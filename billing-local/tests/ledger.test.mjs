import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { Worker } from "node:worker_threads";
import { openLedger } from "../ledger.mjs";
function setup(options = {}) {
  const ledger = openLedger(":memory:", options);
  const { account } = ledger.createSession();
  ledger.grant({ account, cents: 100, session: "cs_one", intent: "pi_one" });
  return { ledger, account };
}
const request = (account, id = "request0000000001", maxCost = 100000) => ({
  account,
  dedup: id,
  fingerprint: id,
  provider: "openrouter",
  model: "fixture",
  priceVersion: "v1",
  maxCost,
});
test("request activity retains the actual operation for dashboard labels", () => {
  const {ledger:l,account:a}=setup();
  try {
    const r=l.reserve({...request(a),operation:'transcription'}).request;
    assert.equal(l.summary(a).requests.find(row=>row.id===r.id).operation,'transcription');
  } finally {l.close();}
});
test("operator balance reset preserves purchases and usage and cannot replay free credits", () => {
  const { ledger: l, account: a } = setup();
  try {
    const r = l.reserve(request(a)).request;
    l.submit(r.id);
    l.settle(r.id, { cost: 1378, providerId: "receipt-reset" });
    const before = l.summary(a);
    const adjustment = { account: a, targetCredits: 200, id: "reset-fixture-0001", reason: "User requested their wallet balance be reset to 200 credits." };
    assert.equal(l.setBalance(adjustment).applied, true);
    assert.equal(l.summary(a).available, 200);
    assert.deepEqual(l.summary(a).purchases, before.purchases);
    assert.deepEqual(l.summary(a).requests, before.requests);
    const later = l.reserve(request(a, "later-usage-00001")).request;
    l.submit(later.id);
    l.settle(later.id, { cost: 5000, providerId: "later-receipt" });
    assert.equal(l.setBalance(adjustment).applied, false);
    assert.equal(l.summary(a).available, 199);
    assert.throws(() => l.setBalance({ ...adjustment, targetCredits: 300 }), /already used/);
    const other = l.createSession().account;
    assert.throws(() => l.setBalance({ ...adjustment, account: other }), /already used/);
    const held = l.reserve(request(a, "held-reset-00001")).request;
    assert.throws(() => l.setBalance({ ...adjustment, id: "reset-fixture-0002" }), /pending/);
    l.cancel(a, held.id);
    for (const value of [-1, 200.5, NaN, 10001]) assert.throws(() => l.setBalance({ ...adjustment, id: "reset-fixture-0002", targetCredits: value }));
    assert.equal(l.summary(a).available, 199);
  } finally { l.close(); }
});
test("payment identity, fractional usage, immutable refunds and before-payment disputes", () => {
  const { ledger: l, account: a } = setup();
  assert.equal(l.summary(a).available, 100);
  assert.equal(l.grant({ account: a, cents: 100, session: "cs_one", intent: "pi_one" }), false);
  assert.throws(() => l.grant({ account: a, cents: 100, session: "cs_other", intent: "pi_one" }));
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  assert.ok(l.settle(r.id, { cost: 50, providerId: "receipt" }));
  assert.equal(l.summary(a).available, 99.99);
  l.settle(r.id, { cost: 50, providerId: "receipt" });
  assert.equal(l.summary(a).available, 99.99);
  l.reverse({ id: "refund1", intent: "pi_one", cents: 50, kind: "refund" });
  l.reverse({ id: "refund1", intent: "pi_one", cents: 50, kind: "refund" });
  assert.equal(l.summary(a).balance, 49.99);
  l.reverse({ id: "dispute1", intent: "pi_late", cents: 100, kind: "dispute" });
  l.grant({ account: a, cents: 100, session: "cs_late", intent: "pi_late" });
  assert.equal(l.summary(a).balance, 49.99);
  assert.equal(l.summary(a).frozen, true);
  l.close();
});
test("parallel holds cannot reuse money, cancellation never releases submitted spending", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.reserve(request(a, "request0000000002"));
  assert.throws(() => l.reserve(request(a, "request0000000003")), /pending/);
  l.submit(r.id);
  l.cancel(a, r.id);
  assert.equal(l.request(a, r.id).state, "submitted");
  assert.equal(l.summary(a).reserved, 200000 / 5000);
  l.uncertain(r.id, "timeout");
  assert.equal(l.summary(a).reserved, 200000 / 5000);
  assert.throws(() => l.resume());
  assert.throws(() => l.reserve(request(a, "request0000000004")));
  l.close();
});
test("duplicate submissions, changed payload and cross-account job reads", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  assert.equal(l.reserve(request(a)).created, false);
  assert.throws(() => l.reserve({ ...request(a), fingerprint: "different" }));
  l.submit(r.id);
  assert.throws(() => l.submit(r.id));
  const b = l.createSession().account;
  assert.equal(l.request(b, r.id), undefined);
  assert.throws(() => l.cancel(b, r.id));
  l.close();
});
test("price overrun and receipt replay trip persistent stop without overcharging user", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  assert.equal(l.settle(r.id, { cost: 100001, providerId: "expensive" }), false);
  assert.equal(l.health().paused, true);
  assert.equal(l.summary(a).balance, 100);
  assert.equal(l.request(a, r.id).state, "uncertain");
  l.close();
  const { ledger: m, account: b } = setup();
  const first = m.reserve(request(b)).request;
  m.submit(first.id);
  m.settle(first.id, { cost: 10, providerId: "same" });
  const second = m.reserve(request(b, "request0000000002")).request;
  m.submit(second.id);
  assert.equal(m.settle(second.id, { cost: 10, providerId: "same" }), false);
  assert.equal(m.health().paused, true);
  m.close();
});
test("daily/global limits include funding fee and previous-day unresolved work", () => {
  let time = Date.UTC(2026, 8, 14, 23, 59);
  const { ledger: l, account: a } = setup({
    now: () => time,
    limits: { globalDaily: 110000, providerDaily: 110000 },
  });
  const r = l.reserve({ ...request(a), feeBps: 550 }).request;
  l.submit(r.id);
  time += 120000;
  assert.throws(() => l.reserve(request(a, "request0000000002", 10000)), /daily limit/);
  l.close();
});
test("restart releases only unsubmitted reservations and retains submitted funds without a global pause", () => {
  const dir = mkdtempSync(tmpdir() + "/s2t-ledger-"),
    path = dir + "/test.sqlite";
  let l = openLedger(path);
  const a = l.createSession().account;
  l.grant({ account: a, cents: 100, session: "cs1", intent: "pi1" });
  const r = l.reserve(request(a)).request;
  const second = l.reserve(request(a, "request0000000002")).request;
  l.submit(r.id);
  l.close();
  l = openLedger(path);
  assert.equal(l.recover(), 1);
  assert.equal(l.request(a, r.id).state, "uncertain");
  assert.equal(l.request(a, second.id).state, "released");
  assert.equal(l.health().paused, false);
  assert.equal(l.summary(a).reserved, 100000 / 5000);
  assert.throws(() => openLedger(path, { mode: "live" }));
  l.close();
});
test("independent evidence settles uncertain work; mismatched report stops service", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.uncertain(r.id, "network");
  assert.ok(l.reconcile(r.id, { cost: 100, providerId: "receipt", evidence: "a".repeat(64) }));
  l.resume();
  assert.equal(l.health().paused, false);
  assert.equal(l.summary(a).reserved, 0);
  assert.equal(
    l.reconcile(r.id, { cost: 200, providerId: "receipt", evidence: "b".repeat(64) }),
    false,
  );
  assert.equal(l.health().paused, true);
  l.close();
});
test("revoked keys cannot reserve or submit; expired sessions fail authentication", () => {
  let time = 1000;
  const { ledger: l, account: a } = setup({ now: () => time });
  const k = l.issueKey(a);
  assert.equal(l.authenticate(k.key).account, a);
  const r = l.reserve({ ...request(a), keyId: k.id }).request;
  l.revoke(a, k.id);
  assert.equal(l.authenticate(k.key), undefined);
  assert.throws(() => l.submit(r.id));
  assert.throws(() => l.reserve({ ...request(a, "request0000000002"), keyId: k.id }));
  const s = l.createSession();
  time += 8 * 86400000;
  assert.equal(l.session(s.token), undefined);
  l.close();
});
test("overdue independent receipt and account-total reconciliation blocks new spending but preserves retries", () => {
  let time = Date.now();
  const { ledger: l, account: a } = setup({ now: () => time, enforceReconciliation: true });
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.settle(r.id, { cost: 100, providerId: "report" });
  time += 86400001;
  assert.equal(l.reserve(request(a)).created, false);
  assert.throws(() => l.reserve(request(a, "request0000000002")), { code: "reconciliation_overdue" });
  l.reconcile(r.id, { cost: 100, providerId: "report", evidence: "a".repeat(64) });
  assert.throws(() => l.reserve(request(a, "request0000000002")), { code: "reconciliation_overdue" });
  l.reconcileReport({ provider: "openrouter", through: r.created, totalCostMicros: 100, evidence: "b".repeat(64) });
  assert.equal(l.reserve(request(a, "request0000000002")).created, true);
  l.close();
});
test("provider funding review expiry blocks new reservations while allowing exact idempotent retries", () => {
  let time = Date.now();
  const { ledger: l, account: a } = setup({now:()=>time, fundingReviewedAt:time});
  const first = l.reserve(request(a));
  time += 86400001;
  assert.equal(l.reserve(request(a)).request.id, first.request.id);
  assert.throws(() => l.reserve(request(a, "request0000000002")), {code:"funding_review_expired"});
  l.close();
});
test("an unsupported reconciliation can be reopened without changing settled money", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.settle(r.id, { cost: 100, providerId: "receipt" });
  l.reconcile(r.id, { cost: 100, providerId: "receipt", evidence: "a".repeat(64) });
  const before = l.summary(a);
  assert.throws(() => l.reopenReconciliation(r.id, "short"));
  assert.equal(l.reopenReconciliation(r.id, "The earlier evidence came from our ledger, not an independent provider report."), true);
  assert.equal(l.reopenReconciliation(r.id, "Repeated correction must not modify balances or receipt state."), false);
  assert.deepEqual(l.summary(a), before);
  assert.equal(l.health().unreconciled.length, 1);
  assert.equal(l.health().paused, false);
  l.close();
});
test("separate database connections race for the last credit without overspending", async () => {
  const dir = mkdtempSync(tmpdir() + "/s2t-race-"),
    path = dir + "/test.sqlite";
  const limits = { concurrency: 30, requestsPerMinute: 100 };
  const l = openLedger(path, { limits });
  const a = l.createSession().account;
  l.grant({ account: a, cents: 100, session: "cs", intent: "pi" });
  const tasks = Array.from(
    { length: 16 },
    (_, i) =>
      new Promise((resolve, reject) => {
        const worker = new Worker(new URL("./reserve-worker.mjs", import.meta.url), {
          workerData: { path, account: a, index: i, limits, maxCost: 125000 },
        });
        worker.on("message", resolve);
        worker.on("error", reject);
      }),
  );
  const results = await Promise.all(tasks);
  assert.equal(results.filter(Boolean).length, 4);
  assert.equal(l.summary(a).reserved, 500000 / 5000);
  assert.ok(l.summary(a).available >= 0);
  l.close();
});
test("independent provider account totals detect spending outside recorded requests", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.settle(r.id, { cost: 100, providerId: "receipt" });
  const report = {
    provider: "openrouter",
    through: Date.now(),
    totalCostMicros: 150,
    evidence: "c".repeat(64),
  };
  assert.equal(l.reconcileReport(report), false);
  assert.equal(l.health().paused, true);
  assert.throws(() => l.resume());
  assert.ok(l.reconcileReport({ ...report, totalCostMicros: 100 }));
  l.resume();
  assert.equal(l.health().paused, false);
  l.close();
});
test("database failures prevent a request from being reserved", () => {
  const { ledger: l, account: a } = setup();
  l.close();
  assert.throws(() => l.reserve(request(a)));
});
test("confirmed provider overrun is absorbed without charging beyond the user reservation", () => {
  const { ledger: l, account: a } = setup();
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.settle(r.id, { cost: 120000, providerId: "overrun" });
  assert.ok(l.reconcile(r.id, { cost: 120000, providerId: "overrun", evidence: "f".repeat(64) }));
  assert.equal(l.summary(a).balance, 100 - 100000 / 5000);
  assert.equal(l.health().expense, 120000);
  assert.equal(l.request(a, r.id).charged, 100000);
  assert.throws(() => l.resume());
  assert.throws(() => l.reviewPricing("v1"));
  l.reviewPricing("v2");
  l.resume();
  assert.equal(l.health().paused, false);
  l.close();
});

test('operator writeoff releases the customer hold but retains maximum service expense', () => {
  const {ledger:l,account:a}=setup();
  const before=l.summary(a).available;
  const r=l.reserve(request(a)).request;
  l.submit(r.id);l.uncertain(r.id,'receipt_missing');
  assert.equal(l.writeOff(r.id,'S2T absorbs an unknown outcome without charging the customer.'),true);
  l.resume();
  assert.equal(l.summary(a).available,before);
  assert.equal(l.summary(a).reserved,0);
  assert.equal(l.health().expense,r.expense_reserved);
  assert.equal(l.health().unreconciled.length,0);
  assert.equal(l.request(a,r.id).cost,null);
  assert.equal(l.request(a,r.id).charged,0);
  assert.equal(l.writeOff(r.id,'A repeated operator writeoff must not change balances.'),false);
  l.close();
});

test("funded accounts can spend beyond all former default caps until their own key limit or balance", () => {
  const { ledger: l, account: a } = setup();
  try {
    l.grant({ account: a, cents: 10000, session: "large-funding", intent: "large-payment" });
    const keyId = l.issueKey(a).id;
    for (let i = 0; i < 3; i++) {
      const r = l.reserve({ ...request(a, `large-request-${i}`, 10000000), keyId }).request;
      l.submit(r.id);
      l.settle(r.id, { cost: 10000000, providerId: `large-receipt-${i}` });
    }
    assert.equal(l.health().expense, 30000000);
    l.setKeyLimits(a, keyId, { limitCredits: 1 });
    assert.throws(() => l.reserve({ ...request(a, "user-limit-request", 10000), keyId }), error => error.code === "key_limit");
    l.setKeyLimits(a, keyId, { limitCredits: null });
    const available = Math.round(l.summary(a).available * 5000);
    const final = l.reserve({ ...request(a, "remaining-balance", available), keyId }).request;
    l.submit(final.id);
    l.settle(final.id, { cost: available, providerId: "remaining-receipt" });
    assert.equal(l.summary(a).available, 0);
    assert.throws(() => l.reserve({ ...request(a, "empty-wallet", 1), keyId }), error => error.code === "insufficient_credits");
  } finally { l.close(); }
});

test("explicit monetary caps remain supported while null technical limits are invalid", () => {
  for (const [name, code] of [["perRequest", "request_limit"], ["accountDaily", "account_limit"], ["globalDaily", "daily_limit"], ["globalLifetime", "global_limit"], ["providerDaily", "provider_limit"]]) {
    const { ledger: l, account: a } = setup({ limits: { [name]: 100000 } });
    try {
      assert.throws(() => l.reserve({ ...request(a), feeBps: 550 }), error => error.code === code);
    } finally { l.close(); }
  }
  for (const name of ["concurrency", "requestsPerMinute"]) {
    assert.throws(() => openLedger(":memory:", { limits: { [name]: null } }));
  }
});

test('finished provider calls with unknown receipts keep holds but do not occupy execution slots',()=>{
 const {ledger:l,account:a}=setup();
 for(let n=0;n<2;n++) {
   const r=l.reserve(request(a,'unknown-complete-'+n,1000)).request;
   l.submit(r.id);
   l.uncertain(r.id,'Provider response lost',null,{pauseSpending:false});
 }
 const held=l.summary(a).reserved;
 assert.ok(held>0);
 const next=l.reserve(request(a,'after-unknown-calls',1000)).request;
 l.submit(next.id);
 assert.equal(l.health().paused,false);
 assert.ok(l.summary(a).reserved>held);
 l.close();
});
