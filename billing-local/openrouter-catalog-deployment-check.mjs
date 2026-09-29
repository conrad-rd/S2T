import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
let tests=readFileSync('tests/openrouter-catalog.test.mjs','utf8').replace(/^import .*;\n/gm,'');
const snapshot=JSON.parse(readFileSync('tests/fixtures/openrouter-models-2026-09-20.json'));
tests=tests.replace(" const {readFileSync}=await import('node:fs');\n const snapshot=JSON.parse(readFileSync(new URL('./fixtures/openrouter-models-2026-09-20.json',import.meta.url)));",' const snapshot='+JSON.stringify(snapshot)+';');
const fixture=`
import assert from 'node:assert/strict';
const catalogTests=[];
const test=(name,run)=>catalogTests.push({name,run});
${tests}
export class CatalogFixture extends CreditsLedger {
 async fetch(request) {
  const index=new URL(request.url).searchParams.get('index');
  if(index===null)return Response.json(catalogTests.map(t=>t.name));
  try {await catalogTests[Number(index)].run();return Response.json({name:catalogTests[Number(index)].name});}
  catch(error){return Response.json({error:String(error),stack:error.stack},{status:500});}
 }
 async verifyLedger() {
  const account=this.ledger.createSession().account;
  this.ledger.grant({account,cents:500,session:'catalog-purchase',intent:'catalog-intent'});
  const {service}=catalog();let calls=0;
  const gateway=createGateway({ledger:this.ledger,policy:catalogPolicy,resolvePolicy:body=>service.policyFor(body),encryptionKey:Buffer.alloc(32,7),
   execute:async request=>{calls++;return {text:'Edited fixture.',cost:10,providerId:'receipt-'+calls,model:request.model,host:request.price.host};}});
  const input={account,idempotencyKey:'catalog-regression-request',body:{provider:'openrouter',operation:'cleanup',model:'fixture/fable-5.1',host:'fixture/fp16',text:'Synthetic dictated material.'}};
  const result=await gateway.run(input), replay=await gateway.run(input);
  assert.equal(result.state,'settled');assert.equal(replay.id,result.id);assert.equal(calls,1);
  assert.equal(result.result.model,'fixture/fable-5.1');assert.equal(result.result.host,'fixture/fp16');
  assert.equal(this.ledger.summary(account).reserved,0);
  await assert.rejects(gateway.run({...input,idempotencyKey:'catalog-unlisted-host',body:{...input.body,host:'not-listed'}}));
  assert.equal(calls,1);assert.equal(this.ledger.summary(account).reserved,0);
  return {settled:true,replayChargedOnce:true,unlistedHostRejectedBeforeReservation:true};
 }
}`;
const artifact=process.env.S2T_DEPLOYMENT_ARTIFACT || '../build/openrouter-models/worker.js';
const mf=new Miniflare(convertV4MiniflareOptions({name:'catalog-test',modules:true,script:readFileSync(artifact,'utf8')+fixture,compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],durableObjects:{CREDITS:{className:'CatalogFixture',useSQLite:true}},bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:'https://credits.example.com',S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'}}));
try {
 const ns=await mf.getDurableObjectNamespace('CREDITS');const stub=ns.get(ns.idFromName('catalog'));
 const names=await (await stub.fetch('https://credits.example.com/')).json();
 for(let i=0;i<names.length;i++) {const response=await stub.fetch('https://credits.example.com/?index='+i);const result=await response.json();assert.equal(response.status,200,JSON.stringify(result));console.log('PASS',result.name);}
 console.log('PASS',await stub.verifyLedger());
} finally {await mf.dispose();}
