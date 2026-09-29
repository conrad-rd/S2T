import test from 'node:test';
import assert from 'node:assert/strict';
import { providerClient, ProviderRejected } from '../providers.mjs';
import { validatePolicy, prepareRequest, modelCatalog } from '../policy.mjs';
import { checkProviderAccess } from '../provider-access.mjs';

const cleanup = { model: 'grok-4.6', inputMicrosPerToken: 1, outputMicrosPerToken: 1,
  maxOutputTokens: 512, maxInputBytes: 16000, maxRequestMicros: 50000, feeBps: 0 };
const policy = { version: 'xai-test', expires: null, routes: { 'xai:cleanup': cleanup } };

test('xAI catalog and cleanup reservation use a separate priced provider', () => {
  validatePolicy(policy);
  assert.equal(modelCatalog(policy).length, 1);
  const request = prepareRequest({ provider: 'xai', operation: 'cleanup', text: 'hello' }, policy);
  assert.equal(request.provider, 'xai');
  assert.ok(request.maxCost >= 512);
  assert.throws(() => validatePolicy({ ...policy, routes: { 'xai:cleanup': { ...cleanup, host: 'cerebras/fp16' } } }));
});

test('xAI cleanup sends only its key and settles exact token cost', async () => {
  const execute = providerClient({ keys: { xai: 'xai-fixture', openrouter: 'router-fixture' }, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.x.ai/v1/chat/completions');
    assert.equal(options.headers.Authorization, 'Bearer xai-fixture');
    assert.equal(options.redirect, 'manual');
    const body = JSON.parse(options.body);
    assert.equal(body.provider, undefined);
    assert.equal(body.max_tokens, 512);
    return Response.json({ id: 'xai-1', model: cleanup.model, usage: { cost_in_usd_ticks: 270000 }, choices: [{ finish_reason: 'stop', message: { content: 'Hello.' } }] });
  } });
  const result = await execute(prepareRequest({ provider: 'xai', operation: 'cleanup', text: 'hello' }, policy));
  assert.equal(result.cost, 27);
  assert.equal(result.host, 'xai');
});

test('xAI failures never become successful unpriced results', async () => {
  const request = prepareRequest({ provider: 'xai', operation: 'cleanup', text: 'hello' }, policy);
  const rejected = providerClient({ keys: { xai: 'fixture' }, fetchImpl: async () => new Response('{}', { status: 401 }) });
  await assert.rejects(rejected(request), ProviderRejected);
  const noUsage = providerClient({ keys: { xai: 'fixture' }, fetchImpl: async () => Response.json({ id: 'receipt', model: cleanup.model, choices: [{ finish_reason: 'stop', message: { content: 'Hello.' } }] }) });
  await assert.rejects(noUsage(request), { code: 'provider_usage' });
});

test('xAI access check is authenticated and read-only', async () => {
  await checkProviderAccess({ xai: 'fixture' }, async (url, options) => {
    assert.equal(url, 'https://api.x.ai/v1/models');
    assert.equal(options.headers.Authorization, 'Bearer fixture');
    assert.equal(options.method, undefined);
    return Response.json({ data: [] });
  });
});

test('xAI receipt settles once, failed cleanup retains charge, and rejection releases only its hold', async () => {
  const { openLedger } = await import('../ledger.mjs');
  const { createGateway } = await import('../gateway.mjs');
  const { randomBytes } = await import('node:crypto');
  const ledger = openLedger(':memory:');
  try {
    const { account } = ledger.createSession();
    ledger.grant({ account, cents: 100, session: 'cs_xai', intent: 'pi_xai' });
    let calls = 0, status = 200, finish = 'stop';
    const execute = providerClient({ keys: { xai: 'fixture' }, fetchImpl: async () => {
      calls++;
      return Response.json({ id: 'receipt-' + calls, model: cleanup.model, usage: { cost_in_usd_ticks: 270001 }, choices: [{ finish_reason: finish, message: { content: 'Hello.' } }] }, { status });
    } });
    const gateway = createGateway({ ledger, policy, execute, encryptionKey: randomBytes(32) });
    const args = { account, idempotencyKey: 'xai-request-fixture-1', body: { provider: 'xai', operation: 'cleanup', text: 'hello' } };
    assert.equal((await gateway.run(args)).state, 'settled');
    assert.equal((await gateway.run(args)).state, 'settled');
    assert.equal(calls, 1);
    finish = 'length';
    const incomplete = await gateway.run({ ...args, idempotencyKey: 'xai-request-fixture-2' });
    assert.equal(incomplete.state, 'settled');
    assert.match(incomplete.error, /incomplete/);
    assert.equal(ledger.summary(account).paused, false);
    status = 401;
    assert.equal((await gateway.run({ ...args, idempotencyKey: 'xai-request-fixture-3' })).state, 'released');
    assert.equal(ledger.summary(account).reserved, 0);
    assert.equal(ledger.summary(account).paused, false);
  } finally { ledger.close(); }
});

const speechPrice = { model: 'grok-voice-transcribe-2.0', title: 'Grok Voice Transcribe 2.0',
  microsPerSecond: 28, microsPerHour: 100000, maxSeconds: 120, maxRequestMicros: 10000, feeBps: 0 };
const speechPolicy = { version: 'xai-speech-test', expires: null, routes: { 'xai:transcription': {
  ...speechPrice, alternatives: [{ ...speechPrice, model: 'grok-voice-transcribe-1.0', title: 'Grok Voice Transcribe 1.0' }]
} } };
function speechRequest() {
  const audio = Buffer.alloc(44 + 40000);
  audio.write('RIFF'); audio.writeUInt32LE(audio.length - 8, 4); audio.write('WAVEfmt ', 8);
  audio.writeUInt32LE(16, 16); audio.writeUInt16LE(1, 20); audio.writeUInt16LE(1, 22);
  audio.writeUInt32LE(16000, 24); audio.writeUInt32LE(32000, 28); audio.writeUInt16LE(2, 32); audio.writeUInt16LE(16, 34);
  audio.write('data', 36); audio.writeUInt32LE(40000, 40);
  return { provider: 'xai', operation: 'transcription', model: speechPrice.model, audio: audio.toString('base64') };
}

test('both xAI speech models are priced independently from text cleanup', () => {
  assert.deepEqual(modelCatalog(speechPolicy).map(m => m.model), ['grok-voice-transcribe-2.0', 'grok-voice-transcribe-1.0']);
  for (const choice of modelCatalog(speechPolicy)) {
    const request = prepareRequest({ ...speechRequest(), model: choice.model }, speechPolicy);
    assert.equal(request.seconds, 1.25);
    assert.equal(request.maxCost, 56);
  }
  assert.throws(() => prepareRequest({ ...speechRequest(), model: 'grok-4.6' }, speechPolicy));
});

test('xAI speech sends options before the WAV file and settles the confirmed duration', async () => {
  const request = prepareRequest(speechRequest(), speechPolicy);
  const execute = providerClient({ keys: { xai: 'speech-fixture', openrouter: 'never-send' }, fetchImpl: async (url, options) => {
    assert.equal(url, 'https://api.x.ai/v1/stt');
    assert.equal(options.headers.Authorization, 'Bearer speech-fixture');
    assert.deepEqual([...options.body.keys()], ['model', 'file']);
    assert.equal(options.body.get('model'), speechPrice.model);
    assert.deepEqual(Buffer.from(await options.body.get('file').arrayBuffer()), request.audio);
    return Response.json({ text: 'Hello.', duration: 1.25 }, { headers: { 'x-request-id': 'speech-receipt' } });
  } });
  const result = await execute(request);
  assert.equal(result.text, 'Hello.');
  assert.equal(result.cost, 35);
  assert.equal(result.providerId, 'speech-receipt');
});

test('xAI speech rejects missing or mismatched duration and missing receipts', async () => {
  const request = prepareRequest(speechRequest(), speechPolicy);
  for (const duration of [undefined, -1, 100, 1.2345]) {
    const execute = providerClient({ keys: { xai: 'fixture' }, fetchImpl: async () => Response.json({ text: 'Hello.', duration }, { headers: { 'request-id': 'fixture' } }) });
    await assert.rejects(execute(request), { code: 'provider_usage' });
  }
  const execute = providerClient({ keys: { xai: 'fixture' }, fetchImpl: async () => Response.json({ text: 'Hello.', duration: 1.25 }) });
  await assert.rejects(execute(request), { code: 'provider_receipt' });
});
