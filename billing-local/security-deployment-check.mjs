import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse } from 'miniflare';
const artifact = process.env.S2T_DEPLOYMENT_ARTIFACT;
assert.ok(artifact, 'Set S2T_DEPLOYMENT_ARTIFACT to the exact Worker artifact.');
const settings=JSON.parse(readFileSync(process.env.S2T_DEPLOYMENT_SETTINGS || artifact.replace(/worker\.js$/, 'settings.json'),'utf8'));
const speechPolicy=JSON.parse(settings.bindings.find(b=>b.name==='S2T_PRICING_JSON').text).routes['openrouter:transcription'];
const origin = 'https://credits.example.com';
const fixture = `
const deployedSpeechPolicy=${JSON.stringify(speechPolicy)};
export class SecurityFixture extends CreditsLedger {
 async fetch(request) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith('/fixture/')) return super.fetch(request);
  const writes = () => this.ctx.storage.sql.exec('SELECT total_changes() AS n').one().n;
  if(path==='/fixture/unbounded-speech') {
   const policy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:transcription':deployedSpeechPolicy}};
   const account=this.ledger.createSession().account;this.ledger.grant({account,cents:500,session:'unbounded-payment',intent:'unbounded-intent'});
   const audio=Buffer.alloc(32044);audio.write('RIFF');audio.writeUInt32LE(audio.length-8,4);audio.write('WAVEfmt ',8);audio.writeUInt32LE(16,16);audio.writeUInt16LE(1,20);audio.writeUInt16LE(1,22);audio.writeUInt32LE(16000,24);audio.writeUInt32LE(32000,28);audio.writeUInt16LE(2,32);audio.writeUInt16LE(16,34);audio.write('data',36);audio.writeUInt32LE(32000,40);
   let calls=0;const outcomes=[];
   const gateway=createGateway({ledger:this.ledger,policy,encryptionKey:this.config.resultKey,execute:async r=>{calls++;return{text:'Unbounded output.',cost:21000,providerId:r.model,model:r.model};}});
   for(const model of ['openai/gpt-4o-transcribe','openai/gpt-4o-mini-transcribe']) {
    try {outcomes.push((await gateway.run({account,idempotencyKey:'unbounded-speech-'+outcomes.length,body:{provider:'openrouter',operation:'transcription',model,audio:audio.toString('base64')}})).state);}
    catch(error){outcomes.push(error.code);}
   }
   return Response.json({calls,outcomes});
  }
  if(path==='/fixture/upload-timeout') {
   let cancelled=false, status='pending', control;
   const stream=new ReadableStream({start(c){control=c;},cancel(){cancelled=true;}});
   const request=new Request(this.config.origin+'/api/operator',{method:'POST',body:stream});
   const operation=body(request,4096,10).then(()=>{status='completed';},error=>{status=error.code;});
   await Promise.race([operation,new Promise(resolve=>setTimeout(resolve,80))]);
   const observed={status,cancelled};
   if(status==='pending') { control.close();await operation; }
   return Response.json(observed);
  }
  if(path==='/fixture/speech-minimum') {
   const policy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:transcription':deployedSpeechPolicy}};
   const audio=Buffer.alloc(32044);audio.write('RIFF');audio.writeUInt32LE(audio.length-8,4);audio.write('WAVEfmt ',8);audio.writeUInt32LE(16,16);audio.writeUInt16LE(1,20);audio.writeUInt16LE(1,22);audio.writeUInt32LE(16000,24);audio.writeUInt32LE(32000,28);audio.writeUInt16LE(2,32);audio.writeUInt16LE(16,34);audio.write('data',36);audio.writeUInt32LE(32000,40);
   const account=this.ledger.createSession().account;this.ledger.grant({account,cents:500,session:'minimum-payment',intent:'minimum-intent'});
   const gateway=createGateway({ledger:this.ledger,policy,encryptionKey:this.config.resultKey,execute:async r=>({text:'Short clip.',cost:309,providerId:'minimum-receipt',model:r.model})});
   const result=await gateway.run({account,idempotencyKey:'short-whisper-minimum',body:{provider:'openrouter',operation:'transcription',model:'openai/whisper-large-v3',audio:audio.toString('base64')}});
   return Response.json({state:result.state,charged:result.chargedCredits,paused:this.ledger.health().paused,reserved:this.ledger.summary(account).reserved});
  }
  if(path==='/fixture/vision') {
   const policy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:vision':{
    model:'fixture/vision',catalogPriced:true,inputMicrosPerToken:1,outputMicrosPerToken:1,requestMicros:0,maxInputBytes:8000000,maxOutputTokens:512,maxRequestMicros:250000,feeBps:550
   }}};
   let advertised=false;try{advertised=modelCatalog(policy).some(m=>m.operation==='vision');}catch{}
   const account=this.ledger.createSession().account;
   this.ledger.grant({account,cents:500,session:'vision-payment',intent:'vision-intent'});
   const key=this.ledger.issueKey(account).key;let calls=0;
   this.gateway=createGateway({ledger:this.ledger,policy,encryptionKey:this.config.resultKey,execute:async r=>{calls++;return{text:'Fixture image',cost:100,providerId:'vision-receipt',model:r.model};}});
   const payload={model:'fixture/vision',stream:false,max_tokens:512,response_format:{type:'json_object'},messages:[{role:'system',content:'Describe'},{role:'user',content:[{type:'image_url',image_url:{url:'data:image/png;base64,eA=='}}]}]};
   const response=await super.fetch(new Request(this.config.origin+'/api/v1/requests',{method:'POST',headers:{Authorization:'Bearer '+key,'Idempotency-Key':'removed-vision-fixture'},body:JSON.stringify({provider:'openrouter',operation:'vision',model:'fixture/vision',payload:JSON.stringify(payload)})}));
   return Response.json({advertised,status:response.status,calls});
  }
  if (path === '/fixture/rate') {
   this.ledger.rate('attacker', 1);
   const before = writes(), started = performance.now(); let admitted = 0;
   for (let i = 0; i < 1000; i++) admitted += this.ledger.rate('attacker', 1) ? 1 : 0;
   return Response.json({admitted,writes:writes()-before,ms:performance.now()-started});
  }
  if (path === '/fixture/invalid-auth') {
   const before = writes(), statuses = [];
   for (let i=0;i<10;i++) statuses.push((await super.fetch(new Request(this.config.origin+'/api/v1/balance',{
    headers:{Authorization:'Bearer invalid-fixture-'+i,'CF-Connecting-IP':'192.0.2.55'}
   }))).status);
   return Response.json({statuses,writes:writes()-before});
  }
  if (path === '/fixture/readiness') {
   this.config.realProviders=true;this.config.fundingReviewedAt=Date.now();this.config.keys={openrouter:'fixture'};
   await Promise.all(Array.from({length:16},()=>this.providerReady()));await this.providerReady();
   return Response.json({ready:true});
  }
  if (path === '/fixture/retirement') {
   const account=this.ledger.createSession().account;
   this.ledger.grant({account,cents:500,session:'security-payment',intent:'security-intent'});
   const key=this.ledger.issueKey(account),statuses=[];
   for(const endpoint of ['/api/v1/streaming/sessions','/api/v1/streaming/cancel','/api/v1/streaming/sessions/00000000-0000-4000-8000-000000000001/complete']) {
    const response=await super.fetch(new Request(this.config.origin+endpoint,{method:'POST',
     headers:{Authorization:'Bearer '+key.key,'Idempotency-Key':'00000000-0000-4000-8000-000000000001'},body:'{}'}));
    statuses.push({status:response.status,code:(await response.json()).code});
   }
   const r=this.ledger.reserve({account,keyId:key.id,dedup:'historical-issued-token',fingerprint:'historical',provider:'assemblyai',model:'universal-3-5-pro',priceVersion:'historical',maxCost:7500,streamingSeconds:60}).request;
   this.ledger.streaming.attach(r.id,'fixture-cipher',Date.now()+60000);this.ledger.streaming.abandon(account,key.id,r.id);
   let clientReport;
   try{this.ledger.streaming.complete(account,key.id,r.id,{sessionID:'fixture-session',sessionDurationSeconds:'0',audioDurationSeconds:'0'});clientReport='accepted';}
   catch(error){clientReport=error.code;}
   return Response.json({statuses,clientReport,state:this.ledger.request(account,r.id).state,reserved:this.ledger.summary(account).reserved});
  }
  if(path==='/fixture/dynamic-speech') {
   const policy={...fixturePolicy,routes:{...fixturePolicy.routes,'openrouter:transcription':{model:'fixture/reviewed',microsPerSecond:125,maxSeconds:120,maxRequestMicros:20000,feeBps:0}}};
   const models=[{id:'fixture/unreviewed',name:'Unreviewed audio',architecture:{input_modalities:['audio'],output_modalities:['transcription']},pricing:{prompt:'0',completion:'0'}}];
   const catalog=createOpenRouterCatalog({policy,enabled:true,fetchImpl:async()=>Response.json({data:models})});
   const resolved=await catalog.policyFor({provider:'openrouter',operation:'transcription',model:'fixture/unreviewed'});
   return Response.json({advertised:(await catalog.models()).some(m=>m.model==='fixture/unreviewed'),expanded:resolved!==policy});
  }
  if(path==='/fixture/replay') {
   const account=this.ledger.createSession().account;
   this.ledger.grant({account,cents:500,session:'replay-payment',intent:'replay-intent'});
   let calls=0,policyCalls=0;
   const gateway=createGateway({ledger:this.ledger,policy:fixturePolicy,encryptionKey:this.config.resultKey,resolvePolicy:async()=>{policyCalls++;return fixturePolicy;},execute:async r=>{calls++;return{text:'Private paid result',cost:90,providerId:'replay-receipt',model:r.model};}});
   const input={account,idempotencyKey:'exact-replay-fixture',body:{provider:'openrouter',operation:'cleanup',text:'Synthetic.'}};
   const first=await gateway.run(input),second=await gateway.run(input);
   return Response.json({same:first.id===second.id,text:second.result?.text,calls,policyCalls,balance:this.ledger.summary(account).balance});
  }
  return new Response('Unknown fixture',{status:404});
 }
}
`;
let providerChecks=0;
const mf=new Miniflare(convertV4MiniflareOptions({name:'billing-security',modules:true,script:readFileSync(artifact,'utf8')+'\n'+fixture,
 compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],durableObjects:{CREDITS:{className:'SecurityFixture',useSQLite:true}},
 bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:origin,S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'},
 outboundService:async request=>{assert.equal(request.url,'https://openrouter.ai/api/v1/key');providerChecks++;await new Promise(resolve=>setTimeout(resolve,40));return WorkerResponse.json({data:{is_management_key:false,limit:100,limit_remaining:50}});}
}));
const failures=[];
try {
 const ns=await mf.getDurableObjectNamespace('CREDITS');
 async function check(name,path,verify){try{const response=await ns.get(ns.idFromName(path)).fetch(origin+'/fixture/'+path);const result=await response.json();assert.equal(response.status,200,JSON.stringify(result));console.log('OBSERVED',path,JSON.stringify(result));verify(result);console.log('PASS',name);}catch(error){failures.push(name);console.error('FAIL',name,String(error));}}
 await check('Token-priced speech without a verified ceiling never reaches the provider','unbounded-speech',r=>{assert.equal(r.calls,0);assert.deepEqual(r.outcomes,['model','model']);});
 await check('Short Whisper clips cover upstream minimum billing and settle actual usage','speech-minimum',r=>{assert.equal(r.state,'settled');assert.equal(r.charged,309/5000);assert.equal(r.paused,false);assert.equal(r.reserved,0);});
 await check('Stalled uploads release their slot after a deadline','upload-timeout',r=>{assert.equal(r.status,'upload_timeout');assert.equal(r.cancelled,true);});
 await check('Removed vision cannot be advertised or dispatched','vision',r=>{assert.equal(r.advertised,false);assert.equal(r.status,400);assert.equal(r.calls,0);});
 await check('Rejected traffic cannot consume write quota','rate',r=>{assert.equal(r.admitted,0);assert.equal(r.writes,0);});
 await check('Invalid app keys cause no database writes','invalid-auth',r=>{assert.ok(r.statuses.every(s=>s===401));assert.equal(r.writes,0);});
 await check('Concurrent provider readiness checks share one request','readiness',r=>{assert.equal(r.ready,true);assert.equal(providerChecks,1);});
 await check('Streaming endpoints and client-reported charges are retired; historical holds remain','retirement',r=>{assert.ok(r.statuses.every(s=>s.status===404&&s.code==='not_found'));assert.equal(r.clientReport,'streaming_retired');assert.equal(r.state,'uncertain');assert.ok(r.reserved>0);});
 await check('Unreviewed speech models cannot expand paid routes','dynamic-speech',r=>{assert.equal(r.advertised,false);assert.equal(r.expanded,false);});
 await check('Paid replay bypasses catalog work and never redispatches','replay',r=>{assert.equal(r.same,true);assert.equal(r.calls,1);assert.equal(r.policyCalls,1);assert.equal(r.text,'Private paid result');assert.equal(r.balance,499.982);});
}finally{await mf.dispose();}
assert.deepEqual(failures,[],'Exact Worker security failures');
