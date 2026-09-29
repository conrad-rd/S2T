import test from 'node:test';
import assert from 'node:assert/strict';
import {createOpenRouterCatalog} from '../openrouter-catalog.mjs';
import {fixturePolicy, prepareRequest} from '../policy.mjs';
import {providerClient} from '../providers.mjs';
const entry = (id, input=['text'], output=['text']) => ({id,name:id,architecture:{input_modalities:input,output_modalities:output},pricing:{prompt:'0.000002',completion:'0.000008'}});
const catalogPolicy=structuredClone(fixturePolicy);
catalogPolicy.routes['openrouter:transcription']={...fixturePolicy.routes['assemblyai:transcription'],model:'fixture/existing-speech'};
const models = [entry('fixture/fable-5.1'),entry('fixture/another-common-model'),entry('fixture/new-speech',['audio'],['transcription']),entry('fixture/image-only',['text'],['image']),entry('fixture/vision-model',['text','image'],['text'])];
function catalog() {
 const calls=[];
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async(url,init)=>{
  calls.push([url,init]);
  const modelID=url.includes('/endpoints') ? url.split('/models/')[1].replace('/endpoints','') : '';
  const selected=models.find(model=>model.id===modelID);
  return Response.json(url.includes('/endpoints') ? {data:{...selected,endpoints:[{tag:'fixture/fp16',provider_name:'Fixture',status:0,pricing:{prompt:'0.000003',completion:'0.00001'}}]}} : {data:models});
 }});
 return {service,calls};
}
test('credit catalog accepts future text models but keeps speech on reviewed routes',async()=>{
 const {service,calls}=catalog();
 const choices=await service.models();
 assert.ok(choices.some(x=>x.model==='fixture/fable-5.1'&&x.host===''));
 assert.ok(!choices.some(x=>x.model==='fixture/new-speech'));
 assert.ok(choices.some(x=>x.model==='fixture/existing-speech'&&x.operation==='transcription'));
 assert.ok(!choices.some(x=>x.model==='fixture/image-only'));
 for(const model of models.slice(0,2)) {
  const body={provider:'openrouter',operation:'cleanup',model:model.id,host:'',text:'An independent dictated fixture.'};
  const prepared=prepareRequest(body,await service.policyFor(body));
  assert.equal(prepared.model,model.id); assert.equal(prepared.price.host,undefined);
  assert.ok(prepared.maxCost<=250000);
 }
 const speech={provider:'openrouter',operation:'transcription',model:'fixture/new-speech',audio:'fixture'};
 assert.throws(()=>prepareRequest(speech,catalogPolicy),/model/i);
 assert.equal(await service.policyFor(speech),catalogPolicy);
 assert.equal(calls.filter(([u])=>!u.includes('/endpoints')).length,1);
 assert.ok(calls.every(([,init])=>!init.headers?.Authorization));
});
test('a higher priced Fable model can reserve a bounded credit request',async()=>{
 const model={...entry('anthropic/claude-fable-5'),pricing:{prompt:'0.000005',completion:'0.000025'}};
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async()=>Response.json({data:[model]})});
 const body={provider:'openrouter',operation:'cleanup',model:model.id,host:'',text:'Please tidy this sentence.'};
 const policy=await service.policyFor(body);
 const prepared=prepareRequest(body,policy);
 assert.equal(prepared.model,model.id);
 assert.ok(prepared.price.maxOutputTokens>=512);
 assert.ok(prepared.maxCost<=250000);
});
test('only hosts published for the selected model can receive credit requests',async()=>{
 const {service}=catalog();
 const body={provider:'openrouter',operation:'cleanup',model:'fixture/fable-5.1',host:'fixture/fp16',text:'Synthetic text.'};
 const prepared=prepareRequest(body,await service.policyFor(body));
 assert.equal(prepared.price.host,'fixture/fp16');
 let sent;
 await providerClient({keys:{openrouter:'fake'},fetchImpl:async(_,init)=>{sent=JSON.parse(init.body);return Response.json({id:'fixture',model:body.model,usage:{cost:0.00001},choices:[{finish_reason:'stop',message:{content:'Done.'}}]});}})(prepared);
 assert.deepEqual(sent.provider.only,['fixture/fp16']);
 await assert.rejects(service.policyFor({...body,host:'unlisted'}),/host/i);
 await assert.rejects(service.policyFor({...body,model:'fixture/image-only'}),/model/i);
});
test('a pinned host uses its endpoint metadata without waiting for the full model catalog',async()=>{
 const calls=[];
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async url=>{
  calls.push(url);
  if (!url.endsWith('/endpoints')) return new Response('',{status:503});
  return Response.json({data:{id:'openai/gpt-oss-120b',architecture:{input_modalities:['text'],output_modalities:['text']},
   endpoints:[{tag:'fixture/alternate',status:0,pricing:{prompt:'0.00000035',completion:'0.00000075'}}]}});
 }});
 const body={provider:'openrouter',operation:'cleanup',model:'openai/gpt-oss-120b',host:'cerebras/fp16',text:'A synthetic transcript.'};
 const prepared=prepareRequest(body,await service.policyFor(body));
 assert.equal(prepared.price.host,'cerebras/fp16');
 assert.deepEqual(calls,[]);
 const second={...body,host:'fixture/alternate'};
 const alternate=prepareRequest(second,await service.policyFor(second));
 assert.equal(alternate.price.host,'fixture/alternate');
 assert.deepEqual(calls,['https://openrouter.ai/api/v1/models/openai/gpt-oss-120b/endpoints']);
});
test('removed image-description requests are unavailable before dispatch',async()=>{
 const {service}=catalog();
 assert.ok((await service.models()).every(model=>model.operation!=='vision'));
 const body={provider:'openrouter',operation:'vision',model:'fixture/vision-model'};
 const policy=await service.policyFor(body);
 assert.throws(()=>prepareRequest(body,policy),/operation is not enabled/);
 await assert.rejects(providerClient({keys:{openrouter:'fixture'},fetchImpl:async()=>{assert.fail('Removed operation dispatched a provider request');}})({...body,price:{}}),/Unsupported OpenRouter operation/);
});
test('legacy configured requests retain their policy and retry fingerprint',async()=>{
 const {service}=catalog(); const body={provider:'openrouter',operation:'cleanup',text:'Legacy.'};
 assert.equal(await service.policyFor(body),catalogPolicy);
 assert.equal(prepareRequest(body,await service.policyFor(body)).fingerprint,prepareRequest(body,fixturePolicy).fingerprint);
});
test('failed metadata loads preserve configured models and fail closed for unknown models',async()=>{
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async()=>new Response('',{status:503})});
 assert.ok((await service.models()).some(x=>x.model==='openai/gpt-oss-120b'));
 await assert.rejects(service.policyFor({provider:'openrouter',operation:'cleanup',model:'unknown/model',host:''}));
});
test('the public snapshot exposes priced text models, but speech requires a reviewed route',async()=>{
 const {readFileSync}=await import('node:fs');
 const snapshot=JSON.parse(readFileSync(new URL('./fixtures/openrouter-models-2026-09-20.json',import.meta.url)));
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async()=>Response.json({data:snapshot})});
 const choices=await service.models();
 const eligible=snapshot.filter(m=>Number(m.pricing.prompt)>=0 && Number(m.pricing.completion)>=0 &&
  m.architecture.input_modalities.includes('text')&&m.architecture.output_modalities.includes('text'));
 for(const m of eligible) assert.ok(choices.some(x=>x.model===m.id),m.id);
 assert.ok(eligible.length>400);
 assert.ok(!choices.some(x=>x.model==='meta/muse-voice-transcribe-1.0'));
});
test('published canonical response aliases settle, while unrelated models remain rejected',async()=>{
 const service=createOpenRouterCatalog({policy:catalogPolicy,enabled:true,fetchImpl:async()=>Response.json({data:[{...models[0],canonical_slug:'fixture/fable-5.1-2026'}]})});
 const body={provider:'openrouter',operation:'cleanup',model:models[0].id,host:'',text:'Synthetic text.'};
 const request=prepareRequest(body,await service.policyFor(body));
 const execute=model=>providerClient({keys:{openrouter:'fake'},fetchImpl:async()=>Response.json({id:'receipt',model,usage:{cost:0.000001},choices:[{finish_reason:'stop',message:{content:'Done.'}}]})})(request);
 assert.equal((await execute('fixture/fable-5.1-2026')).model,'fixture/fable-5.1-2026');
 await assert.rejects(execute('unrelated/model'),/unexpected model/);
});
