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
