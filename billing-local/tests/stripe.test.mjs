import test from "node:test";
import assert from "node:assert/strict";
import Stripe from "stripe";
import { openLedger } from "../ledger.mjs";
import { createStripeBilling } from "../stripe-billing.mjs";
const secret = "whsec_fake_fixture";
function setup() {
  const ledger = openLedger(":memory:", { mode: "test" }),
    { account } = ledger.createSession();
  let session = {
    id: "cs_test_1",
    livemode: false,
    payment_link: "plink_test",
    mode: "payment",
    currency: "usd",
    payment_status: "paid",
    amount_total: 500,
    client_reference_id: account,
    total_details: {},
    payment_intent: {
      id: "pi_1",
      status: "succeeded",
      currency: "usd",
      livemode: false,
      amount_received: 500,
    },
  };
  const refunds = {};
  const stripeClient = {
    checkout: { sessions: { retrieve: async () => session } },
    refunds: { retrieve: async (id) => refunds[id] },
    disputes: { retrieve: async (id) => refunds[id] },
  };
  const handler = createStripeBilling({
    ledger,
    mode: "test",
    secret,
    paymentLinkId: "plink_test",
    stripeClient,
  }).webhook;
  const send = async (type = "checkout.session.completed", id = "cs_test_1", override = {}) => {
    const raw = JSON.stringify({
      id: "evt_1",
      livemode: false,
      type,
      data: { object: { id } },
      ...override,
    });
    const signature = Stripe.webhooks.generateTestHeaderString({ payload: raw, secret });
    return handler(Buffer.from(raw), signature);
  };
  return { ledger, account, session, refunds, handler, send };
}
test("signed webhook retrieves authoritative checkout; duplicate and async events grant once", async () => {
  const { ledger, account, send } = setup();
  await send();
  await send();
  await send("checkout.session.async_payment_succeeded");
  assert.equal(ledger.summary(account).balance, 500);
  ledger.close();
});
test("forged, stale, live, unpaid, wrong-link and inconsistent checkout events fail closed", async () => {
  const { ledger, account, session, handler, send } = setup();
  await assert.rejects(handler(Buffer.from("{}"), "t=1,v1=bad"));
  await assert.rejects(send(undefined, undefined, { livemode: true }));
  session.payment_status = "unpaid";
  await send();
  assert.equal(ledger.summary(account).balance, 0);
  session.payment_status = "paid";
  session.payment_link = "plink_other";
  await assert.rejects(send());
  session.payment_link = "plink_test";
  session.payment_intent.amount_received = 499;
  await assert.rejects(send());
  assert.equal(ledger.summary(account).balance, 0);
  ledger.close();
});
test("partial refunds deduplicate and out-of-order disputes freeze later purchases", async () => {
  const { ledger, account, session, refunds, send } = setup();
  await send();
  refunds.re_1 = {
    id: "re_1",
    currency: "usd",
    status: "succeeded",
    payment_intent: "pi_1",
    amount: 100,
  };
  await send("refund.created", "re_1");
  await send("refund.updated", "re_1");
  assert.equal(ledger.summary(account).balance, 400);
  refunds.dp_1 = { id: "dp_1", currency: "usd", payment_intent: "pi_late", amount: 500, status: "needs_response" };
  await send("charge.dispute.created", "dp_1");
  session.id = "cs_test_late";
  session.payment_intent.id = "pi_late";
  await send("checkout.session.completed", "cs_test_late");
  assert.equal(ledger.summary(account).balance, 400);
  assert.equal(ledger.summary(account).frozen, true);
  ledger.close();
});
test("discounts, taxes, unsupported currency and out-of-range purchases are not silently credited", async () => {
  for (const mutate of [
    (s) => (s.currency = "eur"),
    (s) => (s.total_details.amount_tax = 90),
    (s) => (s.total_details.amount_discount = 10),
    (s) => {
      s.amount_total = 10001;
      s.payment_intent.amount_received = 10001;
    },
  ]) {
    const { ledger, account, session, send } = setup();
    mutate(session);
    await assert.rejects(send());
    assert.equal(ledger.summary(account).balance, 0);
    ledger.close();
  }
});
test("checkout verifies the supplied link and allowed amount before sending a buyer to Stripe", async () => {
  const link = {
    active: true,
    livemode: true,
    url: "https://buy.stripe.com/fixture",
    automatic_tax: { enabled: false },
    allow_promotion_codes: false,
  };
  const price = {
    currency: "usd",
    type: "one_time",
    custom_unit_amount: { minimum: 500, maximum: 10000 },
  };
  const billing = createStripeBilling({
    mode: "live",
    paymentLinkId: "plink_live",
    paymentLinkURL: link.url,
    stripeClient: {
      paymentLinks: {
        retrieve: async () => link,
        listLineItems: async () => ({ data: [{ quantity: 1, price }], has_more: false }),
      },
    },
  });
  assert.equal(
    (await billing.checkout("account")).url,
    "https://buy.stripe.com/fixture?client_reference_id=account",
  );
  price.custom_unit_amount.maximum = 10001;
  await assert.rejects(billing.checkout("account"));
  price.custom_unit_amount.maximum = 10000;
  link.automatic_tax.enabled = true;
  await assert.rejects(billing.checkout("account"));
});
