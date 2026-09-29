import {modelCatalog} from './policy.mjs';
import {requireThat} from './money.mjs';

const catalogModelID = value => typeof value === 'string' && value.length <= 200 && /^[A-Za-z0-9_~.-]+\/[A-Za-z0-9_~.:-]+$/.test(value);
const catalogRate = value => {
  const number = typeof value === 'string' || typeof value === 'number' ? Number(value) : NaN;
  requireThat(Number.isFinite(number) && number >= 0 && number <= 1, 'model_price', 'This model has no usable published price.');
  return Math.max(1, Math.ceil(number * 1e6 * 1.25));
};

export function createOpenRouterCatalog({policy, enabled = false, fetchImpl = fetch, now = Date.now}) {
  const cache = new Map();
  async function read(path) {
    const previous = cache.get(path);
    if (previous && previous.expires > now()) return previous.value;
    const value = (async () => {
      const response = await fetchImpl('https://openrouter.ai/api/v1/' + path, {signal:AbortSignal.timeout(10000),redirect:'error'});
      requireThat(response.ok, 'model_catalog', 'OpenRouter model choices are temporarily unavailable. Retry shortly.', 503);
      let size = 0; const chunks = [];
      for await (const chunk of response.body) {
        size += chunk.length;
        requireThat(size <= 8_000_000, 'model_catalog', 'OpenRouter catalog is too large.', 503);
        chunks.push(chunk);
      }
      return JSON.parse(Buffer.concat(chunks).toString()).data;
    })();
    if (cache.size >= 128) cache.delete(cache.keys().next().value);
    cache.set(path, {value,expires:now()+300000});
    try { return await value; }
    catch (error) { cache.set(path,{value,expires:now()+15000}); throw error; }
  }
  async function entries() {
    const entries = await read('models?output_modalities=all');
    requireThat(Array.isArray(entries) && entries.length <= 10000, 'model_catalog', 'Invalid OpenRouter catalog.', 503);
    return entries.filter(model => catalogModelID(model.id));
  }
  function operations(model) {
    const input=model.architecture?.input_modalities || [], output=model.architecture?.output_modalities || [];
    const tasks=[];
    if (input.includes('text') && output.includes('text')) tasks.push('cleanup');
    if (input.includes('audio') && output.includes('transcription')) tasks.push('transcription');
    return tasks;
  }
  function priced(model) { try { catalogRate(model.pricing?.prompt); catalogRate(model.pricing?.completion); return true; } catch { return false; } }
  function base(operation) { return policy.routes['openrouter:'+operation]; }
  return {
    async models() {
      const configured=modelCatalog(policy);
      if (!enabled) return configured;
      try {
        const known=new Set(configured.map(m=>`${m.operation}:${m.model}:${m.host}`));
        for (const model of await entries()) for (const task of operations(model)) {
          // The catalog does not provide an enforceable maximum audio charge.
          // Speech remains limited to explicitly reviewed policy routes.
          if (task === 'transcription') continue;
          if (!base(task) || !priced(model) || known.has(`${task}:${model.id}:`)) continue;
          configured.push({provider:'openrouter',operation:task,model:model.id,host:'',title:model.name || model.id,
            requiresDataCollection:model.id==='meta/muse-spark-1.3-contributor', ...(task==='transcription'?{maxSeconds:base(task).maxSeconds}:{})});
        }
      } catch { /* Configured routes remain available when public metadata is down. */ }
      return configured;
    },
    async policyFor(body) {
      if (!enabled || body?.provider !== 'openrouter' || body.operation !== 'cleanup') return policy;
      const route=base(body.operation);
      if (!route) return policy;
      if ([route,...(route.alternatives || [])].some(p=>(!body.model || p.model===body.model)&&(body.host===undefined || body.host===(p.host || '')))) return policy;
      requireThat(catalogModelID(body.model), 'model', 'Choose an OpenRouter model ID.');
      let model, pricing;
      if (body.host) {
        requireThat(body.operation==='cleanup' && typeof body.host==='string' && /^[A-Za-z0-9._/-]{1,100}$/.test(body.host), 'host', 'Invalid hosting provider.');
        const data=await read('models/'+body.model.split('/').map(encodeURIComponent).join('/')+'/endpoints');
        requireThat(data?.id===body.model && operations(data).includes(body.operation), 'model', 'This model is not listed for the selected task by OpenRouter. Reload model choices.');
        const endpoint=data?.endpoints?.find(e=>e.tag===body.host && (e.status===undefined || e.status===0));
        requireThat(endpoint, 'host', 'This host is not available for the selected model. Choose Automatic or reload providers.');
        model=data;
        pricing=endpoint.pricing;
      } else {
        model=(await entries()).find(m=>m.id===body.model && operations(m).includes(body.operation));
        requireThat(model, 'model', 'This model is not listed for the selected task by OpenRouter. Reload model choices.');
        pricing=model.pricing;
      }
      requireThat(priced({pricing}), 'model_price', 'This model has no usable published price.');
      const {alternatives,host,...defaults}=route;
      const selected={...defaults,model:model.id,title:model.name || model.id,catalogPriced:true};
      selected.inputMicrosPerToken=catalogRate(pricing.prompt);
      selected.outputMicrosPerToken=catalogRate(pricing.completion);
      selected.requestMicros=pricing.request===undefined ? 0 : catalogRate(pricing.request);
      selected.maxOutputTokens=8192;
      selected.maxRequestMicros=250000;
      selected.responseModels=[...new Set([model.id,model.canonical_slug,model.id.split(':')[0]].filter(value=>catalogModelID(value)))];
      if (body.host) selected.host=body.host;
      if (model.id==='meta/muse-spark-1.3-contributor') selected.requiresDataCollection=true;
      else delete selected.requiresDataCollection;
      return {...policy,routes:{...policy.routes,['openrouter:'+body.operation]:{...route,alternatives:[...(alternatives || []),selected]}}};
    }
  };
}
