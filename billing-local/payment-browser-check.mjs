import { chromium } from 'playwright';
import Stripe from 'stripe';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { once } from 'node:events';
import { createApplication } from './server.mjs';
import { configuration } from './config.mjs';
const secret = 'whsec_browser_fixture';
const config = configuration({ PORT: '17439', S2T_BILLING_MODE: 'test', S2T_BILLING_DATA_DIR: mkdtempSync(tmpdir() + '/s2t-checkout-browser-'), STRIPE_SECRET_KEY: 'sk_test_fixture', STRIPE_WEBHOOK_SECRET: secret });
let created;
const app = createApplication(config, { stripeClient: { checkout: { sessions: {
  create: async (body) => { created = body; return { id: 'cs_test_browser', url: 'https://checkout.stripe.com/c/pay/local-fixture' }; },
  retrieve: async () => ({ id: 'cs_test_browser', livemode: false, payment_link: null, mode: 'payment', currency: 'usd', payment_status: 'paid', amount_total: 500, client_reference_id: created.client_reference_id, metadata: created.metadata, total_details: {}, payment_intent: { id: 'pi_browser', status: 'succeeded', currency: 'usd', livemode: false, amount_received: 500 } }),
} } } });
app.server.listen(config.port, '127.0.0.1');
await once(app.server, 'listening');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  await page.route('https://checkout.stripe.com/**', route => route.fulfill({ body: 'Isolated checkout fixture. No payment.' }));
  await page.goto(config.origin);
  await page.waitForFunction(() => document.querySelector('#purchase').textContent.includes('Buy 500 credits'));
  await page.locator('#open-purchase').click();
  await page.locator('#purchase').click();
  await page.waitForURL('https://checkout.stripe.com/**');
  assert.equal(created.line_items[0].price_data.unit_amount, 500);
  await page.goto(config.origin + '/?checkout=returned');
  await page.waitForFunction(() => !document.querySelector('#account-content').hidden);
  assert.equal(await page.locator('#balance').textContent(), '0.0000');
  assert.match(await page.locator('#status').textContent(), /does not confirm payment/);
  const raw = JSON.stringify({ type: 'checkout.session.completed', livemode: false, data: { object: { id: 'cs_test_browser' } } });
  const signature = Stripe.webhooks.generateTestHeaderString({ payload: raw, secret });
  for (let i = 0; i < 2; i++) {
    const response = await fetch(config.origin + '/api/stripe/webhook', { method: 'POST', body: raw, headers: { 'stripe-signature': signature } });
    assert.equal(response.status, 200);
  }
  await page.reload();
  await page.waitForFunction(() => document.querySelector('#balance').textContent === '500.0000');
  await page.locator('#keys-details > summary').click();
  await page.getByRole('button', { name: 'Create S2T key', exact: true }).click();
  await page.locator('#key-value').waitFor({ state: 'visible' });
  assert.match(await page.locator('#key-value').inputValue(), /^s2t_test_/);
  assert.deepEqual(errors, []);
  console.log('PASS: browser amount selection, account-bound checkout, return without credit grant, signed mock fulfillment, duplicate event, wallet refresh, and test key. No real Stripe calls, screenshots, or clipboard reads.');
} finally { await browser.close(); await app.close(); }
