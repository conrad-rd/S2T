import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes, randomUUID} from 'node:crypto';
import Stripe from 'stripe';
import {openLedger} from '../ledger.mjs';
import {createGateway} from '../gateway.mjs';
import {providerClient} from '../providers.mjs';
import {fixturePolicy} from '../policy.mjs';
import {createStripeBilling} from '../stripe-billing.mjs';
const setup=()=>{const ledger=openLedger(':memory:',{mode:'test'}),account=ledger.createSession().account;ledger.grant({account,cents:500,session:'cs-audit',intent:'pi-audit'});return {ledger,account};};
const reserve=(ledger,account,key='fixture')=>ledger.reserve({account,dedup:key,fingerprint:key,provider:'openrouter',model:'fixture',priceVersion:'fixture',maxCost:10000}).request;
const input=account=>({account,idempotencyKey:'audit-request-fixture',body:{provider:'openrouter',operation:'cleanup',text:'Example text.'}});

test('partial dispute removes only disputed credit; winning restores once across stale events and intervening refunds', async()=>{
 const {ledger,account}=setup();let dispute={id:'dp-audit',currency:'usd',payment_intent:'pi-audit',amount:100,status:'needs_response'};
 const billing=createStripeBilling({ledger,mode:'test',secret:'whsec_audit',stripeClient:{disputes:{retrieve:async()=>({...dispute})}}});
 const send=async type=>{const raw=JSON.stringify({type,livemode:false,data:{object:{id:dispute.id}}});return billing.webhook(Buffer.from(raw),Stripe.webhooks.generateTestHeaderString({payload:raw,secret:'whsec_audit'}));};
 try {
  await send('charge.dispute.created');assert.equal(ledger.summary(account).balance,400);assert.equal(ledger.summary(account).frozen,true);
  ledger.reverse({id:'re-audit',intent:'pi-audit',cents:50,kind:'refund'});assert.equal(ledger.summary(account).balance,350);
  dispute.status='won';await send('charge.dispute.closed');await send('charge.dispute.funds_reinstated');
  assert.equal(ledger.summary(account).balance,450);assert.equal(ledger.summary(account).frozen,false);
  dispute.status='under_review';await send('charge.dispute.created');
  assert.equal(ledger.summary(account).balance,450);assert.equal(ledger.summary(account).frozen,false);
  ledger.reverse({id:'re-rest',intent:'pi-audit',cents:450,kind:'refund'});assert.equal(ledger.summary(account).balance,0);
 }finally{ledger.close();}
});
test('won dispute arriving before purchase never removes credits or freezes the eventual buyer',()=>{
 const ledger=openLedger(':memory:',{mode:'test'}),account=ledger.createSession().account;
 try {
  ledger.dispute({id:'dp-early',intent:'pi-early',cents:100,status:'won'});
  ledger.grant({account,cents:500,session:'cs-early',intent:'pi-early'});
  assert.equal(ledger.summary(account).balance,500);assert.equal(ledger.summary(account).frozen,false);
 }finally{ledger.close();}
});
test('refund freeze clears when its unsubmitted hold is cancelled',()=>{
 const {ledger,account}=setup();try{
  const r=reserve(ledger,account);ledger.reverse({id:'refund-all',intent:'pi-audit',cents:500,kind:'refund'});
  assert.equal(ledger.summary(account).frozen,true);ledger.cancel(account,r.id);
  assert.equal(ledger.summary(account).frozen,false);assert.equal(ledger.summary(account).available,0);
  assert.ok(ledger.checkoutOrder(account,500,'purchase-after-refund').id);
 }finally{ledger.close();}
});
test('durability failure before dispatch releases the unused hold and never calls the provider',async()=>{
 const {ledger,account}=setup();let calls=0;
 const gateway=createGateway({ledger,policy:fixturePolicy,encryptionKey:randomBytes(32),execute:async()=>{calls++;},confirmReservation:async()=>{throw Error('storage unavailable');}});
 try{await assert.rejects(gateway.run(input(account)));assert.equal(calls,0);assert.equal(ledger.summary(account).reserved,0);assert.equal(ledger.health().paused,false);}
 finally{ledger.close();}
});
for(const bad of ['model','cost']) test('provider '+bad+' failures retain receipts without pausing unrelated usage',async()=>{
 const {ledger,account}=setup();const execute=providerClient({keys:{openrouter:'fixture'},fetchImpl:async()=>Response.json({id:'safe-receipt',model:bad==='model'?'unexpected/model':'openai/gpt-oss-120b',usage:{cost:bad==='cost'?'bad':0.0001},choices:[{finish_reason:'stop',message:{content:'Private words'}}]})});
 const gateway=createGateway({ledger,policy:fixturePolicy,encryptionKey:randomBytes(32),execute});
 try{const result=await gateway.run(input(account));assert.equal(result.state,'uncertain');assert.equal(ledger.health().paused,false);assert.equal(ledger.request(account,result.id).provider_id,'safe-receipt');assert.ok(!JSON.stringify(ledger.health()).includes('Private words'));}
 finally{ledger.close();}
});
test('writeoff retries remain idempotent and do not spend or restore additional credits',()=>{
 const {ledger,account}=setup();try{const r=reserve(ledger,account);ledger.submit(r.id);ledger.uncertain(r.id,'fixture');const reason='S2T absorbs this confirmed test failure.';assert.equal(ledger.writeOff(r.id,reason),true);assert.equal(ledger.writeOff(r.id,reason),false);assert.equal(ledger.summary(account).balance,500);ledger.resume();}
 finally{ledger.close();}
});
test('written-off requests return a retryable uncharged error without submitting again',async()=>{
 const {ledger,account}=setup();let calls=0;
 const gateway=createGateway({ledger,policy:fixturePolicy,encryptionKey:randomBytes(32),execute:async()=>{calls++;throw Error('unknown network outcome');}});
 try{
  const pending=await gateway.run(input(account));
  ledger.writeOff(pending.id,'S2T absorbs this unknown provider charge.');
  const replay=await gateway.run(input(account));
  assert.equal(replay.state,'settled');assert.equal(replay.chargedCredits,0);assert.equal(replay.reservedCredits,0);
  assert.match(replay.error,/No credits were charged/);assert.equal(calls,1);
 }finally{ledger.close();}
});
test('historical abandoned issued tokens retain exposure until their authorization windows close',()=>{
 let time=Date.now();const ledger=openLedger(':memory:',{now:()=>time}),account=ledger.createSession().account;ledger.grant({account,cents:500,session:'cs-stream',intent:'pi-stream'});const keyId=ledger.issueKey(account).id;
 const reserve=()=>{const id=randomUUID();return ledger.reserve({account,keyId,dedup:id,fingerprint:id,provider:'assemblyai',model:'universal-3-5-pro',priceVersion:'legacy-streaming',maxCost:630*125,streamingSeconds:630}).request;};
 try{
  for(let n=0;n<8;n++){const r=reserve();ledger.streaming.attach(r.id,'encrypted-historical-token',time+60000);ledger.streaming.abandon(account,keyId,r.id);}
  assert.throws(reserve,{code:'streaming_concurrency'});
  time+=721000;
  assert.ok(reserve().id);
 }finally{ledger.close();}
});
