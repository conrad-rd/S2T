import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { DatabaseSync } from 'node:sqlite';
import { openLedger } from "../ledger.mjs";
import { createLedger } from '../ledger-core.mjs';
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
  assert.equal(first.chargedCredits, 0.018);
  assert.equal(first.result.text, "Edited.");
  assert.equal((await gateway.run(args(account))).result.text, "Edited.");
  assert.equal(calls, 1);
  const stored = ledger.request(account, first.id);
  assert.ok(!stored.result.includes("Edited."));
  ledger.close();
});
test('retired paid speech model replays a legacy settled request without resolving current policy or redispatching', async()=>{
  const db=new DatabaseSync(':memory:');
  let now=Date.now();
  const ledger=createLedger(db,{mode:'test',now:()=>now,fundingReviewedAt:now});
  const account=ledger.createSession().account;
  ledger.grant({account,cents:100,session:'cs_retired_speech',intent:'pi_retired_speech'});
  const key=ledger.issueKey(account);
  const other=ledger.createSession().account,otherKey=ledger.issueKey(other);
  const encryptionKey=randomBytes(32);
  const speechModel='meta/muse-voice-transcribe-1.0';
  const oldPolicy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:transcription':{
    model:speechModel,reserveRequestCeiling:true,maxSeconds:120,maxRequestMicros:20000,feeBps:0}}};
  let providerCalls=0,policyCalls=0;
  const old=createGateway({ledger,policy:oldPolicy,encryptionKey,execute:async()=>{
    providerCalls++;return {text:'Preserved paid transcript.',cost:125,providerId:'legacy-speech-receipt',model:speechModel};
  }});
  const input={account,keyId:key.id,idempotencyKey:'retired-speech-request-0001',
    body:{provider:'openrouter',operation:'transcription',model:speechModel,audio:wave().toString('base64')}};
  try {
    const original=await old.run(input);
    assert.equal(original.state,'settled');
    assert.equal(original.result.text,'Preserved paid transcript.');
    // This row represents the deployed schema before body_hash and operation existed.
    db.prepare('UPDATE requests SET body_hash=NULL,operation=NULL WHERE id=?').run(original.id);
    const pendingBody={...input.body,audio:wave(2).toString('base64')};
    const pendingPrepared=prepareRequest(pendingBody,oldPolicy);
    const pending=ledger.reserve({account,keyId:key.id,dedup:'retired-speech-pending-001',
      ...pendingPrepared,feeBps:pendingPrepared.price.feeBps}).request;
    ledger.submit(pending.id);
    ledger.uncertain(pending.id,'synthetic legacy unknown outcome',null,{pauseSpending:false});
    db.prepare('UPDATE requests SET operation=NULL WHERE id=?').run(pending.id);
    const retired=createGateway({ledger,policy:fixturePolicy,encryptionKey,
      resolvePolicy:async()=>{policyCalls++;return fixturePolicy;},
      execute:async()=>{providerCalls++;assert.fail('Retired speech was redispatched');}});
    now+=86400001; // A stale funding review must not hide a prior paid result.
    const replay=await retired.run(input);
    assert.equal(replay.state,'settled');
    assert.equal(replay.result.text,'Preserved paid transcript.');
    assert.equal(replay.id,original.id);
    const pendingReplay=await retired.run({...input,idempotencyKey:'retired-speech-pending-001',body:pendingBody});
    assert.equal(pendingReplay.id,pending.id);
    assert.equal(pendingReplay.state,'uncertain');
    assert.ok(pendingReplay.reservedCredits>0);
    assert.equal(providerCalls,1);
    assert.equal(policyCalls,0);
    await assert.rejects(retired.run({...input,body:{...input.body,audio:wave(2).toString('base64')}}),{code:'idempotency_conflict'});
    await assert.rejects(retired.run({...input,body:{...input.body,model:'other/model'}}),{code:'idempotency_conflict'});
    await assert.rejects(retired.run({...input,body:{...input.body,text:'injected'}}),{code:'idempotency_conflict'});
    await assert.rejects(retired.run({...input,idempotencyKey:'retired-speech-request-0002'}),{code:'route'});
    await assert.rejects(retired.run({...input,keyId:otherKey.id}),{code:'key'});
    await assert.rejects(retired.run({...input,account:other,keyId:otherKey.id}),{code:'route'});
    ledger.revoke(account,key.id);
    await assert.rejects(retired.run(input),{code:'key'});
    assert.equal(providerCalls,1);
  } finally {ledger.close();}
});

test('new request body hashes are key-order independent but reject changed fields before policy resolution', async()=>{
  let calls=0;
  const {ledger,account,gateway}=setup(async()=>{calls++;return {text:'Edited.',cost:10,providerId:'canonical-body'};});
  try {
    const first=await gateway.run({account,idempotencyKey:'canonical-body-request-001',body:{provider:'openrouter',operation:'cleanup',text:'Same words.'}});
    const reordered={text:'Same words.',operation:'cleanup',provider:'openrouter'};
    const replay=await gateway.run({account,idempotencyKey:'canonical-body-request-001',body:reordered});
    assert.equal(replay.id,first.id);
    assert.equal(calls,1);
    await assert.rejects(gateway.run({account,idempotencyKey:'canonical-body-request-001',body:{...reordered,instructions:'different'}}),{code:'idempotency_conflict'});
  } finally {ledger.close();}
});
test("timeout retains funds without pausing other requests and replay never resubmits", async () => {
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
  assert.equal(ledger.health().paused, false);
  const next = await gateway.run({ ...args(account), idempotencyKey: "new-request-000002" });
  assert.equal(next.state, "uncertain");
  assert.equal(calls, 2);
  const other = ledger.createSession().account;
  ledger.grant({ account: other, cents: 100, session: "cs-other", intent: "pi-other" });
  const unaffected = await gateway.run(args(other));
  assert.equal(unaffected.state, "uncertain");
  assert.equal(calls, 3);
  assert.equal(ledger.summary(other).balance, 100);
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
    keys: { openrouter: "fake-or", assemblyai: "fake-aa" },
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
  for (const provider of ["assemblyai"])
    await client(
      prepareRequest(
        { provider, operation: "transcription", audio: wave().toString("base64") },
        fixturePolicy,
      ),
    );
  assert.equal(seen.length, 2);
  assert.equal(seen[0][1].headers.Authorization, "Bearer fake-or");
  assert.equal(seen[1][1].headers.Authorization, "fake-aa");
  assert.throws(() => prepareRequest({ provider: "elevenlabs", operation: "transcription", audio: wave().toString("base64") }, fixturePolicy), /not enabled/);
  assert.ok(seen.every((x) => x[1].redirect === "manual" && x[1].signal instanceof AbortSignal));
  const posted = JSON.parse(seen[0][1].body);
  assert.equal(posted.max_tokens, 512);
  assert.equal(posted.provider.allow_fallbacks, false);
  assert.equal(posted.provider.data_collection, 'deny');
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
test("malformed costs are isolated while confirmed overruns pause spending", async () => {
  for (const cost of [NaN, 500000]) {
    const { ledger, account, gateway } = setup(async () => ({ text: "x", providerId: "r", cost }));
    const r = await gateway.run(args(account));
    assert.equal(r.state, "uncertain");
    assert.equal(ledger.health().paused, Number.isFinite(cost));
    assert.equal(ledger.summary(account).balance, 100);
    ledger.close();
  }
});

test('AssemblyAI Sync receipts use session_id rather than a batch transcript id', async () => {
  const client = providerClient({ keys: {assemblyai:'fixture'}, fetchImpl: async () => Response.json({text:'A short test.',session_id:'sync-session-fixture',audio_duration_ms:1000,words:[],confidence:0.99}) });
  const receipt = await client(prepareRequest({provider:'assemblyai',operation:'transcription',audio:wave().toString('base64')},fixturePolicy));
  assert.equal(receipt.providerId,'sync-session-fixture');
  assert.equal(receipt.text,'A short test.');
});

test('completed silence settles its receipt once without pausing other requests', async () => {
  let calls = 0;
  const client = providerClient({ keys: { assemblyai: 'fixture' }, fetchImpl: async () => {
    calls++;
    return Response.json({ text: '', session_id: 'silence-receipt', words: [], audio_duration_ms: 1000 });
  } });
  const { ledger, account, gateway } = setup(client);
  try {
    const input = { account, idempotencyKey: 'silent-recording-0001', body: { provider: 'assemblyai', operation: 'transcription', audio: wave().toString('base64') } };
    const result = await gateway.run(input);
    assert.equal(result.state, 'settled');
    assert.equal(result.result.text, '');
    assert.equal(ledger.request(account, result.id).provider_id, 'silence-receipt');
    assert.equal(ledger.summary(account).reserved, 0);
    assert.equal(ledger.health().paused, false);
    assert.deepEqual(await gateway.run(input), result);
    assert.equal(calls, 1);
  } finally { ledger.close(); }
});

test('missing transcript or receipt remains uncertain even for silent audio', async () => {
  for (const response of [{ session_id: 'missing-text' }, { text: '' }, { text: null, session_id: 'null-text' }]) {
    const client = providerClient({ keys: { assemblyai: 'fixture' }, fetchImpl: async () => Response.json(response) });
    const { ledger, account, gateway } = setup(client);
    try {
      const result = await gateway.run({ account, idempotencyKey: 'malformed-silence-01', body: { provider: 'assemblyai', operation: 'transcription', audio: wave().toString('base64') } });
      assert.equal(result.state, 'uncertain');
      assert.equal(ledger.health().paused, false);
    } finally { ledger.close(); }
  }
});

test('invalid cleanup text settles valid receipts once and preserves an explicit delivery error', async () => {
  for (const content of ['', '   ', null, {}, 'x'.repeat(100001)]) {
    let calls = 0;
    const client = providerClient({keys: {openrouter: 'fixture'}, fetchImpl: async () => {
      calls++;
      return Response.json({id:'invalid-output',model:'openai/gpt-oss-120b',choices:[{finish_reason:'stop',message:{content}}],usage:{cost:0.00009}});
    }});
    const {ledger,account,gateway} = setup(client);
    try {
      const result = await gateway.run(args(account));
      assert.equal(result.state, 'settled');
      assert.match(result.error, /original transcription is preserved/);
      assert.equal(result.result, undefined);
      assert.equal(result.chargedCredits, 0.018);
      assert.equal(ledger.summary(account).reserved, 0);
      assert.equal(ledger.health().paused, false);
      assert.deepEqual(await gateway.run(args(account)), result);
      assert.equal(calls, 1);
    } finally {ledger.close();}
  }
});

test('unusable speech output settles valid OpenRouter receipts once without retaining a hold', async () => {
  const {readFileSync} = await import('node:fs');
  const policy = JSON.parse(JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8')).vars.S2T_PRICING_JSON);
  for (const text of ['', '   ', null, {}, 'x'.repeat(100001)]) {
    let calls = 0;
    const client = providerClient({keys: {openrouter: 'fixture'}, fetchImpl: async () => {
      calls++;
      return Response.json({id:'unusable-speech',text,usage:{cost:0.0001}});
    }});
    const {ledger,account} = setup(client);
    const gateway = createGateway({ledger,policy,execute:client,encryptionKey:randomBytes(32)});
    const input = {account,idempotencyKey:'unusable-speech-0001',body:{provider:'openrouter',operation:'transcription',model:'openai/whisper-large-v3',audio:wave().toString('base64')}};
    try {
      const result = await gateway.run(input);
      assert.equal(result.state, 'settled');
      assert.match(result.error, /recording is preserved for retry/);
      assert.equal(result.result, undefined);
      assert.equal(ledger.request(account,result.id).cost, 100);
      assert.equal(ledger.summary(account).reserved, 0);
      assert.equal(ledger.health().paused, false);
      assert.deepEqual(await gateway.run(input), result);
      assert.equal(calls, 1);
    } finally {ledger.close();}
  }
});
