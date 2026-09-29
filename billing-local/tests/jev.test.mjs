import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {fixturePolicy, prepareRequest, validatePolicy, modelCatalog} from '../policy.mjs';
import {providerClient} from '../providers.mjs';
import {openLedger} from '../ledger.mjs';
import {createGateway} from '../gateway.mjs';
export const jevPrice={model:'typesafe/jev-1.13',title:'Jev 1.13',inputMicrosPerThousandTokens:42,maxInputBytes:65536,maxRequestMicros:3000,feeBps:550};
const policy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:decisions':jevPrice}};
const decision={model:jevPrice.model,state:{transcript:'Uh, hello.'},questions:{edit0:{type:'noul',instructions:'Is this an accidental hesitation?'}}};
const body={provider:'openrouter',operation:'decisions',model:jevPrice.model,text:JSON.stringify(decision)};
test('Jev validates bounded priced decisions and exposes a separate catalog operation',()=>{
 validatePolicy(policy);
 assert.equal(modelCatalog(policy).find(m=>m.operation==='decisions').model,jevPrice.model);
 const request=prepareRequest(body,policy);
 assert.ok(request.maxCost>0 && request.maxCost<=3000);
 for(const changed of [{model:'~typesafe/jev-latest'},{host:'cerebras/fp16'},{audio:'abc'},{text:JSON.stringify({...decision,tools:[]})},{text:JSON.stringify({...decision,questions:{}})}]) assert.throws(()=>prepareRequest({...body,...changed},policy));
});
test('Jev charges one receipt, encrypts decisions, replays without inference and preserves account isolation',async()=>{
 const ledger=openLedger(':memory:');
 try {
  const {account}=ledger.createSession();ledger.grant({account,cents:100,session:'cs-jev',intent:'pi-jev'});
  let calls=0;
  const execute=providerClient({keys:{openrouter:'hosted-fixture'},fetchImpl:async(url,options)=>{
   calls++;assert.equal(url,'https://openrouter.ai/api/alpha/decisions');assert.equal(options.headers.Authorization,'Bearer hosted-fixture');assert.equal(options.redirect,'manual');assert.deepEqual(JSON.parse(options.body),decision);
   return Response.json({id:'jev-receipt',model:'typesafe/jev-1.13',answers:{edit0:{type:'noul',noul:0.99}},usage:{cost:4.2e-7}});
  }});
  const gateway=createGateway({ledger,policy,execute,encryptionKey:randomBytes(32)});
  const args={account,idempotencyKey:'jev-credit-fixture-001',body};
  const first=await gateway.run(args);assert.equal(first.state,'settled');assert.ok(first.chargedCredits>0);assert.equal(JSON.parse(first.result.text).answers.edit0.noul,0.99);
  assert.deepEqual(await gateway.run(args),first);assert.equal(calls,1);assert.equal(ledger.health().paused,false);
  assert.ok(!ledger.request(account,first.id).result.includes('edit0'));
  assert.throws(()=>gateway.get(ledger.createSession().account,first.id));
 } finally {ledger.close();}
});
test('invalid Jev decisions with a valid receipt settle without pausing credit usage',async()=>{
 const request=prepareRequest(body,policy);
 const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async()=>Response.json({id:'bad-answer-receipt',model:'unexpected-model',answers:{},usage:{cost:0.000001}})});
 const receipt=await execute(request);assert.equal(receipt.cost,1);assert.match(receipt.error,/invalid decisions/);assert.equal(receipt.text,'');
});
