import test from 'node:test';
import assert from 'node:assert/strict';
import {providerClient} from '../providers.mjs';
const request={provider:'assemblyai',operation:'transcription',model:'universal-3-5-pro',seconds:2,audio:Buffer.from('synthetic-audio'),price:{microsPerSecond:125}};
test('AssemblyAI 404 falls back once, bills batch rate and preserves the final receipt',async()=>{
 const calls=[];const responses=[new Response('Not found',{status:404}),Response.json({upload_url:'https://cdn.assemblyai.com/fixture'}),Response.json({id:'batch-fixture',status:'queued'}),Response.json({id:'batch-fixture',status:'completed',text:'Recovered text.'})];
 const execute=providerClient({keys:{assemblyai:'assembly-only',openrouter:'never-send'},sleep:async()=>{},fetchImpl:async(url,init)=>{calls.push({url,init});assert.equal(init.headers.Authorization,'assembly-only');return responses.shift();}});
 const result=await execute(request);assert.equal(result.text,'Recovered text.');assert.equal(result.providerId,'batch-fixture');assert.equal(result.cost,117);assert.equal(calls.length,4);
 assert.equal(calls[0].url,'https://sync.assemblyai.com/v1/transcribe');assert.equal(calls[1].init.body,request.audio);assert.deepEqual(JSON.parse(calls[2].init.body).speech_models,['universal-3-5-pro']);
});
test('unknown Sync outcome never starts a second potentially billed job',async()=>{
 for(const status of [500,503]){let calls=0;const execute=providerClient({keys:{assemblyai:'fixture'},fetchImpl:async()=>{calls++;return new Response('',{status});}});await assert.rejects(execute(request));assert.equal(calls,1);}
});
test('a failed batch poll retains its receipt and is not treated as an unbilled rejection',async()=>{
 const responses=[new Response('',{status:404}),Response.json({upload_url:'https://cdn.assemblyai.com/fixture'}),Response.json({id:'batch-fixture',status:'queued'}),new Response('',{status:404})];
 const execute=providerClient({keys:{assemblyai:'fixture'},sleep:async()=>{},fetchImpl:async()=>responses.shift()});
 await assert.rejects(execute(request),e=>e.code==='provider_http'&&e.providerId==='batch-fixture');assert.equal(responses.length,0);
});
