import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { once } from "node:events";
import { createApplication } from "./server.mjs";
import { configuration } from "./config.mjs";
let nextPort = 14317;
async function app(mode = "demo") {
  const port = nextPort++;
  const config = configuration({
    PORT: String(port),
    S2T_BILLING_MODE: mode,
    S2T_BILLING_DATA_DIR: mkdtempSync(tmpdir() + "/s2t-http-"),
  });
  const instance = createApplication(config);
  instance.server.listen(port, "127.0.0.1");
  await once(instance.server, "listening");
  return instance;
}
test("HTTP purchase, key, metering, replay, ownership, CSRF and revocation", async () => {
  const instance = await app();
  const base = "http://localhost:14317";
  try {
    const first = await fetch(base + "/api/account"),
      cookie = first.headers.get("set-cookie").split(";")[0];
    const post = (path, body, headers = {}) =>
      fetch(base + path, {
        method: "POST",
        headers: { cookie, "content-type": "application/json", ...headers },
        body: JSON.stringify(body),
      });
    assert.equal((await post("/api/demo/purchase", { cents: 500 })).status, 403);
    assert.equal((await post("/api/demo/purchase", { cents: 500 }, { origin: base })).status, 200);
    const issued = await (await post("/api/keys", {}, { origin: base })).json();
    assert.match(issued.key, /^s2t_demo_/);
    const headers = {
      Authorization: `Bearer ${issued.key}`,
      "Idempotency-Key": "http-request-000001",
    };
    const request = { provider: "openrouter", operation: "cleanup", text: "Synthetic text." };
    const result = await (await post("/api/v1/requests", request, headers)).json();
    assert.equal(result.state, "settled");
    assert.equal(result.chargedCredits, 0.018);
    const replay = await (await post("/api/v1/requests", request, headers)).json();
    assert.equal(replay.id, result.id);
    assert.equal(replay.result.text, "Synthetic text.");
    assert.equal(
      (await post("/api/v1/requests", { ...request, text: "different" }, headers)).status,
      400,
    );
    const after = await (await fetch(base + "/api/account", { headers: { cookie } })).json();
    assert.equal(after.available, 499.982);
    assert.equal(after.reserved, 0);
    assert.equal((await post("/api/v1/requests", request)).status, 401);
    const other = instance.ledger.createSession().account;
    instance.ledger.grant({ account: other, cents: 100, session: "other", intent: "other" });
    const otherKey = instance.ledger.issueKey(other).key;
    assert.equal(
      (
        await fetch(base + `/api/v1/requests/${result.id}`, {
          headers: { Authorization: `Bearer ${otherKey}` },
        })
      ).status,
      404,
    );
    assert.equal((await post("/api/keys/revoke", { id: issued.id }, { origin: base })).status, 200);
    assert.equal((await post("/api/v1/requests", request, headers)).status, 401);
    assert.equal((await post("/api/checkout", {}, { origin: base })).status, 503);
  } finally {
    await instance.close();
  }
});
test("test deployment cannot mint demo credits or accept unconfigured Stripe events", async () => {
  const instance = await app("test");
  const base = "http://localhost:14318";
  try {
    const res = await fetch(base + "/api/account"),
      cookie = res.headers.get("set-cookie").split(";")[0];
    const opts = {
      method: "POST",
      headers: { cookie, origin: base, "content-type": "application/json" },
      body: '{"cents":500}',
    };
    assert.equal((await fetch(base + "/api/demo/purchase", opts)).status, 404);
    assert.equal((await fetch(base + "/api/stripe/webhook", opts)).status, 503);
    assert.equal((await fetch(base + "/api/checkout", opts)).status, 503);
  } finally {
    await instance.close();
  }
});
test("production startup refuses demo credentials and incomplete safeguards", () => {
  assert.throws(() => configuration({ S2T_BILLING_MODE: "live" }), /required/);
  assert.throws(() => configuration({ S2T_BILLING_MODE: "live", VERCEL: "1" }), /persistent host/);
  assert.throws(
    () => configuration({ S2T_BILLING_MODE: "demo", STRIPE_SECRET_KEY: "sk_live_fake" }),
    /never use a live/,
  );
});
