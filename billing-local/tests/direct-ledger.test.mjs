import test from "node:test";
import assert from "node:assert/strict";
import { openLedger } from "../ledger.mjs";
function fixture(options = {}) {
  const l = openLedger(":memory:", options);
  const a = l.createSession().account;
  l.grant({ account: a, cents: 100, session: "s", intent: "p" });
  const k = l.issueKey(a).id;
  const p = {
    account: a,
    keyId: k,
    model: "fixture",
    host: "fixture",
    priceVersion: "v1",
    feeBps: 550,
    allowanceMicros: 100000,
    dedup: "one",
    expiresAt: Date.now() + 86400000,
  };
  return { l, a, k, p };
}
test("direct holds conserve available funds and cumulative charges are idempotent", () => {
  const { l, a, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  const available = l.summary(a).available;
  assert.equal(l.direct.prepare(p).created, false);
  l.direct.attach(r.id, { hash: "hash", secretCipher: "cipher" });
  l.direct.observe(r.id, { usageMicros: 1001 });
  l.direct.observe(r.id, { usageMicros: 1001 });
  assert.equal(l.summary(a).available, available);
  assert.equal(l.direct.get(r.id).charged, 1001);
  assert.equal(l.summary(a).requests.length, 1);
  l.direct.observe(r.id, { usageMicros: 2002 });
  assert.equal(l.summary(a).available, available);
  l.close();
});
test("normal requests and direct pools share key and account exposure", () => {
  const { l, a, k, p } = fixture();
  l.setKeyLimits(a, k, { limitCredits: 21 });
  l.direct.prepare(p);
  assert.throws(
    () =>
      l.reserve({
        account: a,
        keyId: k,
        dedup: "normal",
        fingerprint: "normal",
        provider: "openrouter",
        model: "f",
        priceVersion: "v1",
        maxCost: 9000,
      }),
    /limit/,
  );
  l.close();
});
test("revocation prevents pool reuse and retains held funds", () => {
  const { l, a, k, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.revoke(a, k);
  assert.equal(l.direct.eligible(r.id), false);
  assert.equal(l.direct.pending().length, 1);
  assert.throws(() =>
    l.direct.refill(r.id, { allowanceMicros: 1, dedup: "next" }),
  );
  l.close();
});
test("daily rollover retains outstanding pool exposure", () => {
  let t = Date.now();
  const { l, p } = fixture({ now: () => t, limits: { accountDaily: 110000 } });
  l.direct.prepare(p);
  t += 86400000;
  assert.throws(
    () =>
      l.direct.prepare({
        ...p,
        dedup: "two",
        model: "other",
        allowanceMicros: 10000,
        expiresAt: t + 86400000,
      }),
    /limit/,
  );
  l.close();
});
test("closing preserves authorization for late usage and requires independent finality", () => {
  const { l, a, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.direct.markClosing(r.id);
  const available = l.summary(a).available;
  assert.throws(() => l.direct.close(r.id, { usageMicros: 0 }), /Independent/);
  l.direct.observe(r.id, { usageMicros: 300 });
  assert.equal(l.summary(a).available, available);
  l.direct.close(r.id, { usageMicros: 300, finalUsageVerified: true });
  assert.equal(l.direct.pending().length, 0);
  assert.equal(l.summary(a).reserved, 0);
  l.close();
});
test("refill dedup and account isolation preserve absolute caps", () => {
  const { l, a, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.direct.refill(r.id, { allowanceMicros: 1000, dedup: "refill" });
  l.direct.refill(r.id, { allowanceMicros: 1000, dedup: "refill" });
  assert.equal(l.direct.get(r.id).authorized, 101000);
  const b = l.createSession().account;
  l.grant({ account: b, cents: 100, session: "s2", intent: "p2" });
  const k = l.issueKey(b).id;
  assert.throws(
    () => l.direct.prepare({ ...p, dedup: "wrong", keyId: k }),
    /Key not found/,
  );
  const other = l.direct.prepare({ ...p, account: b, keyId: k }).authorization;
  l.direct.attach(other.id, { hash: "h2", secretCipher: "c2" });
  l.direct.observe(other.id, { usageMicros: 200 });
  assert.equal(l.direct.get(r.id).observed, 0);
  assert.equal(l.summary(a).requests.length, 0);
  l.close();
});
test("overrun caps customer debit and pauses provider access", () => {
  const { l, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.direct.observe(r.id, { usageMicros: 100001 });
  assert.equal(l.direct.get(r.id).charged, 100000);
  assert.equal(l.direct.eligible(r.id), false);
  assert.equal(l.direct.get(r.id).status, "closing");
  l.close();
});
test("restart recovery retains creating and active pool holds", () => {
  const { l, a, p } = fixture();
  const creating = l.direct.prepare(p).authorization;
  const active = l.direct.prepare({
    ...p,
    dedup: "active",
    model: "other",
  }).authorization;
  l.direct.attach(active.id, { hash: "h", secretCipher: "c" });
  const before = l.summary(a);
  l.recover();
  assert.equal(l.summary(a).reserved, before.reserved);
  assert.equal(l.direct.get(creating.id).status, "creating");
  assert.equal(l.direct.get(active.id).secret_cipher, "c");
  l.close();
});
test("regression pauses access without altering already billed usage", () => {
  const { l, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.direct.observe(r.id, { usageMicros: 100 });
  l.direct.observe(r.id, { usageMicros: 99 });
  assert.equal(l.direct.get(r.id).observed, 100);
  assert.equal(l.direct.eligible(r.id), false);
  l.close();
});
test("idempotency binds initial allowance, fee, price and device but retains original expiry", () => {
  const { l, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  for (const changed of [
    { allowanceMicros: 1 },
    { feeBps: 0 },
    { priceVersion: "v2" },
    { device: { id: "00000000-0000-0000-0000-000000000001", name: "Mac" } },
  ])
    assert.throws(() => l.direct.prepare({ ...p, ...changed }), /already used/);
  assert.equal(
    l.direct.prepare({ ...p, expiresAt: p.expiresAt + 1 }).authorization
      .expires,
    r.expires,
  );
  l.close();
});
test("creation is bounded globally across accounts", () => {
  const { l, p } = fixture({ limits: { concurrency: 1 } });
  l.direct.prepare(p);
  const b = l.createSession().account;
  l.grant({ account: b, cents: 100, session: "s2", intent: "p2" });
  const keyId = l.issueKey(b).id;
  assert.throws(
    () => l.direct.prepare({ ...p, account: b, keyId }),
    /Too many/,
  );
  l.close();
});
test("freeze and lowered key limits make existing delegated credentials ineligible", () => {
  const { l, a, k, p } = fixture();
  const r = l.direct.prepare(p).authorization;
  l.direct.attach(r.id, { hash: "h", secretCipher: "c" });
  l.setKeyLimits(a, k, { limitCredits: 1 });
  assert.equal(l.direct.eligible(r.id), false);
  l.setKeyLimits(a, k, { limitCredits: null });
  assert.equal(l.direct.eligible(r.id), true);
  l.reverse({ id: "dispute", intent: "p", cents: 100, kind: "dispute" });
  assert.equal(l.direct.eligible(r.id), false);
  assert.throws(() => l.direct.prepare(p), /inactive/);
  l.close();
});

test("direct funding has no default monetary cap but retains balance and chosen key limits", () => {
  const { l, a, k, p } = fixture();
  try {
    l.grant({ account: a, cents: 10000, session: "large-funding", intent: "large-payment" });
    const r = l.direct.prepare({ ...p, allowanceMicros: 30000000 }).authorization;
    l.direct.attach(r.id, { hash: "large-hash", secretCipher: "fixture" });
    l.direct.markClosing(r.id);
    l.direct.close(r.id, { usageMicros: 30000000, finalUsageVerified: true });
    l.setKeyLimits(a, k, { limitCredits: 1 });
    assert.throws(() => l.direct.prepare({ ...p, dedup: "limited" }), error => error.code === "key_limit");
    l.setKeyLimits(a, k, { limitCredits: null });
    assert.equal(l.direct.prepare({ ...p, dedup: "available" }).created, true);
    assert.throws(() => l.direct.prepare({ ...p, dedup: "too-large", allowanceMicros: 90000000 }), error => error.code === "insufficient_credits");
  } finally { l.close(); }
});
