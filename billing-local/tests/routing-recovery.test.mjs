import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { openLedger } from '../ledger.mjs';
import { createGateway } from '../gateway.mjs';
import { fixturePolicy } from '../policy.mjs';
import { providerClient } from '../providers.mjs';

test('a definitive provider routing rejection releases its hold and does not disable other dictations', async () => {
  const ledger = openLedger(':memory:');
  try {
    const {account} = ledger.createSession();
    ledger.grant({account,cents:100,session:'cs-routing',intent:'pi-routing'});
    const execute = providerClient({keys:{openrouter:'fixture'},fetchImpl:async () => new Response(JSON.stringify({error:{message:'No endpoints found'}}),{status:404})});
    const gateway = createGateway({ledger,policy:fixturePolicy,execute,encryptionKey:randomBytes(32)});
    const args = {account,idempotencyKey:'routing-rejected-fixture',body:{provider:'openrouter',operation:'cleanup',text:'Preserve this dictation.'}};
    const result = await gateway.run(args);
    assert.equal(result.state,'released');
    assert.match(result.error,/route|host/i);
    assert.equal(ledger.summary(account).reserved,0);
    assert.equal(ledger.summary(account).paused,false);
    assert.equal((await gateway.run(args)).error,result.error);
  } finally { ledger.close(); }
});

test('S2T OpenRouter speech sends the same audio contract as a personal key and meters the generation receipt', async () => {
  const {readFileSync} = await import('node:fs');
  const {prepareRequest, modelCatalog} = await import('../policy.mjs');
  const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc',import.meta.url),'utf8'));
  const policy = JSON.parse(config.vars.S2T_PRICING_JSON);
  const audio = Buffer.alloc(32044);
  audio.write('RIFF'); audio.writeUInt32LE(audio.length-8,4); audio.write('WAVEfmt ',8);
  audio.writeUInt32LE(16,16); audio.writeUInt16LE(1,20); audio.writeUInt16LE(1,22);
  audio.writeUInt32LE(16000,24); audio.writeUInt32LE(32000,28); audio.writeUInt16LE(2,32); audio.writeUInt16LE(16,34);
  audio.write('data',36); audio.writeUInt32LE(32000,40);
  const choices = modelCatalog(policy).filter(m => m.provider === 'openrouter' && m.operation === 'transcription');
  assert.equal(choices.length,19);
  assert.ok(choices.some(choice => choice.model === 'microsoft/mai-transcribe-2'));
  assert.ok(choices.some(choice => choice.model === 'nvidia/parakeet-tdt-0.6b-v3'));
  for (const choice of choices) {
    const prepared = prepareRequest({provider:'openrouter',operation:'transcription',model:choice.model,audio:audio.toString('base64')},policy);
    let calls = 0;
    const result = await providerClient({keys:{openrouter:'speech-fixture',assemblyai:'never-use'},fetchImpl:async (url,init) => {
      calls++;
      assert.equal(url,'https://openrouter.ai/api/v1/audio/transcriptions');
      assert.equal(init.headers.Authorization,'Bearer speech-fixture');
      assert.deepEqual(JSON.parse(init.body),{model:choice.model,input_audio:{data:audio.toString('base64'),format:'wav'}});
      return new Response(JSON.stringify({text:'A complete transcription.',usage:{cost:0.0001}}),{headers:{'X-Generation-Id':'speech-receipt'}});
    }})(prepared);
    assert.equal(calls,1);
    assert.equal(result.text,'A complete transcription.');
    assert.equal(result.providerId,'speech-receipt');
    assert.equal(result.cost,100);
    assert.ok(result.cost <= prepared.maxCost);
  }
});

test('a truncated paid cleanup settles once and preserves the original-text fallback without pausing transcription', async () => {
  const ledger = openLedger(':memory:');
  try {
    const {account} = ledger.createSession();
    ledger.grant({account,cents:100,session:'cs-truncated',intent:'pi-truncated'});
    let calls=0;
    const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async () => {
      calls++;
      return Response.json({id:'receipt-truncated',model:'openai/gpt-oss-120b',usage:{cost:0.0001},choices:[{finish_reason:'length',message:{content:'Partial text that must never be delivered'}}]});
    }});
    const gateway=createGateway({ledger,policy:fixturePolicy,execute,encryptionKey:randomBytes(32)});
    const args={account,idempotencyKey:'truncated-fixture',body:{provider:'openrouter',operation:'cleanup',text:'The complete original words.'}};
    const result=await gateway.run(args);
    assert.equal(result.state,'settled');
    assert.match(result.error,/original transcription/);
    assert.equal(result.result,undefined);
    assert.equal(ledger.summary(account).paused,false);
    assert.equal(ledger.summary(account).reserved,0);
    assert.equal((await gateway.run(args)).error,result.error);
    assert.equal(calls,1);
  } finally {ledger.close();}
});
