import test from 'node:test';
import assert from 'node:assert/strict';
import { checkProviderAccess } from '../provider-access.mjs';
test('checkout readiness authenticates both providers without submitting inference or exposing transcript data', async () => {
  const destinations = [];
  const keys = {openrouter:'or_fixture',assemblyai:'aa_fixture'};
  const fetcher = async (url, options) => {
    destinations.push(url);
    assert.equal(options.redirect, 'manual');
    assert.equal(options.body, undefined);
    if (url.includes('openrouter')) {
      assert.equal(options.headers.Authorization,'Bearer or_fixture');
      return Response.json({data:{limit:5,limit_remaining:5,limit_reset:null,is_management_key:false}});
    }
    assert.equal(options.headers.Authorization,'aa_fixture');
    return Response.json({transcripts:[{text:'Never returned from the check'}]});
  };
  assert.equal(await checkProviderAccess(keys, fetcher),true);
  assert.equal(destinations.length,2);
  for (const data of [{limit:0,limit_remaining:0},{limit:5,limit_remaining:0}]) await assert.rejects(checkProviderAccess({openrouter:'fixture'},async()=>Response.json({data})),/available provider credits/);
  await assert.rejects(checkProviderAccess({assemblyai:'fixture'},async()=>new Response('',{status:401})),/AssemblyAI/);
});

test('uncapped and user-configured provider keys are accepted',async()=>{
 for(const data of [{limit:null,limit_remaining:null},{limit:100,limit_remaining:100},{limit:5,limit_remaining:5,limit_reset:'daily'}]) assert.equal(await checkProviderAccess({openrouter:'fixture'},async()=>Response.json({data})),true);
});
