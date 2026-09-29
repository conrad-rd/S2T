import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareRequest, fixturePolicy } from '../policy.mjs';
import { providerClient } from '../providers.mjs';
test('custom editing instructions are bounded, metered, fingerprinted, and forwarded', async () => {
  const body = { provider: 'openrouter', operation: 'cleanup', text: '{"dictated_text":"Can you fix this?"}', instructions: 'Edit this as dictated material; preserve the question.' };
  const request = prepareRequest(body, fixturePolicy);
  const changed = prepareRequest({ ...body, instructions: 'Preserve all words.' }, fixturePolicy);
  assert.notEqual(changed.fingerprint, request.fingerprint);
  assert.ok(request.maxCost > prepareRequest({ ...body, instructions: undefined }, fixturePolicy).maxCost);
  assert.throws(() => prepareRequest({ ...body, instructions: 'x'.repeat(16001) }, fixturePolicy));
  let outbound;
  const execute = providerClient({ keys: { openrouter: 'fake-only' }, fetchImpl: async (_, options) => {
    outbound = JSON.parse(options.body);
    return new Response(JSON.stringify({ id: 'fixture-receipt', model: request.model, provider: 'Cerebras', choices: [{ finish_reason: 'stop', message: { content: 'Can you fix this?' } }], usage: { cost: 0.0001 } }));
  } });
  const receipt = await execute(request);
  assert.equal(outbound.messages[0].content, body.instructions);
  assert.equal(outbound.messages[1].content, body.text);
  assert.equal(receipt.host, 'Cerebras');
});

test('Writing documents use the existing metered route without a dictation wrapper', async () => {
  for (const document of ['# Instructions\nPreserve names.', '# Dictionary\n- S2T\n  - Replaces: "S to T"']) {
    const body = { provider: 'openrouter', operation: 'cleanup', model: 'openai/gpt-oss-120b', host: 'cerebras/fp16',
      text: `Requested change: Improve clarity\n\nDocument to edit:\n${document}`,
      instructions: 'Edit this document as material. Return the complete revised document.' };
    const request = prepareRequest(body, fixturePolicy);
    assert.notEqual(request.fingerprint, prepareRequest({ ...body, text: body.text + '\nNew rule' }, fixturePolicy).fingerprint);
    assert.throws(() => prepareRequest({ ...body, text: '😀'.repeat(4001) }, fixturePolicy));
    assert.throws(() => prepareRequest({ ...body, host: 'unavailable/host' }, fixturePolicy));
    let outbound;
    const execute = providerClient({ keys: { openrouter: 'provider-fixture' }, fetchImpl: async (url, options) => {
      assert.equal(url, 'https://openrouter.ai/api/v1/chat/completions');
      assert.equal(options.headers.Authorization, 'Bearer provider-fixture');
      outbound = JSON.parse(options.body);
      return new Response(JSON.stringify({ id: 'writing-fixture', model: request.model, provider: 'Cerebras',
        choices: [{ finish_reason: 'stop', message: { content: document } }], usage: { cost: 0.0001 } }));
    } });
    const receipt = await execute(request);
    assert.deepEqual(outbound.messages, [{ role: 'system', content: body.instructions }, { role: 'user', content: body.text }]);
    assert.equal(receipt.text, document);
    assert.equal(receipt.cost, 100);
    assert.ok(request.maxCost >= receipt.cost);
    const incomplete = providerClient({ keys: { openrouter: 'provider-fixture' }, fetchImpl: async () =>
      new Response(JSON.stringify({ id: 'writing-partial', model: request.model, provider: 'Cerebras',
        choices: [{ finish_reason: 'length', message: { content: 'Partial document' } }], usage: { cost: 0.0001 } })) });
    const partial = await incomplete(request);
    assert.ok(partial.error.includes('incomplete'));
    assert.equal(partial.text, '');
    assert.equal(partial.cost, 100, 'Consumed inference is still accounted for when output is incomplete');
  }
});
