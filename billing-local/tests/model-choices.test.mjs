import test from 'node:test';
import assert from 'node:assert/strict';
import { fixturePolicy, prepareRequest, modelCatalog } from '../policy.mjs';
import { providerClient } from '../providers.mjs';
const policy = structuredClone(fixturePolicy);
policy.routes['openrouter:cleanup'].alternatives = [{
  ...fixturePolicy.routes['openrouter:cleanup'], model: 'openai/gpt-oss-20b', host: undefined, title: 'GPT-OSS 20B'
}];
const body = {provider:'openrouter', operation:'cleanup', model:'openai/gpt-oss-20b', host:'', text:'Synthetic dictation', reasoning:'low', fast:'true'};
test('catalog and dispatch agree on each configured model and host', () => {
  assert.equal(modelCatalog(policy).length, 3);
  for (const model of modelCatalog(policy).filter(m => m.operation === 'cleanup')) {
    const request = prepareRequest({...body, model:model.model, host:model.host}, policy);
    assert.equal(request.model, model.model);
    assert.equal(request.price.host || '', model.host);
  }
  for (const overrides of [{model:'unknown/model'}, {host:'unapproved'}, {reasoning:'invented'}, {fast:'yes'}, {provider:'unknown'}]) {
    assert.throws(() => prepareRequest({...body, ...overrides}, policy));
  }
});
test('model, host, reasoning and speed participate in retry identity', () => {
  const variants = [body, {...body,reasoning:'high'}, {...body,fast:'false'}, {...body,model:'openai/gpt-oss-120b',host:'cerebras/fp16'}];
  assert.equal(new Set(variants.map(b => prepareRequest(b, policy).fingerprint)).size, variants.length);
});
test('selected model and options reach OpenRouter with privacy and pricing bounds', async () => {
  let posted;
  const execute = providerClient({keys:{openrouter:'synthetic'}, fetchImpl:async (_, init) => {
    posted = JSON.parse(init.body);
    return new Response(JSON.stringify({id:'fixture',model:body.model,provider:'Fixture',usage:{cost:0.00001},choices:[{finish_reason:'stop',message:{content:'Synthetic result'}}]}));
  }});
  await execute(prepareRequest(body, policy));
  assert.equal(posted.model, body.model);
  assert.deepEqual(posted.reasoning, {effort:'low'});
  assert.equal(posted.provider.sort, 'throughput');
  assert.equal(posted.provider.data_collection, 'deny');
  assert.equal(posted.provider.only, undefined);
  assert.equal(posted.max_tokens, 512);
  assert.ok(posted.provider.max_price);
});
test('legacy requests retain their retry identity after adding model choices', async () => {
  const {createHash} = await import('node:crypto');
  const legacy = {provider:'openrouter',operation:'cleanup',text:'Legacy dictation'};
  const previous = createHash('sha256').update(JSON.stringify(['openrouter','cleanup','openai/gpt-oss-120b','Legacy dictation',null])).digest('hex');
  assert.equal(prepareRequest(legacy, policy).fingerprint, previous);
});
test('Contributor requires request-level opt-in and never enables data use on other models', async () => {
  const contributorPolicy = structuredClone(policy);
  contributorPolicy.routes['openrouter:cleanup'].alternatives.push({...policy.routes['openrouter:cleanup'].alternatives[0],model:'meta/muse-spark-1.3-contributor',title:'Muse Spark Contributor',requiresDataCollection:true});
  const contributor = {...body,model:'meta/muse-spark-1.3-contributor'};
  assert.throws(() => prepareRequest(contributor,contributorPolicy), /opt-in/);
  assert.throws(() => prepareRequest({...contributor,allowDataCollection:'false'},contributorPolicy), /opt-in/);
  assert.throws(() => prepareRequest({...body,allowDataCollection:'true'},contributorPolicy), /only to Contributor/);
  const prepared = prepareRequest({...contributor,allowDataCollection:'true'},contributorPolicy);
  assert.equal(prepared.allowDataCollection,true);
  let posted;
  await providerClient({keys:{openrouter:'fixture'},fetchImpl:async (_,init) => {
    posted=JSON.parse(init.body);
    return new Response(JSON.stringify({id:'receipt',model:contributor.model,usage:{cost:0.00001},choices:[{finish_reason:'stop',message:{content:'Result'}}]}));
  }})(prepared);
  assert.equal(posted.provider.data_collection,'allow');
  assert.equal(modelCatalog(contributorPolicy).find(m => m.model === contributor.model).requiresDataCollection,true);
});
