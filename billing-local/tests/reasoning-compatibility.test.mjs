import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { providerClient } from '../providers.mjs';
import { createGateway } from '../gateway.mjs';
import { openLedger } from '../ledger.mjs';
import { fixturePolicy, prepareRequest } from '../policy.mjs';

test('selected GPT-OSS efforts reach the provider unchanged with the selected model and host', async()=>{
  for(const model of ['openai/gpt-oss-120b','openai/gpt-oss-20b']) for(const saved of ['none','minimal','max','xhigh','low','medium','high']) {
    const policy=structuredClone(fixturePolicy);policy.routes['openrouter:cleanup'].model=model;
    const prepared=prepareRequest({provider:'openrouter',operation:'cleanup',model,text:'Fixture text.',reasoning:saved,host:'cerebras/fp16'},policy);
    const originalFingerprint=prepared.fingerprint;
    const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async(url,init)=>{
      assert.equal(url,'https://openrouter.ai/api/v1/chat/completions');
      const body=JSON.parse(init.body);
      assert.equal(body.reasoning.effort,saved);assert.equal(body.model,model);
      assert.deepEqual(body.provider.only,['cerebras/fp16']);assert.equal(body.provider.allow_fallbacks,false);
      assert.equal(body.provider.data_collection,'deny');
      return Response.json({id:'fixture-receipt',model,usage:{cost:0.00001},choices:[{finish_reason:'stop',message:{content:'Fixture text.'}}]});
    }});
    assert.equal((await execute(prepared)).text,'Fixture text.');
    assert.equal(prepared.reasoning,saved);assert.equal(prepared.fingerprint,originalFingerprint);
  }
});

test('default effort is omitted and other models keep their explicit supported selection',async()=>{
  for(const [model,effort] of [['openai/gpt-oss-120b',undefined],['fixture/optional-reasoning','none']]) {
    const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async(_,init)=>{
      assert.equal(JSON.parse(init.body).reasoning?.effort,effort);
      return Response.json({id:'fixture-receipt',model,usage:{cost:0},choices:[{finish_reason:'stop',message:{content:'Done.'}}]});
    }});
    await execute({provider:'openrouter',operation:'cleanup',model,reasoning:effort,text:'Fixture.',price:fixturePolicy.routes['openrouter:cleanup']});
  }
});

test('cleanup rejection names its operation and status, hides raw provider content and releases only its hold',async()=>{
  const ledger=openLedger(':memory:');
  try {
    const {account}=ledger.createSession();ledger.grant({account,cents:500,session:'fixture-payment',intent:'fixture-intent'});
    let calls=0;
    const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async()=>{calls++;return Response.json({error:{message:'private transcript and secret token'}},{status:400})}});
    const gateway=createGateway({ledger,policy:fixturePolicy,execute,encryptionKey:randomBytes(32)});
    const input={account,idempotencyKey:'rejected-cleanup-fixture',body:{provider:'openrouter',operation:'cleanup',text:'Fixture.'}};
    const result=await gateway.run(input);
    assert.equal(result.state,'released');assert.match(result.error,/text cleanup/i);assert.match(result.error,/400/);
    assert.doesNotMatch(result.error,/recording|speech model|private transcript|secret token/i);
    assert.equal(ledger.summary(account).available,500);assert.equal(ledger.health().paused,false);
    assert.deepEqual(await gateway.run(input),result);assert.equal(calls,1);
  } finally {ledger.close();}
});
