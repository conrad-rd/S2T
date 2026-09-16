import test from 'node:test';
import assert from 'node:assert/strict';
import Stripe from 'stripe';
import { openLedger } from '../ledger.mjs';
import { createStripeBilling } from '../stripe-billing.mjs';

test('account-bound checkout fixes amount, retries once, and grants only verified payment', async () => {
  const ledger = openLedger(':memory:', { mode: 'test' });
  const { account } = ledger.createSession();
  let created, retrieved;
  const calls = [];
  const billing = createStripeBilling({ ledger, mode: 'test', secret: 'whsec_fixture', origin: 'http://localhost:4317',
    stripeClient: { checkout: { sessions: {
      create: async (body, options) => { calls.push(options.idempotencyKey); created = body; return { id: 'cs_test_created', url: 'https://checkout.stripe.com/c/pay/fixture' }; },
      retrieve: async () => retrieved,
    } } },
  });
  const result = await billing.checkout(account, 500, 'purchase-fixture-0001');
  await billing.checkout(account, 500, 'purchase-fixture-0001');
  assert.equal(new Set(calls).size, 1);
  assert.equal(created.line_items[0].price_data.unit_amount, 500);
  assert.equal(created.client_reference_id, account);
  assert.equal(result.url, 'https://checkout.stripe.com/c/pay/fixture');
  await assert.rejects(billing.checkout(account, 1000, 'purchase-fixture-0001'));
  assert.equal(ledger.summary(account).balance, 0);
  retrieved = { id: 'cs_test_created', livemode: false, mode: 'payment', currency: 'usd', payment_link: null, payment_status: 'paid', amount_total: 500, client_reference_id: account, metadata: created.metadata, total_details: {}, payment_intent: { id: 'pi_fixture', status: 'succeeded', currency: 'usd', livemode: false, amount_received: 500 } };
  const raw = JSON.stringify({ type: 'checkout.session.completed', livemode: false, data: { object: { id: retrieved.id } } });
  const sig = Stripe.webhooks.generateTestHeaderString({ payload: raw, secret: 'whsec_fixture' });
  await billing.webhook(Buffer.from(raw), sig);
  await billing.webhook(Buffer.from(raw), sig);
  assert.equal(ledger.summary(account).balance, 500);
  retrieved.amount_total = 1000;
  retrieved.payment_intent.amount_received = 1000;
  await assert.rejects(billing.webhook(Buffer.from(raw), sig));
  ledger.close();
});
