import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {fixturePolicy, prepareRequest} from './policy.mjs';
import {providerClient} from './providers.mjs';
import {openLedger} from './ledger.mjs';
import {createGateway} from './gateway.mjs';

const decisions = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(decisions.length, 3);
assert.equal(decisions.reduce((n, d) => n + Object.keys(d.questions).length, 0), 101);
const policy = {...fixturePolicy, routes: {...fixturePolicy.routes, 'openrouter:decisions': {
  model: 'typesafe/jev-1.13', title: 'Jev 1.13', inputMicrosPerThousandTokens: 42,
  maxInputBytes: 65536, maxRequestMicros: 3000, feeBps: 550,
}}};
let calls = 0;
const execute = providerClient({keys: {openrouter: 'isolated-fixture'}, fetchImpl: async (url, options) => {
  assert.equal(url, 'https://openrouter.ai/api/alpha/decisions');
  assert.equal(options.headers.Authorization, 'Bearer isolated-fixture');
  const request = JSON.parse(options.body);
  calls++;
  return Response.json({id: `dictionary-fixture-${calls}`, model: 'typesafe/jev-1.13',
    answers: Object.fromEntries(Object.keys(request.questions).map(id => [id, {type: 'noul', noul: 0.99}])),
    usage: {cost: 0.00001}});
}});
const ledger = openLedger(':memory:');
try {
  const {account} = ledger.createSession();
  ledger.grant({account, cents: 100, session: 'cs-dictionary-fixture', intent: 'pi-dictionary-fixture'});
  const gateway = createGateway({ledger, policy, execute, encryptionKey: randomBytes(32)});
  for (const [index, decision] of decisions.entries()) {
    const body = {provider: 'openrouter', operation: 'decisions', model: decision.model, text: JSON.stringify(decision)};
    assert.ok(prepareRequest(body, policy).maxCost <= 3000);
    const args = {account, body, idempotencyKey: `dictionary-native-fixture-${index}`};
    const first = await gateway.run(args);
    assert.equal(first.state, 'settled');
    assert.ok(first.chargedCredits > 0);
    assert.deepEqual(await gateway.run(args), first);
    assert.ok(!ledger.request(account, first.id).result.includes('answers'));
    assert.throws(() => gateway.get(ledger.createSession().account, first.id));
  }
  assert.equal(calls, 3);
  assert.equal(ledger.health().paused, false);
  console.log('PASS: actual native dictionary requests pass the existing credit policy, mock provider, encrypted ledger, replay and account isolation. No live calls or payments.');
} finally { ledger.close(); }
