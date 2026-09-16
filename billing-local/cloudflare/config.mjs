import { configuration } from '../config-core.mjs';
import { requireThat } from '../money.mjs';
export function workerConfiguration(env) {
  const config = configuration({
    ...env,
    S2T_PRICING_FILE: env.S2T_PRICING_JSON ? 'pricing' : undefined,
    S2T_PROVIDER_LIMITS_FILE: env.S2T_PROVIDER_LIMITS_JSON ? 'limits' : undefined
  }, { readFile: name => name === 'pricing' ? env.S2T_PRICING_JSON : env.S2T_PROVIDER_LIMITS_JSON });
  requireThat(['test', 'live'].includes(config.mode) && config.clerk && config.identity, 'config', 'Hosted credits require customer sign-in.');
  requireThat(new URL(config.origin).protocol === 'https:' && new URL(config.origin).origin === config.origin, 'config', 'Hosted credits require an exact HTTPS origin.');
  requireThat(/^[a-f0-9]{64}$/.test(env.S2T_RESULT_KEY || ''), 'config', 'Configure the private result encryption key.');
  config.resultKey = Buffer.from(env.S2T_RESULT_KEY, 'hex');
  return config;
}
