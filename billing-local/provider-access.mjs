import { requireThat, Fault } from './money.mjs';
export async function checkProviderAccess(keys, fetcher = fetch) {
  const checks = [];
  if (keys.openrouter) checks.push((async () => {
    const response = await fetcher('https://openrouter.ai/api/v1/key', { headers: { Authorization: 'Bearer ' + keys.openrouter }, redirect: 'manual', signal: AbortSignal.timeout(10000) });
    requireThat(response.ok, 'provider_access', 'OpenRouter could not authenticate the hosted key.', 503);
    const reader = response.body.getReader();
    const chunks = [];
    let size = 0;
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 16384) { await reader.cancel(); throw Error('Provider metadata too large'); }
      chunks.push(value);
    }
    const data = JSON.parse(Buffer.concat(chunks).toString()).data;
    requireThat(data && !data.is_management_key && (data.limit === null ||
      (Number.isFinite(data.limit) && data.limit > 0 && Number.isFinite(data.limit_remaining) && data.limit_remaining > 0)),
      'provider_funding', 'OpenRouter needs an active S2T key with available provider credits before another purchase.', 503);
  })().catch(error => { if (error instanceof Fault) throw error; throw new Fault("provider_access", "OpenRouter access check failed: " + String(error.message).replaceAll(keys.openrouter, "[redacted]").slice(0, 220), 503); }));
  if (keys.assemblyai) checks.push((async () => {
    const response = await fetcher('https://api.assemblyai.com/v2/transcript?limit=1', { headers: { Authorization: keys.assemblyai }, redirect: 'manual', signal: AbortSignal.timeout(10000) });
    await response.body?.cancel();
    requireThat(response.ok, 'provider_access', 'AssemblyAI could not authenticate the hosted key.', 503);
  })().catch(error => { if (error instanceof Fault) throw error; throw new Fault("provider_access", "AssemblyAI access check failed: " + String(error.message).replaceAll(keys.assemblyai, "[redacted]").slice(0, 220), 503); }));
  if (keys.xai) checks.push((async () => {
    const response = await fetcher('https://api.x.ai/v1/models', { headers: { Authorization: 'Bearer ' + keys.xai }, redirect: 'manual', signal: AbortSignal.timeout(10000) });
    await response.body?.cancel();
    requireThat(response.ok, 'provider_access', 'xAI could not authenticate the hosted key.', 503);
  })().catch(() => { throw new Fault('provider_access', 'xAI could not authenticate the hosted key.', 503); }));
  await Promise.all(checks);
  return true;
}
