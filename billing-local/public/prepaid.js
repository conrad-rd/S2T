import { quoteCredits } from './credit-pricing.js';
const $ = id => document.getElementById(id);
let config, purchase, timer, attempt;
const status = text => { $('guest-status').textContent = text; $('guest-status').hidden = !text; };
function amountText(value, digits) {
  const span = document.createElement('span');
  const [whole, fraction] = value.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits }).split('.');
  span.append(whole);
  if (fraction) { const tail = document.createElement('span'); tail.className = 'decimal-places'; tail.textContent = '.' + fraction; span.append(tail); }
  return span;
}
async function api(path, body, headers = {}) {
  const response = await fetch('/api/guest/' + path, { method: body === undefined ? 'GET' : 'POST', credentials: 'same-origin', headers: { ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  const value = await response.json();
  if (!response.ok) { const error = Error(value.error || 'Request failed. Please retry.'); error.status = response.status; throw error; }
  return value;
}
function quote() {
  const cents = Math.round(Number($('guest-amount').value) * 100);
  const valid = $('guest-amount').validity.valid && cents >= 500 && cents <= 10000;
  $('guest-pay').disabled = !valid;
  $('guest-quote').replaceChildren(...(valid ? [amountText(quoteCredits(cents).credits, 4)] : ['—']));
  $('guest-pay').replaceChildren(...(valid ? ['Pay $', amountText(cents / 100, 2)] : ['Choose $5 to $100']));
  document.querySelectorAll('[data-amount]').forEach(button => button.setAttribute('aria-pressed', String(valid && Number(button.dataset.amount) * 100 === cents)));
  return cents;
}
function render(value) {
  purchase = value;
  $('guest-result').hidden = value.state !== 'paid';
  $('guest-key').value = value.key || '';
  $('guest-purchase').hidden = !['pending', 'paid'].includes(value.state) || !config.guestCheckout;
  $('email-opt-in').checked = value.emailOptIn === true;
  $('guest-backup').hidden = false;
  $('guest-code').value = value.recoveryCode;
  $('guest-download').textContent = value.key ? 'Download key and recovery code' : 'Download recovery code';
  $('guest-title').textContent = value.key ? 'Your prepaid key' : 'Prepaid credits';
  $('guest-intro').textContent = value.key ? 'Add credits to this key, or paste it into S2T to start dictating.' : 'Buy credits without signing in.';
  const label = document.createElement('span'); label.className = 'credit-label'; label.textContent = 'credits remaining';
  $('guest-balance').replaceChildren(amountText(value.balance, 4), label);
  if (value.state === 'unavailable') status('This key is unavailable. Contact S2T support about your purchase.');
}
async function refresh() { render(await api('status')); }
document.querySelectorAll('[data-amount]').forEach(button => button.addEventListener('click', () => { $('guest-amount').value = button.dataset.amount; attempt = null; quote(); }));
$('guest-amount').addEventListener('input', () => { attempt = null; quote(); });
$('guest-buy').addEventListener('submit', async event => {
  event.preventDefault();
  const cents = quote();
  $('guest-pay').disabled = true;
  status('Opening secure payment…');
  try {
    const fingerprint = `${cents}:${$('email-opt-in').checked}`;
    if (!attempt || attempt.fingerprint !== fingerprint) attempt = { fingerprint, id: crypto.randomUUID() };
    const { url } = await api('checkout', { cents, emailRecovery: $('email-opt-in').checked, recoveryCode: purchase.recoveryCode }, { 'Idempotency-Key': attempt.id });
    if (new URL(url).origin !== 'https://checkout.stripe.com') throw Error('Payment link is invalid.');
    sessionStorage.setItem('s2t-guest-purchase-count', String(purchase.purchaseCount));
    location.assign(url);
  } catch (error) { status(error.message); quote(); }
});
$('guest-copy').addEventListener('click', async () => {
  try { await navigator.clipboard.writeText(purchase.key); status('Key copied. Paste it into S2T.'); }
  catch { $('guest-key').select(); status('Select and copy your key from the field.'); }
});
$('guest-download').addEventListener('click', () => {
  const file = new Blob([`S2T prepaid purchase\n\n${purchase.key ? `Key: ${purchase.key}\n` : ''}Recovery code: ${purchase.recoveryCode}\nRecover at ${location.origin}/prepaid.html\n\nKeep this file private.\n`], { type: 'text/plain' });
  const url = URL.createObjectURL(file), link = document.createElement('a');
  link.href = url; link.download = 'S2T-prepaid-key.txt'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
});
async function recover(code, emailLink = false) {
  clearTimeout(timer);
  $('guest-result').hidden = true;
  $('guest-key').value = '';
  status('Recovering your purchase…');
  await api('recover', { code: code.trim(), emailLink });
  await refresh(); status('Purchase recovered. This browser now remembers it.');
}
$('code-recovery').addEventListener('submit', async event => {
  event.preventDefault();
  try { await recover($('recover-code').value); $('recover-code').value = ''; } catch (error) { status(error.message); }
});
$('email-recovery').addEventListener('submit', async event => {
  event.preventDefault(); const button = event.target.querySelector('button'); button.disabled = true;
  try { status((await api('email', { email: $('recover-email').value })).message); } catch (error) { status(error.message); }
  finally { button.disabled = false; }
});
async function recoverFromLink() {
  const code = new URLSearchParams(location.hash.slice(1)).get('recover');
  if (!code) return false;
  history.replaceState(null, '', location.pathname + location.search);
  await recover(code, true);
  return true;
}
window.addEventListener('hashchange', () => { recoverFromLink().catch(error => status(error.message)); });
async function start() {
  config = await (await fetch('/api/config')).json();
  $('email-option').hidden = $('email-recovery').hidden = !config.guestEmailRecovery;
  quote();
  if (await recoverFromLink()) return;
  try { await refresh(); }
  catch (error) {
    if (error.status !== 401) throw error;
    if (!config.guestCheckout) { status('Guest checkout is not available yet. Existing purchases can still be recovered below.'); return; }
    await api('start', {}); await refresh();
  }
  if (new URLSearchParams(location.search).get('checkout') === 'returned') {
    let polls = 0;
    const savedCount = sessionStorage.getItem('s2t-guest-purchase-count');
    const previous = savedCount === null ? null : Number(savedCount);
    sessionStorage.removeItem('s2t-guest-purchase-count');
    status('Waiting for payment confirmation. Your credits appear after Stripe confirms the purchase.');
    const poll = async () => {
      try {
        await refresh();
        if (previous !== null && Number.isSafeInteger(previous) && previous >= 0 && purchase.purchaseCount > previous) { status('Payment confirmed. Your credits are ready.'); return; }
        if (++polls < 40) timer = setTimeout(poll, 3000);
        else status('Payment may still be pending. Return to this page later to check your balance.');
      } catch (error) { status(error.message); }
    };
    timer = setTimeout(poll, 3000);
  }
}
start().catch(error => status(error.message));
