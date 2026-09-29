import { quoteCredits } from './credit-pricing.js';
const $ = (id) => document.getElementById(id);
let account;
let clerk;
let purchaseAttempt;
let refreshGeneration = 0;
let identityGeneration = 0;
class StaleIdentity extends Error {}
let limitsLinkPending = location.hash === '#keys-details';
function revealKeyLimits() {
  if (!limitsLinkPending || !account) return;
  const section = $('keys-details');
  if (section.tagName === 'DETAILS') section.open = true;
  section.scrollIntoView({ block: 'start' });
  limitsLinkPending = false;
}
window.addEventListener('hashchange', () => {
  limitsLinkPending = location.hash === '#keys-details';
  revealKeyLimits();
});
let usageDays = 30;
let chartSignature = '';
window.addEventListener('resize', () => {
  $('chart-detail').hidden = $('chart-connector').hidden = true;
  for (const day of $('usage-chart').children) delete day.dataset.active;
});
const providerName = name => ({ assemblyai: 'AssemblyAI', openrouter: 'OpenRouter' })[name] ?? name;
const requestName = request => request.operation === 'transcription' ? 'Transcription' : request.operation === 'decisions' ? 'Jev cleanup' : request.operation === 'cleanup' ? 'Text cleanup' : providerName(request.provider);
const chartDate = value => new Date(value + 'T00:00:00Z').toLocaleDateString(undefined, { month: 'short', day: 'numeric', timeZone: 'UTC' });
const connectionCode = new URLSearchParams(location.search).get("connect");
if (connectionCode && /^[A-F0-9]{12}$/.test(connectionCode)) sessionStorage.setItem("s2t-connect-code", connectionCode);
const pendingConnection = sessionStorage.getItem("s2t-connect-code");
if (pendingConnection) {
  $("connect-panel").hidden = false;
  $("connect-code").textContent = pendingConnection.match(/.{1,4}/g).join("-");
}
$("connect-approve").addEventListener("click", async () => {
  const identity = identityGeneration;
  $("connect-approve").disabled = true;
  try {
    await api("/api/device/approve", { userCode: pendingConnection }, {}, identity);
    if (identity !== identityGeneration) return;
    sessionStorage.removeItem("s2t-connect-code");
    $("connect-status").textContent = "Connected. Return to S2T.";
    await refresh();
    if (identity !== identityGeneration) return;
  } catch (error) {
    if (error instanceof StaleIdentity || identity !== identityGeneration) return;
    $("connect-status").textContent = error.message;
    $("connect-approve").disabled = false;
  }
});
const money = (cents) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);
const number = (value) =>
  new Intl.NumberFormat("en-US", { maximumFractionDigits: 4 }).format(value);
const creditNumber = (value) =>
  new Intl.NumberFormat("en-US", { minimumFractionDigits: 4, maximumFractionDigits: 4 }).format(value);
function amountText(text) {
  const content = document.createElement('span');
  for (const part of text.split(/(?<=\d)(\.\d+)/)) {
    if (/^\.\d+$/.test(part)) {
      const decimals = document.createElement('span');
      decimals.className = 'decimal-places';
      decimals.textContent = part;
      content.append(decimals);
    } else content.append(part);
  }
  return content;
}
function amount() {
  return Math.round(Number($("amount").value) * 100);
}
function status(message) {
  $("status").textContent = message;
  $('purchase-status').textContent = message;
  $('purchase-status').hidden = !message;
}
async function api(path, body, headers = {}, identity = identityGeneration) {
  const session = clerk?.session;
  const token = session ? await session.getToken({ template: "s2t" }) : null;
  if (identity !== identityGeneration || session !== clerk?.session) throw new StaleIdentity();
  const res = await fetch(path, {
    method: body === undefined ? "GET" : "POST",
    headers: { ...(body === undefined ? {} : { "Content-Type": "application/json" }), ...(token ? { Authorization: `Bearer ${token}` } : {}), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const data = await res.json();
  if (identity !== identityGeneration || session !== clerk?.session) throw new StaleIdentity();
  if (!res.ok) throw Error(data.error);
  return data;
}
function updateAmount() {
  const cents = amount(),
    valid = $("amount").validity.valid && cents >= 500 && cents <= 10000;
  const quotedCredits = valid ? quoteCredits(cents).credits : 0;
  $("preview-credits").replaceChildren(amountText(valid ? number(quotedCredits) : "—"));
  $("purchase").disabled = !valid || !account || (account.mode !== "demo" && !account.checkoutEnabled) || account.frozen;
  $("purchase").replaceChildren(amountText(valid ? account?.mode === "demo" ? `Try a ${money(cents)} demo top-up` : `Continue to pay ${money(cents)} for ${number(quotedCredits)} credits` : "Choose $5 to $100"));
  document
    .querySelectorAll("[data-amount]")
    .forEach((b) => b.setAttribute("aria-pressed", Number(b.dataset.amount) * 100 === cents));
}
function empty(container, text) {
  const p = document.createElement("p");
  p.className = "muted";
  p.textContent = text;
  container.append(p);
}
function keyLimitForm(limits = {}, id = 'new') {
  const form = document.createElement('form');
  form.className = 'key-limit-form';
  const fields = document.createElement('div'); fields.className = 'key-limit-fields'; form.append(fields);
  function field(name, title, input) {
    const label=document.createElement('label');label.textContent=title;input.id=`key-${id}-${name}`;input.name=name;
    label.htmlFor=input.id;input.setAttribute('aria-label',title);label.append(input);fields.append(label);return input;
  }
  function input(type,value=''){const el=document.createElement('input');el.type=type;el.value=value;return el;}
  function select(choices){const el=document.createElement('select');for(const [value,title] of choices){const option=document.createElement('option');option.value=value;option.textContent=title;el.append(option);}return el;}
  const cap=field('limitCredits','Credit limit',input('number',limits.limitCredits ?? ''));cap.min='0';cap.max='1000000';cap.step='0.01';cap.placeholder='No limit';
  const reset=field('reset','Reset allowance',select([['never','Never'],['1','Daily'],['3','Every 3 days'],['custom','Custom interval']]));
  reset.value=limits.resetDays == null ? 'never' : [1,3].includes(limits.resetDays) ? String(limits.resetDays) : 'custom';
  const days=field('resetDays','Days between resets',input('number',limits.resetDays ?? 7));days.min='1';days.max='3650';days.step='1';
  const expiry=field('expiry','Key expires',select([['after','After a number of days'],['date','At a date and time'],['never','Never']]));
  expiry.value=Object.hasOwn(limits,'expiresAt') ? limits.expiresAt == null ? 'never' : 'date' : 'after';
  const expiresDays=field('expiresDays','Days until expiry',input('number',90));expiresDays.min='1';expiresDays.max='3650';expiresDays.step='1';
  const localDate=value=>{const date=new Date(value);return new Date(date-date.getTimezoneOffset()*60000).toISOString().slice(0,16);};
  const originalDate=limits.expiresAt ? localDate(limits.expiresAt) : '';
  const expiresDate=field('expiresDate','Expiry in your local time',input('datetime-local',originalDate));
  const help=document.createElement('p');help.className='muted';help.textContent='Resets use midnight UTC. Pending requests count toward the limit. Expiry is permanent.';form.append(help);
  function visibility(){
    reset.disabled=cap.value==='';
    days.parentElement.hidden=reset.disabled || reset.value!=='custom';days.required=!days.parentElement.hidden;days.disabled=days.parentElement.hidden;
    expiresDays.parentElement.hidden=expiry.value!=='after';expiresDays.required=expiry.value==='after';expiresDays.disabled=expiry.value!=='after';
    expiresDate.parentElement.hidden=expiry.value!=='date';expiresDate.required=expiry.value==='date';expiresDate.disabled=expiry.value!=='date';
  }
  form.addEventListener('input',()=>{form.dataset.dirty='true';visibility();});form.addEventListener('change',()=>{form.dataset.dirty='true';visibility();});visibility();
  form.readLimits=()=>{
    if(!form.reportValidity()) throw Error('Check the key limit settings.');
    return {limitCredits:cap.value===''?null:Number(cap.value),resetDays:cap.value===''||reset.value==='never'?null:Number(reset.value==='custom'?days.value:reset.value),
      expiresAt:expiry.value==='never'?null:expiry.value==='after'?Date.now()+Number(expiresDays.value)*86400000:expiresDate.value===originalDate?limits.expiresAt:new Date(expiresDate.value).getTime()};
  };
  return form;
}
const newKeyForm=keyLimitForm();
$('new-key-settings').append(newKeyForm);
newKeyForm.addEventListener('submit',event=>{event.preventDefault();$('create-key').click();});
function renderKeyLimits(row,key) {
  const limits=key.limits ?? {limitCredits:null,expiresAt:key.expires};
  const expired=key.expires<=Date.now();
  const description=document.createElement('p');description.className='muted key-limit-summary';
  description.append(amountText(expired?'Expired permanently':limits.limitCredits==null?'No key credit limit':`${number(limits.remainingCredits)} of ${number(limits.limitCredits)} credits available${limits.resetDays ? ` · Resets every ${limits.resetDays} ${limits.resetDays===1?'day':'days'}`:' · Lifetime'}`));
  if(!expired && limits.resetsAt) description.append(` · Next reset ${new Date(limits.resetsAt).toLocaleString()}`);
  if(!expired && limits.expiresAt) description.append(` · Expires ${new Date(limits.expiresAt).toLocaleString()}`);
  row.append(description);
  if(expired)return;
  const details=document.createElement('details');details.className='key-limit-details';
  const summary=document.createElement('summary');summary.textContent='Limits and expiry';details.append(summary);
  const form=keyLimitForm(limits,key.id);const save=document.createElement('button');save.className='secondary';save.type='submit';save.textContent='Save limits';form.append(save);details.append(form);row.append(details);
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    const identity = identityGeneration;
    try {
      const value=form.readLimits();save.disabled=true;
      await api('/api/keys/limits',{id:key.id,...value},{},identity);
      if(identity!==identityGeneration)return;
      form.dataset.dirty='false';if(form.contains(document.activeElement)) document.activeElement.blur();await refresh();if(identity!==identityGeneration)return;status('Key limits saved. Existing spending still counts.');
    } catch(error){if(error instanceof StaleIdentity || identity!==identityGeneration)return;status(error.message);save.disabled=false;}
  });
}

async function refresh() {
  const generation = ++refreshGeneration;
  document.querySelector('.usage-card').setAttribute('aria-busy', 'true');
  let updated;
  try { updated = await api(`/api/account?days=${usageDays}`); }
  catch (error) { if (error instanceof StaleIdentity || generation !== refreshGeneration) return; throw error; }
  finally { if (generation === refreshGeneration) document.querySelector('.usage-card').removeAttribute('aria-busy'); }
  if (generation !== refreshGeneration) return;
  account = updated;
  $('balance').replaceChildren(amountText(creditNumber(account.available)));
  $("held-balance").replaceChildren(amountText(account.reserved > 0
      ? `${creditNumber(account.reserved)} credits reserved for pending requests.`
      : ""));
  $('held-balance').hidden = account.reserved <= 0;
  const demo = account.mode === "demo";
  $("account-content").hidden = false;
  $("mode-badge").textContent = demo ? "Local preview" : account.mode === "test" ? "Stripe sandbox" : "S2T credits";
  $('mode-badge').hidden = account.mode === 'live';
  $('account-warning').hidden = !account.paused && !account.frozen;
  $('account-warning').textContent = account.frozen ? 'This account is frozen. Contact support before adding credits.' : account.paused ? 'Credit usage is paused by the service. Changing key limits will not resume usage. Contact info@conrad-baulig.com for help. Your balance is preserved.' : '';
  renderUsage(account.usage);
  $("purchase-note").textContent = demo ? "Demo only. No payment is taken and these credits cannot buy API usage." : account.mode === "test" ? account.realProviders ? "Stripe sandbox for approved testers. Payments are simulated; dictation uses real providers." : "Stripe sandbox. Use test payment details. Provider requests remain synthetic." : "Pay once through Stripe. No subscription.";
  $("create-key").textContent = demo ? "Create demo key" : "Create S2T key";
  $("demo-panel").hidden = !demo;
  $("footer-mode").textContent = demo ? "Local preview · No real payments" : account.mode === "test" ? account.realProviders ? "Private sandbox · Real dictation" : "Sandbox · No real provider usage" : "";
  $('footer-mode').hidden = account.mode === 'live';
  const active = account.keys.filter((k) => !k.revoked && k.expires > Date.now());
  $("create-key").disabled = active.length >= 10 || account.frozen;
  revealKeyLimits();
  $("key-count").textContent = active.length
    ? `${active.length} active`
    : "";
  const keys = $("key-list");
  if (!keys.querySelector('form[data-dirty="true"]') && !keys.contains(document.activeElement)) {
  keys.replaceChildren();
  for (const key of account.keys.filter(key => !key.revoked)) {
    const row = document.createElement("div");
    row.className = "key-row";
    const label = document.createElement("span");
    label.textContent = `•••• ${key.suffix}`;
    const revoke = document.createElement("button");
    revoke.className = "secondary";
    revoke.textContent = "Revoke";
    revoke.setAttribute("aria-label", `Revoke key ending ${key.suffix}`);
    revoke.addEventListener("click", async () => {
      const identity = identityGeneration;
      revoke.disabled = true;
      try {
        await api("/api/keys/revoke", { id: key.id }, {}, identity);
        if (identity !== identityGeneration) return;
        if ($("key-value").value.endsWith(key.suffix)) {
          $("key-value").value = "";
          $("key-result").hidden = true;
        }
        row.remove();
        await refresh();
        if (identity !== identityGeneration) return;
        status("Key revoked. It can no longer start requests.");
      } catch (e) {
        if (e instanceof StaleIdentity || identity !== identityGeneration) return;
        status(e.message);
        revoke.disabled = false;
      }
    });
    const header=document.createElement("div");header.className="key-row-header";header.append(label,revoke);row.append(header);
    renderKeyLimits(row,key);
    keys.append(row);
  }
  }
  $("service-state").textContent = account.paused
    ? "Spending paused"
    : account.frozen
      ? "Account frozen"
      : "Limits active";
  $("try-request").disabled =
    account.mode !== "demo" || account.paused || account.frozen || account.available <= 0;
  const history = $("history");
  history.replaceChildren();
  if (!account.purchases.length) empty(history, "Your first top-up will appear here.");
  for (const p of account.purchases) {
    const row = document.createElement("div");
    row.className = "transaction";
    const label = document.createElement("span");
    label.replaceChildren(amountText(`${money(p.cents)} · ${p.id.startsWith("demo_") ? "Demo top-up" : "Stripe payment"}`));
    const date = document.createElement("small");
    date.textContent = new Date(p.created).toLocaleString();
    if (p.reversed) date.append(amountText(` · ${money(p.reversed)} reversed`));
    label.append(date);
    const value = document.createElement("strong");
    value.replaceChildren(amountText(Number.isFinite(p.netCredits) ? `+${number(p.netCredits)} credits` : 'See payment receipt'));
    row.append(label, value);
    history.append(row);
  }
  const requests = $("requests");
  $('activity-count').textContent = account.requests.length ? `${account.requests.length} recent` : '';
  requests.replaceChildren();
  if (!account.requests.length)
    empty(requests, demo ? "No requests yet. Try a metered demo request above." : "Your dictation and cleanup usage will appear here.");
  for (const r of account.requests) {
    const row = document.createElement("div");
    row.className = "transaction";
    const label = document.createElement("span");
    label.textContent = `${requestName(r)}${r.state === 'settled' ? '' : ' · ' + r.state}`;
    const date = document.createElement("small");
    date.textContent = new Date(r.created).toLocaleString();
    label.append(date);
    const cost = document.createElement("strong");
    cost.replaceChildren(amountText(
      r.state === "settled"
        ? `${creditNumber(r.charged / 5000)} credits`
        : r.state === "released"
          ? "Released"
          : `${creditNumber(r.reserved / 5000)} reserved`));
    row.append(label, cost);
    requests.append(row);
  }
  updateAmount();
}
function renderUsage(usage) {
  if (!usage) {
    $('usage-total').textContent = '—';
    $('last-used').textContent = 'Unavailable';
    $('last-device').textContent = 'Unavailable';
    return;
  }
  document.querySelectorAll('[data-days]').forEach(button => button.setAttribute('aria-pressed', Number(button.dataset.days) === usage.days));
  $('usage-total').replaceChildren(amountText(creditNumber(usage.spentCredits)));
  const last = usage.lastUsed;
  $('last-used').textContent = last ? new Date(last.at).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) : 'Not used yet';
  $('last-used-detail').textContent = last ? new Date(last.at).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', timeZoneName: 'short' }) : '';
  $('last-device').textContent = last?.device?.name ?? (last ? 'Not recorded' : '—');
  $('device-detail').textContent = last?.device ? `Device ${last.device.suffix}` : '';
  const signature = JSON.stringify(usage.series);
  if (signature !== chartSignature) {
    chartSignature = signature;
    const chart = $('usage-chart');
    chart.replaceChildren();
    chart.style.gridTemplateColumns = `repeat(${usage.series.length}, minmax(0, 1fr))`;
    const max = Math.max(...usage.series.map(day => day.credits), 0);
    const detail = $('chart-detail'), connector = $('chart-connector');
    const hideDetail = () => {
      detail.hidden = connector.hidden = true;
      detail.replaceChildren();
      for (const child of chart.children) delete child.dataset.active;
    };
    hideDetail();
    const axis = $('chart-y-axis');
    axis.replaceChildren();
    for (const fraction of (max >= .0004 ? [1, .75, .5, .25, 0] : max ? [1, 0] : [0])) {
      const tick = document.createElement('span');
      tick.replaceChildren(amountText(creditNumber(max * fraction)));
      tick.style.top = `${(1 - fraction) * 100}%`;
      axis.append(tick);
    }
    chart.onfocusout = event => { if (!chart.contains(event.relatedTarget)) hideDetail(); };
    const svgNS = 'http://www.w3.org/2000/svg';
    const strokes = Array.from({ length: 28 }, (_, row) => {
      const y = 220 - row * 8;
      return `M2 ${y}h20a2 2 0 0 1 0 4H2a2 2 0 0 1 0-4Z`;
    }).join('');
    usage.series.forEach((day, index) => {
      const button = document.createElement('button');
      button.className = 'chart-day';
      button.dataset.empty = day.credits === 0;
      button.tabIndex = index === usage.series.length - 1 ? 0 : -1;
      const label = `${chartDate(day.day)} · ${creditNumber(day.credits)} credits · ${day.requests} request${day.requests === 1 ? '' : 's'}`;
      button.setAttribute('aria-label', label);
      const bar = document.createElement('span');
      bar.className = 'chart-bar';
      bar.style.setProperty('--height', `${max ? day.credits / max * 100 : 0}%`);
      bar.setAttribute('aria-hidden', 'true');
      const marks = document.createElementNS(svgNS, 'svg');
      marks.setAttribute('viewBox', '0 0 24 224');
      marks.setAttribute('preserveAspectRatio', 'none');
      marks.classList.add('chart-strokes');
      const path = document.createElementNS(svgNS, 'path');
      path.setAttribute('d', strokes);
      marks.append(path);
      bar.append(marks);
      button.append(bar);
      const describe = event => {
        detail.replaceChildren(amountText(`${creditNumber(day.credits)} credits`));
        detail.hidden = connector.hidden = false;
        const wrap = chart.parentElement.getBoundingClientRect();
        const bounds = (day.credits ? bar : button).getBoundingClientRect();
        const pointer = event && Number.isFinite(event.clientX);
        const x = (pointer ? event.clientX : bounds.left + bounds.width / 2) - wrap.left;
        const y = (pointer ? event.clientY : day.credits ? bounds.top : bounds.bottom) - wrap.top;
        const width = detail.offsetWidth, height = detail.offsetHeight;
        const gap = 32;
        const right = bounds.right - wrap.left + gap;
        const leftSide = bounds.left - wrap.left - gap - width;
        const onRight = right + width <= wrap.width;
        const left = Math.max(0, Math.min(wrap.width - width, onRight ? right : leftSide));
        const top = Math.min(y - gap - height, bounds.top - wrap.top - gap - height);
        detail.style.left = `${left}px`;
        detail.style.top = `${top}px`;
        const endX = onRight ? left : left + width;
        const endY = top + height / 2;
        connector.style.left = `${x}px`;
        connector.style.top = `${y}px`;
        connector.style.width = `${Math.hypot(endX - x, endY - y)}px`;
        connector.style.transform = `rotate(${Math.atan2(endY - y, endX - x)}rad)`;
        for (const child of chart.children) delete child.dataset.active;
        button.dataset.active = 'true';
      };
      bar.addEventListener('pointerenter', describe);
      bar.addEventListener('pointermove', describe);
      bar.addEventListener('pointerleave', hideDetail);
      bar.addEventListener('pointercancel', hideDetail);
      button.addEventListener('focus', () => { if (button.matches(':focus-visible')) describe(); });
      button.addEventListener('keydown', event => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const target = event.key === 'Home' ? 0 : event.key === 'End' ? usage.series.length - 1 : Math.max(0, Math.min(usage.series.length - 1, index + (event.key === 'ArrowLeft' ? -1 : 1)));
        for (const child of chart.children) child.tabIndex = -1;
        chart.children[target].tabIndex = 0;
        chart.children[target].focus();
      });
      chart.append(button);
    });
    $('chart-start').textContent = chartDate(usage.series[0].day);
    $('chart-end').textContent = chartDate(usage.series.at(-1).day);
    $('usage-empty').hidden = usage.requestCount > 0;
  }
  const providers = $('provider-usage');
  providers.replaceChildren();
  for (const item of usage.providers) {
    const line = document.createElement('span'), dot = document.createElement('i'), value = document.createElement('strong');
    dot.setAttribute('aria-hidden', 'true');
    value.replaceChildren(amountText(`${creditNumber(item.credits)} credits`));
    line.append(dot, document.createTextNode(providerName(item.provider)), value);
    providers.append(line);
  }
}
document.querySelectorAll('[data-days]').forEach(button => button.addEventListener('click', async () => {
  usageDays = Number(button.dataset.days);
  try { await refresh(); }
  catch (error) { usageDays = account?.usage?.days ?? 30; status(error.message); }
}));
$('open-purchase').addEventListener('click', () => { $('purchase-status').hidden = true; $('purchase-dialog').showModal(); });
$('close-purchase').addEventListener('click', () => $('purchase-dialog').close());
$("amount").addEventListener("input", updateAmount);
document.querySelectorAll("[data-amount]").forEach((b) =>
  b.addEventListener("click", () => {
    $("amount").value = b.dataset.amount;
    updateAmount();
  }),
);
$("purchase").addEventListener("click", async () => {
  const identity = identityGeneration;
  $("purchase").disabled = true;
  try {
    if (account.mode === "demo") {
      await api("/api/demo/purchase", { cents: amount() }, {}, identity);
      if (identity !== identityGeneration) return;
      await refresh();
      if (identity !== identityGeneration) return;
      status("Demo credits added. No payment was taken.");
      $('purchase-dialog').close();
    } else {
      if (!purchaseAttempt || purchaseAttempt.cents !== amount()) purchaseAttempt = { cents: amount(), id: crypto.randomUUID() };
      const checkout = await api("/api/checkout", { cents: purchaseAttempt.cents }, { "Idempotency-Key": purchaseAttempt.id }, identity);
      if (identity !== identityGeneration) return;
      const url = new URL(checkout.url);
      if (url.origin !== "https://checkout.stripe.com") throw Error("Checkout returned an unexpected address.");
      location.assign(url.href);
    }
  } catch (e) {
    if (!(e instanceof StaleIdentity) && identity === identityGeneration) status(e.message);
  } finally {
    if (identity === identityGeneration) updateAmount();
  }
});
$("create-key").addEventListener("click", async () => {
  const identity = identityGeneration;
  $("create-key").disabled = true;
  try {
    const data = await api("/api/keys", newKeyForm.readLimits(), {}, identity);
    if (identity !== identityGeneration) return;
    $("key-result").hidden = false;
    $("key-value").value = data.key;
    await refresh();
    if (identity !== identityGeneration) return;
    status(
      account.mode === "live" || account.realProviders ? "S2T key created. Copy it now and save it in the Mac app." : "Test key created. Copy it now. Requests use synthetic providers.",
    );
  } catch (e) {
    if (e instanceof StaleIdentity || identity !== identityGeneration) return;
    status(e.message);
    $("create-key").disabled = false;
  }
});
$("copy-key").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("key-value").value);
    status("S2T key copied.");
  } catch {
    $("key-value").select();
    status("Select and copy the key from the field.");
  }
});
$("try-request").addEventListener("click", async () => {
  const identity = identityGeneration;
  $("try-request").disabled = true;
  $("request-result").textContent = "Reserving credits and running the synthetic request…";
  try {
    const result = await api("/api/demo/request", {}, { "Idempotency-Key": crypto.randomUUID() }, identity);
    if (identity !== identityGeneration) return;
    $("request-result").replaceChildren(amountText(
      result.state === "settled"
        ? `Completed. Charged ${creditNumber(result.chargedCredits)} credit; the unused reservation was released.`
        : "Outcome uncertain. Credits remain reserved and new spending is paused."));
    await refresh();
  } catch (e) {
    if (e instanceof StaleIdentity || identity !== identityGeneration) return;
    $("request-result").textContent = e.message;
    await refresh();
  }
});
async function start() {
  const config = await (await fetch("/api/config")).json();
  $("guest-entry").hidden = !config.guestCheckout;
  $("mode-badge").textContent = config.mode === "demo" ? "Local preview" : config.mode === "test" ? "Stripe sandbox" : "S2T credits";
  $("footer-mode").textContent = config.mode === "demo" ? "Local preview · No real payments" : config.mode === "test" ? "Sandbox · No real payments" : "";
  $('mode-badge').hidden = config.mode === 'live';
  $('footer-mode').hidden = config.mode === 'live';
  if (config.clerk) {
    const load = (path, attributes = {}) => new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = config.clerk.origin + path;
      script.crossOrigin = "anonymous";
      for (const [name, value] of Object.entries(attributes)) script.setAttribute(name, value);
      script.onload = resolve;
      script.onerror = () => reject(Error("Sign-in could not load. Please reload the page."));
      document.head.append(script);
    });
    await load("/npm/@clerk/ui@1/dist/ui.browser.js");
    await load("/npm/@clerk/clerk-js@6/dist/clerk.browser.js", { "data-clerk-publishable-key": config.clerk.publishableKey });
    clerk = window.Clerk;
    await clerk.load({ telemetry: false, ui: { ClerkUI: window.__internal_ClerkUICtor } });
    let lastUser;
    clerk.addListener(({ user }) => {
      if (lastUser === user?.id) return;
      lastUser = user?.id;
      identityGeneration++;
      refreshGeneration++;
      account = null;
      purchaseAttempt = null;
      $('connect-approve').disabled = !user;
      $('connect-status').textContent = '';
      $('create-key').disabled = !user;
      $('try-request').disabled = !user;
      $('request-result').textContent = '';
      $("key-value").value = "";
      $("key-result").hidden = true;
      $("account-content").hidden = true;
      $('purchase-dialog').close();
      chartSignature = '';
      $('chart-detail').hidden = $('chart-connector').hidden = true;
      usageDays = 30;
      for (const id of ['balance','last-used','last-used-detail','last-device','device-detail','usage-total','usage-chart','chart-y-axis','chart-detail','provider-usage','requests','history','key-list']) $(id).replaceChildren();
      status('');
      $("sign-in").hidden = !!user;
      if (user) { clerk.unmountSignIn($("sign-in")); clerk.mountUserButton($("user-button")); refresh().catch(e => status(e.message)); }
      else { clerk.mountSignIn($("sign-in")); }
    });
    if (!clerk.user) { $("sign-in").hidden = false; clerk.mountSignIn($("sign-in")); }
  } else if (config.mode !== "live") await refresh();
  else throw Error("Customer sign-in has not been configured.");
  const returned = new URLSearchParams(location.search).get("checkout");
  if (returned === "returned") status("Checking your balance. A checkout return alone does not confirm payment; credits appear after Stripe confirms it.");
  if (returned === "cancelled") status("Checkout cancelled. No credits were added by this page.");
}
start().catch(e => status(e.message));
updateAmount();
window.addEventListener("focus", () => { if (account) refresh().catch(e => status(e.message)); });
setInterval(() => { if (account && !document.hidden) refresh().catch(e => status(e.message)); }, 30000);
