import test from 'node:test';
import assert from 'node:assert/strict';
import Stripe from 'stripe';
import { openLedger } from '../ledger.mjs';
import { createGuestPurchases, guestCookie, guestToken, recoveryMailer } from '../guest-purchases.mjs';
import { createStripeBilling } from '../stripe-billing.mjs';

function fixture() {
  let time = Date.now();
  const ledger = openLedger(':memory:', { mode: 'test', now: () => time });
  const emails = [];
  const guests = createGuestPurchases({ ledger, mode: 'test', encryptionKey: Buffer.alloc(32, 7), origin: 'https://credits.example', sendEmail: async value => emails.push(value) });
  const { token } = guests.start();
  const account = guests.account(token).account;
  const pay = () => { ledger.grant({ account, cents: 500, session: 'cs_fixture', intent: 'pi_fixture' }); guests.fulfilled({ client_reference_id: account, customer_details: { email: 'buyer@example.com' } }); };
  return { ledger, guests, token, account, emails, pay, advance: ms => time += ms };
}
test('unpaid guests cannot obtain a key; repeated fulfillment and visits reveal exactly one usable key', () => {
  const f = fixture();
  try {
    assert.equal(f.guests.status(f.token).key, null);
    assert.equal(f.guests.start(f.token).token, f.token);
    f.pay();
    const first = f.guests.status(f.token);
    f.pay();
    assert.equal(f.guests.status(f.token).key, first.key);
    assert.equal(f.ledger.authenticate(first.key).account, f.account);
    assert.equal(f.ledger.summary(f.account).keys.length, 1);
    assert.equal(f.guests.status(f.token).balance, first.balance);
    assert.throws(() => f.ledger.issueKey(f.account), /one key/);
    assert.throws(() => f.ledger.approveDevice(f.account, 'whatever', () => ''), /prepaid key/);
    assert.equal(f.ledger.session(f.token), undefined);
    assert.throws(() => f.guests.account(first.key));
    assert.throws(() => f.guests.account('bad'));
  } finally { f.ledger.close(); }
});
test('recovery code restores the same key after browser expiry, without changing another guest', () => {
  const f = fixture();
  try {
    f.pay();
    const before = f.guests.status(f.token), other = f.guests.start();
    f.advance(181 * 86400000);
    assert.throws(() => f.guests.status(f.token));
    const restored = f.guests.recover(before.recoveryCode, false);
    assert.equal(f.guests.status(restored.token).key, before.key);
    assert.throws(() => f.guests.recover('0'.repeat(64), false));
    assert.throws(() => f.guests.status(other.token));
    assert.equal(f.ledger.summary(f.account).keys.length, 1);
  } finally { f.ledger.close(); }
});
test('email is optional, bound to paid checkout, encrypted, and recovered with an expiring one-use link', async () => {
  const f = fixture();
  try {
    await f.guests.requestEmail('buyer@example.com');
    assert.equal(f.emails.length, 0);
    f.ledger.guests.optIn(f.account, true);
    f.pay();
    assert.ok(f.ledger.guests.get(f.account).email_payload);
    assert.ok(!JSON.stringify(f.ledger.guests.get(f.account)).includes('buyer@example.com'));
    const answer = await f.guests.requestEmail('BUYER@example.com');
    assert.deepEqual(await f.guests.requestEmail('missing@example.com'), answer);
    assert.equal(f.emails.length, 1);
    const code = new URL(f.emails[0].links[0]).hash.split('=')[1];
    const restored = f.guests.recover(code, true);
    assert.equal(f.guests.status(restored.token).key, f.guests.status(f.token).key);
    assert.throws(() => f.guests.recover(code, true));
    await f.guests.requestEmail('buyer@example.com');
    const expired = new URL(f.emails[1].links[0]).hash.split('=')[1];
    f.advance(16 * 60000);
    assert.throws(() => f.guests.recover(expired, true));
  } finally { f.ledger.close(); }
});
test('no opt-in stores no email; revoked keys remain revoked after recovery', async () => {
  const f = fixture();
  try {
    f.pay();
    const before = f.guests.status(f.token);
    assert.equal(f.ledger.guests.get(f.account).email_payload, null);
    await f.guests.requestEmail('buyer@example.com');
    assert.equal(f.emails.length, 0);
    f.ledger.revoke(f.account, f.ledger.authenticate(before.key).id);
    const recovered = f.guests.recover(before.recoveryCode, false);
    assert.equal(f.guests.status(recovered.token).state, 'unavailable');
    assert.equal(f.guests.status(recovered.token).key, null);
  } finally { f.ledger.close(); }
});
test('guest checkout uses the existing verified webhook and a guest return URL', async () => {
  const f = fixture();
  try {
    let created, paid = false;
    const billing = createStripeBilling({ ledger: f.ledger, mode: 'test', origin: 'https://credits.example', secret: 'whsec_fixture', onFulfilled: value => f.guests.fulfilled(value), stripeClient: { checkout: { sessions: {
      create: async value => { created = value; return { id: 'cs_checkout', url: 'https://checkout.stripe.com/c/test' }; },
      retrieve: async () => ({ id: 'cs_checkout', livemode: false, mode: 'payment', currency: 'usd', payment_status: paid ? 'paid' : 'unpaid', amount_total: 500, client_reference_id: f.account, metadata: created.metadata, total_details: {}, payment_intent: { id: 'pi_checkout', status: 'succeeded', currency: 'usd', livemode: false, amount_received: 500 } }),
    } } } });
    await billing.checkout(f.account, 500, 'guest-purchase-fixture', { guest: true });
    assert.equal(created.success_url, 'https://credits.example/prepaid.html?checkout=returned');
    const raw = JSON.stringify({ type: 'checkout.session.completed', livemode: false, data: { object: { id: 'cs_checkout' } } });
    const signature = Stripe.webhooks.generateTestHeaderString({ payload: raw, secret: 'whsec_fixture' });
    await billing.webhook(raw, signature);
    assert.equal(f.guests.status(f.token).key, null);
    paid = true;
    await billing.webhook(raw, signature);
    await billing.webhook(raw, signature);
    assert.ok(f.guests.status(f.token).key);
    assert.equal(f.ledger.summary(f.account).keys.length, 1);
    assert.equal(f.guests.status(f.token).balance, 500);
  } finally { f.ledger.close(); }
});
test('browser cookie is HttpOnly and recovery mail contains no app key', async () => {
  const token = 'a'.repeat(64), cookie = guestCookie(token);
  assert.match(cookie, /HttpOnly; Secure; SameSite=Lax/);
  assert.equal(guestToken(new Request('https://example.com', { headers: { cookie } })), token);
  let sent;
  await recoveryMailer('fixture', 'S2T <keys@example.com>', async (url, options) => { sent = { url, options }; return { ok: true }; })({ to: 'buyer@example.com', links: ['https://credits.example/prepaid.html#recover=fixture'], id: 'fixture' });
  assert.equal(sent.url, 'https://api.resend.com/emails');
  assert.match(JSON.parse(sent.options.body).text, /15 minutes/);
  assert.equal(sent.options.redirect, 'manual');
});

test('a stale tab cannot pay against a different browser wallet and save the wrong recovery code', () => {
  const f = fixture();
  try {
    const code = f.guests.status(f.token).recoveryCode;
    assert.equal(f.guests.checkoutAccount(f.token, code).account, f.account);
    const other = f.guests.start();
    assert.throws(() => f.guests.checkoutAccount(other.token, code), /another tab/);
    assert.throws(() => f.guests.checkoutAccount(f.token, undefined), /another tab/);
  } finally { f.ledger.close(); }
});
