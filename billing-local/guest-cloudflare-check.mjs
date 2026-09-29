import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse } from 'miniflare';
import Stripe from 'stripe';
import { chromium } from 'playwright';
const origin = 'https://credits.example.com', secret = 'whsec_guest_fixture';
let session, unpaid = true;
const emails = [], directory = mkdtempSync(tmpdir() + '/s2t-guest-cloudflare-');
const options = enabled => ({ ...convertV4MiniflareOptions({
  name: 'guest-test', modules: true, script: readFileSync(process.env.S2T_BUNDLE_PATH || '../build/cloudflare-bundle/worker.js', 'utf8'), compatibilityDate: '2026-09-16', compatibilityFlags: ['nodejs_compat'],
  durableObjects: { CREDITS: { className: 'CreditsLedger', useSQLite: true } }, durableObjectsPersist: directory,
  bindings: { S2T_BILLING_MODE: 'test', S2T_PUBLIC_ORIGIN: origin, S2T_RESULT_KEY: 'a'.repeat(64), S2T_GUEST_CREDENTIAL_KEY: 'b'.repeat(64), CLERK_PUBLISHABLE_KEY: 'pk_test_' + Buffer.from('accounts.example.com$').toString('base64'), STRIPE_SECRET_KEY: 'rk_test_fixture', STRIPE_WEBHOOK_SECRET: secret, S2T_GUEST_CHECKOUT: enabled ? 'enabled' : '', S2T_RECOVERY_EMAIL_KEY: 'fixture', S2T_RECOVERY_EMAIL_FROM: 'keys@example.com' },
  serviceBindings: { ASSETS: async request => {
    const file = new URL(request.url).pathname;
    assert.ok(!file.includes('..'));
    return new WorkerResponse(readFileSync('public' + file), { headers: { 'Content-Type': file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : file.endsWith('.html') ? 'text/html' : 'application/octet-stream' } });
  } },
  outboundService: async request => {
    const url = new URL(request.url);
    if (url.origin === 'https://api.resend.com') { emails.push(await request.json()); return WorkerResponse.json({ id: 'mail_fixture' }); }
    assert.equal(url.origin, 'https://api.stripe.com');
    if (request.method === 'POST' && url.pathname === '/v1/checkout/sessions') {
      const form = new URLSearchParams(await request.text());
      assert.equal(form.get('success_url'), origin + '/prepaid.html?checkout=returned');
      session = { id: 'cs_test_guest', url: 'https://checkout.stripe.com/c/pay/cs_test_guest', livemode: false, mode: 'payment', currency: 'usd', payment_status: 'paid', amount_total: 500, client_reference_id: form.get('client_reference_id'), metadata: { s2t_order: form.get('metadata[s2t_order]') }, total_details: {}, payment_intent: { id: 'pi_guest', status: 'succeeded', currency: 'usd', livemode: false, amount_received: 500 }, customer_details: { email: 'buyer@example.com' } };
      return WorkerResponse.json(session);
    }
    return WorkerResponse.json({ ...session, payment_status: unpaid ? 'unpaid' : 'paid' });
  },
}), resourcePersistencePath: directory });
let mf = new Miniflare(options(true)), browser;
const call = (path, { data, cookie, headers = {} } = {}) => mf.dispatchFetch(origin + path, { method: data === undefined ? 'GET' : 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}), ...headers }, ...(data === undefined ? {} : { body: JSON.stringify(data) }) });
const read = async (response, expected = 200) => { const data = await response.json(); assert.equal(response.status, expected, JSON.stringify(data)); return data; };
async function webhook() {
  const event = { livemode: false, type: 'checkout.session.completed', data: { object: { id: session.id } } };
  const signature = Stripe.webhooks.generateTestHeaderString({ payload: JSON.stringify(event), secret });
  await read(await call('/api/stripe/webhook', { data: event, headers: { 'stripe-signature': signature } }));
}
try {
  assert.equal((await read(await call('/api/config'))).guestCheckout, true);
  await read(await call('/api/guest/start', { data: {}, headers: { Origin: 'https://evil.example' } }), 403);
  await read(await call('/api/guest/status'), 401);
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const context = await browser.newContext(), page = await context.newPage(), errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await context.route('**/*', async route => {
    const request = route.request();
    if (request.url().startsWith('https://checkout.stripe.com/')) return route.fulfill({ body: 'Mock checkout. No payment.' });
    if (!request.url().startsWith(origin)) return route.abort();
    const response = await mf.dispatchFetch(request.url(), { method: request.method(), headers: await request.allHeaders(), ...(request.postData() ? { body: request.postData() } : {}) });
    await route.fulfill({ status: response.status, headers: Object.fromEntries(response.headers), body: Buffer.from(await response.arrayBuffer()) });
  });
  await page.goto(origin + '/prepaid.html');
  await page.locator('#guest-pay').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#email-opt-in').isChecked(), false);
  assert.equal(await page.locator('#guest-backup').getAttribute('open'), null);
  assert.equal(await page.locator('#guest-code').isVisible(), false);
  for (const width of [320, 375, 768, 1280]) {
    await page.setViewportSize({ width, height: 900 });
    await page.locator('[data-amount="100"]').click();
    assert.equal(await page.locator('#guest-quote').textContent(), '11,800.0000');
    assert.equal(await page.locator('#guest-pay').textContent(), 'Pay $100.00');
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Overflow at ${width}`);
    const buttons = await page.locator('.prepaid-presets button').evaluateAll(items => items.map(item => { const r = item.getBoundingClientRect(); return { left: r.left, right: r.right }; }));
    assert.ok(buttons.every((item, i) => i === 0 || item.left >= buttons[i - 1].right));
  }
  await page.locator('[data-amount="5"]').click();
  await page.locator('#guest-backup summary').click();
  assert.equal(await page.locator('#guest-code').isVisible(), true);
  await page.locator('#guest-backup summary').click();
  const recoveryCode = await page.locator('#guest-code').inputValue();
  assert.match(recoveryCode, /^[a-f0-9]{64}$/);
  await page.locator('#email-opt-in').check();
  await page.locator('#guest-pay').click();
  await page.waitForURL('https://checkout.stripe.com/**');
  const cookie = (await context.cookies(origin)).map(item => `${item.name}=${item.value}`).join('; ');
  await read(await call('/api/keys', { cookie, data: {} }), 401);
  await read(await call('/api/device/approve', { cookie, data: { userCode: 'AA'.repeat(6) } }), 401);
  await webhook();
  assert.equal((await read(await call('/api/guest/status', { cookie }))).state, 'pending');
  unpaid = false; await webhook(); await webhook();
  await page.goto(origin + '/prepaid.html?checkout=returned');
  await page.locator('#guest-result').waitFor({ state: 'visible' });
  const key = await page.locator('#guest-key').inputValue();
  assert.match(key, /^s2t_test_/);
  assert.equal(await page.locator('#guest-buy').isVisible(), true);
  assert.equal(await page.locator('#guest-balance .decimal-places').textContent(), '.0000');
  const balance = await read(await call('/api/v1/balance', { headers: { Authorization: 'Bearer ' + key } }));
  assert.equal(balance.balance, 500); assert.equal(balance.keys.length, 1);
  const other = await call('/api/guest/start', { data: {} });
  const otherCookie = other.headers.get('set-cookie').split(';')[0]; await read(other);
  assert.equal((await read(await call('/api/guest/status', { cookie: otherCookie }))).key, null);
  await context.clearCookies(); await page.goto(origin + '/prepaid.html');
  await page.locator('#guest-pay').waitFor({ state: 'visible' });
  await page.locator('#guest-recovery summary').click();
  await page.locator('#recover-code').fill(recoveryCode); await page.locator('#code-recovery button').click();
  await page.locator('#guest-result').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#guest-key').inputValue(), key);
  await read(await call('/api/guest/email', { data: { email: 'buyer@example.com' } }));
  assert.equal(emails.length, 1);
  const link = emails[0].text.match(/https:\/\/\S+#recover=[a-f0-9]+/)[0];
  await context.clearCookies(); await page.goto(link);
  await page.waitForURL(url => url.hash === '');
  await page.locator('#guest-result').waitFor({ state: 'visible' });
  assert.equal(await page.locator('#guest-key').inputValue(), key);
  assert.equal(new URL(page.url()).hash, '');
  await read(await call('/api/guest/recover', { data: { code: link.split('=')[1], emailLink: true } }), 401);
  assert.deepEqual(errors, []);
  await browser.close(); browser = null;
  await mf.dispose(); mf = new Miniflare(options(false));
  await read(await call('/api/guest/start', { data: {} }), 503);
  assert.equal((await read(await call('/api/guest/status', { cookie }))).key, key);
  console.log('PASS: Guest browser checkout, payment verification, one key, isolation, CSRF, optional email, code/email recovery, restart persistence. No real payments, emails, screenshots, or provider calls.');
} finally { if (browser) await browser.close(); await mf.dispose(); }
