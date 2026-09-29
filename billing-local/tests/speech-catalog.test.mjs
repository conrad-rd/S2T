import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {modelCatalog, prepareRequest, validatePolicy} from '../policy.mjs';
const catalog = JSON.parse(readFileSync(new URL('./fixtures/openrouter-speech-2026-09-19.json', import.meta.url)));
const policy = JSON.parse(JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url))).vars.S2T_PRICING_JSON);
function wave(seconds) {
  const b=Buffer.alloc(44+32000*seconds);
  b.write('RIFF'); b.writeUInt32LE(b.length-8,4); b.write('WAVEfmt ',8);
  b.writeUInt32LE(16,16); b.writeUInt16LE(1,20); b.writeUInt16LE(1,22);
  b.writeUInt32LE(16000,24); b.writeUInt32LE(32000,28); b.writeUInt16LE(2,32); b.writeUInt16LE(16,34);
  b.write('data',36); b.writeUInt32LE(b.length-44,40); return b.toString('base64');
}
const unboundedModels = new Set(['openai/gpt-4o-transcribe','openai/gpt-4o-mini-transcribe']);
test('S2T accepts reviewed duration-priced speech models, including MAI 2, at the full clip limit',()=>{
  const listed=modelCatalog(policy).filter(x=>x.provider==='openrouter'&&x.operation==='transcription');
  const bounded=catalog.filter(x=>!unboundedModels.has(x.id));
  assert.deepEqual(new Set(listed.map(x=>x.model)),new Set(bounded.map(x=>x.id)));
  for (const {id} of bounded) {
    const p=prepareRequest({provider:'openrouter',operation:'transcription',model:id,audio:wave(120)},policy);
    assert.ok(p.maxCost>0&&p.maxCost<=p.price.maxRequestMicros,id);
  }
});
test('unknown models remain rejected before provider dispatch',()=>{
  assert.throws(()=>prepareRequest({provider:'openrouter',operation:'transcription',model:'example/unpriced',audio:wave(1)},policy),/not available/);
});
test('speech without an enforceable upstream ceiling is withheld from S2T credits',()=>{
  for (const model of unboundedModels) {
    assert.throws(()=>prepareRequest({provider:'openrouter',operation:'transcription',model,audio:wave(1)},policy),/not available/);
  }
});
test('request-ceiling reservations cannot be enabled for AssemblyAI or with a malformed flag',()=>{
  for (const value of [true,'true']) {
    const copy=structuredClone(policy); copy.routes['assemblyai:transcription'].reserveRequestCeiling=value;
    assert.throws(()=>validatePolicy(copy));
  }
});

test('short Whisper uploads reserve the upstream ten-second minimum without charging the reservation', async () => {
  const {openLedger} = await import('../ledger.mjs');
  const {createGateway} = await import('../gateway.mjs');
  const {randomBytes} = await import('node:crypto');
  const ledger = openLedger(':memory:');
  const account = ledger.createSession().account;
  ledger.grant({account,cents:500,session:'minimum-payment',intent:'minimum-intent'});
  let reserved;
  const gateway = createGateway({ledger,policy,encryptionKey:randomBytes(32),execute:async request=>{
    reserved=request.maxCost;
    // Groq Whisper V3's published $0.111/hour and ten-second minimum, rounded up.
    return {text:'Short clip.',cost:309,providerId:'minimum-receipt',model:request.model};
  }});
  try {
    const result=await gateway.run({account,idempotencyKey:'short-whisper-001',body:{provider:'openrouter',operation:'transcription',model:'openai/whisper-large-v3',audio:wave(1)}});
    assert.equal(result.state,'settled');
    assert.ok(reserved>=309);
    assert.equal(result.chargedCredits,309/5000);
    assert.equal(ledger.health().paused,false);
    assert.equal(ledger.summary(account).reserved,0);
  } finally {ledger.close();}
});
