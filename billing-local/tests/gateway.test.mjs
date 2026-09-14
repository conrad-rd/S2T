import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { openLedger } from "../ledger.mjs";
import { createGateway } from "../gateway.mjs";
import { fixturePolicy, prepareRequest, parseWave, validatePolicy } from "../policy.mjs";
import { providerClient } from "../providers.mjs";
function setup(execute) {
  const ledger = openLedger(":memory:");
  const { account } = ledger.createSession();
  ledger.grant({ account, cents: 100, session: "cs", intent: "pi" });
  const gateway = createGateway({
    ledger,
    policy: fixturePolicy,
    encryptionKey: randomBytes(32),
    execute,
  });
  return { ledger, account, gateway };
}
const body = { provider: "openrouter", operation: "cleanup", text: "Example sentence." };
const args = (account) => ({ account, idempotencyKey: "unique-request-00001", body });
function wave(seconds = 1) {
  const data = Buffer.alloc(44 + 32000 * seconds);
  data.write("RIFF");
  data.writeUInt32LE(data.length - 8, 4);
  data.write("WAVEfmt ", 8);
  data.writeUInt32LE(16, 16);
  data.writeUInt16LE(1, 20);
  data.writeUInt16LE(1, 22);
  data.writeUInt32LE(16000, 24);
  data.writeUInt32LE(32000, 28);
  data.writeUInt16LE(2, 32);
  data.writeUInt16LE(16, 34);
  data.write("data", 36);
  data.writeUInt32LE(data.length - 44, 40);
  return data;
}
test("one upstream call for 20 identical concurrent requests and encrypted result replay", async () => {
  let calls = 0,
    complete;
  const { ledger, account, gateway } = setup(async () => {
    calls++;
    await new Promise((r) => (complete = r));
    return { text: "Edited.", cost: 90, providerId: "receipt", model: body.model };
  });
  const pending = gateway.run(args(account));
  const rest = await Promise.all(Array.from({ length: 19 }, () => gateway.run(args(account))));
  assert.equal(calls, 1);
  assert.ok(rest.every((x) => x.state === "submitted"));
  complete();
  const first = await pending;
  assert.equal(first.chargedCredits, 0.01);
  assert.equal(first.result.text, "Edited.");
  assert.equal((await gateway.run(args(account))).result.text, "Edited.");
  assert.equal(calls, 1);
  const stored = ledger.request(account, first.id);
  assert.ok(!stored.result.includes("Edited."));
  ledger.close();
});
test("timeout retains funds, opens circuit, and replay never resubmits", async () => {
  let calls = 0;
  const { ledger, account, gateway } = setup(async () => {
    calls++;
    throw Error("socket died");
  });
  const r = await gateway.run(args(account));
  assert.equal(r.state, "uncertain");
  assert.ok(ledger.summary(account).reserved > 0);
  assert.equal(ledger.summary(account).balance, 100);
  assert.equal((await gateway.run(args(account))).id, r.id);
  assert.equal(calls, 1);
  await assert.rejects(
    gateway.run({ ...args(account), idempotencyKey: "new-request-000002" }),
    /paused/,
  );
  ledger.close();
});
test("unapproved input, model, fields and expired prices cannot reach provider", async () => {
  let calls = 0;
  const { ledger, account, gateway } = setup(async () => {
    calls++;
  });
  for (const invalid of [
    { ...body, provider: "unknown" },
    { ...body, model: "expensive/model" },
    { ...body, max_tokens: 999999 },
    { ...body, text: "x".repeat(16001) },
    { ...body, url: "http://localhost/admin" },
  ])
    await assert.rejects(gateway.run({ ...args(account), body: invalid }));
  assert.equal(calls, 0);
  assert.throws(() => prepareRequest(body, { ...fixturePolicy, expires: "2000-01-01" }));
  assert.throws(() => validatePolicy(fixturePolicy, { live: true }));
  ledger.close();
});
test("WAV parsing validates real duration, channels, and container lengths", () => {
  assert.equal(parseWave(wave().toString("base64"), 120).seconds, 1);
  assert.throws(() => parseWave(wave(121).toString("base64"), 120));
  const stereo = wave();
  stereo.writeUInt16LE(2, 22);
  assert.throws(() => parseWave(stereo.toString("base64"), 120));
  const truncated = wave().subarray(0, 100);
  assert.throws(() => parseWave(truncated.toString("base64"), 120));
  assert.throws(() => parseWave("eA==", 120));
});
test("all provider adapters use fixed destinations, separate credentials, bounded options and no retries", async () => {
  const seen = [];
  const client = providerClient({
    keys: { openrouter: "fake-or", assemblyai: "fake-aa", elevenlabs: "fake-el" },
    fetchImpl: async (url, options) => {
      seen.push([url, options]);
      const isOR = url.includes("openrouter");
      return new Response(
        JSON.stringify(
          isOR
            ? {
                id: "or",
                model: "openai/gpt-oss-120b",
                choices: [{ finish_reason: "stop", message: { content: "Edited" } }],
                usage: { cost: 0.00009 },
              }
            : { text: "Transcribed" },
        ),
        { headers: { "request-id": "stt-receipt" } },
      );
    },
  });
  assert.equal((await client(prepareRequest(body, fixturePolicy))).cost, 90);
  for (const provider of ["assemblyai", "elevenlabs"])
    await client(
      prepareRequest(
        { provider, operation: "transcription", audio: wave().toString("base64") },
        fixturePolicy,
      ),
    );
  assert.equal(seen.length, 3);
  assert.equal(seen[0][1].headers.Authorization, "Bearer fake-or");
  assert.equal(seen[1][1].headers.Authorization, "fake-aa");
  assert.equal(seen[2][1].headers["xi-api-key"], "fake-el");
  assert.ok(seen.every((x) => x[1].redirect === "error" && x[1].signal instanceof AbortSignal));
  const posted = JSON.parse(seen[0][1].body);
  assert.equal(posted.max_tokens, 512);
  assert.equal(posted.provider.allow_fallbacks, false);
  assert.deepEqual(posted.provider.only, ["cerebras/fp16"]);
  assert.equal(posted.provider.max_price.request, 0);
  let attempts = 0;
  const failed = providerClient({
    keys: { openrouter: "fake" },
    fetchImpl: async () => {
      attempts++;
      return new Response("{}", { status: 500 });
    },
  });
  await assert.rejects(failed(prepareRequest(body, fixturePolicy)));
  assert.equal(attempts, 1);
});
test("malformed receipts and inflated costs pause the gateway", async () => {
  for (const cost of [NaN, 500000]) {
    const { ledger, account, gateway } = setup(async () => ({ text: "x", providerId: "r", cost }));
    const r = await gateway.run(args(account));
    assert.equal(r.state, "uncertain");
    assert.equal(ledger.health().paused, true);
    assert.equal(ledger.summary(account).balance, 100);
    ledger.close();
  }
});
