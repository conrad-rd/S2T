import { configuration } from '../config-core.mjs';
import { requireThat } from '../money.mjs';
export function workerConfiguration(env) {
  const config = configuration({
    ...env,
    STRIPE_SECRET_KEY: env.S2T_BILLING_MODE === 'live' ? env.STRIPE_LIVE_SECRET_KEY : env.STRIPE_SECRET_KEY,
    STRIPE_WEBHOOK_SECRET: env.S2T_BILLING_MODE === 'live' ? env.STRIPE_LIVE_WEBHOOK_SECRET : env.STRIPE_WEBHOOK_SECRET,
    S2T_PRICING_FILE: env.S2T_PRICING_JSON ? 'pricing' : undefined,
    S2T_PROVIDER_LIMITS_FILE: env.S2T_PROVIDER_LIMITS_JSON ? 'limits' : undefined
  }, { readFile: name => name === 'pricing' ? env.S2T_PRICING_JSON : env.S2T_PROVIDER_LIMITS_JSON });
  requireThat(['test', 'live'].includes(config.mode) && config.clerk && config.identity, 'config', 'Hosted credits require customer sign-in.');
  requireThat(new URL(config.origin).protocol === 'https:' && new URL(config.origin).origin === config.origin, 'config', 'Hosted credits require an exact HTTPS origin.');
  requireThat(/^[a-f0-9]{64}$/.test(env.S2T_RESULT_KEY || ''), 'config', 'Configure the private result encryption key.');
  config.browserOrigin = env.S2T_BROWSER_ORIGIN || config.origin;
  requireThat(new URL(config.browserOrigin).protocol === 'https:' && new URL(config.browserOrigin).origin === config.browserOrigin, 'config', 'Use an exact HTTPS browser origin.');
  config.guestCheckout = env.S2T_GUEST_CHECKOUT === 'enabled';
  config.guestEmailRecovery = !!env.S2T_RECOVERY_EMAIL_KEY && !!env.S2T_RECOVERY_EMAIL_FROM;
  requireThat(!config.guestCheckout || !config.allowedAccounts, 'config', 'Guest purchases cannot bypass the real-provider staging allowlist.');
  config.resultKey = Buffer.from(env.S2T_RESULT_KEY, 'hex');
  if (env.S2T_GUEST_CREDENTIAL_KEY !== undefined) {
    requireThat(/^[a-f0-9]{64}$/.test(env.S2T_GUEST_CREDENTIAL_KEY) && env.S2T_GUEST_CREDENTIAL_KEY !== env.S2T_RESULT_KEY,
      'config', 'S2T_GUEST_CREDENTIAL_KEY must be a separate 32-byte secret.');
    config.guestCredentialKey = Buffer.from(env.S2T_GUEST_CREDENTIAL_KEY, 'hex');
  }
  return config;
}
