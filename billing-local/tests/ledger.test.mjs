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
test("payment identity, fractional usage, immutable refunds and before-payment disputes", () => {
  const { ledger: l, account: a } = setup();
  assert.equal(l.summary(a).available, 100);
  assert.equal(l.grant({ account: a, cents: 100, session: "cs_one", intent: "pi_one" }), false);
  assert.throws(() => l.grant({ account: a, cents: 100, session: "cs_other", intent: "pi_one" }));
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  assert.ok(l.settle(r.id, { cost: 90, providerId: "receipt" }));
  assert.equal(l.summary(a).available, 99.99);
  l.settle(r.id, { cost: 90, providerId: "receipt" });
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
  assert.equal(l.summary(a).reserved, 200000 / 9000);
  l.uncertain(r.id, "timeout");
  assert.equal(l.summary(a).reserved, 200000 / 9000);
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
test("restart releases only unsubmitted reservations, keeps submitted funds and stops spending", () => {
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
  assert.equal(l.health().paused, true);
  assert.equal(l.summary(a).reserved, 100000 / 9000);
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
test("unreconciled charges block further spending after 24 hours", () => {
  let time = Date.now();
  const { ledger: l, account: a } = setup({ now: () => time });
  const r = l.reserve(request(a)).request;
  l.submit(r.id);
  l.settle(r.id, { cost: 100, providerId: "report" });
  time += 86400001;
  assert.throws(() => l.reserve(request(a, "request0000000002")), /reconciliation is overdue/);
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
          workerData: { path, account: a, index: i, limits },
        });
        worker.on("message", resolve);
        worker.on("error", reject);
      }),
  );
  const results = await Promise.all(tasks);
  assert.equal(results.filter(Boolean).length, 4);
  assert.equal(l.summary(a).reserved, 800000 / 9000);
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
  assert.equal(l.summary(a).balance, 100 - 100000 / 9000);
  assert.equal(l.health().expense, 120000);
  assert.equal(l.request(a, r.id).charged, 100000);
  assert.throws(() => l.resume());
  assert.throws(() => l.reviewPricing("v1"));
  l.reviewPricing("v2");
  l.resume();
  assert.equal(l.health().paused, false);
  l.close();
});
