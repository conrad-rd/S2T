import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { configuration } from '../config.mjs';
import { fixturePolicy } from '../policy.mjs';
import { hash } from '../ledger.mjs';

test('real-provider sandbox requires reviewed caps and a tester allowlist', () => {
  const dir = mkdtempSync(tmpdir() + '/s2t-staging-config-');
  writeFileSync(dir + '/pricing.json', JSON.stringify({ ...fixturePolicy, version: "staging-fixture", expires: new Date(Date.now() + 3600000).toISOString() }));
  writeFileSync(dir + '/limits.json', JSON.stringify({ reviewedAt: new Date().toISOString(), providers: Object.fromEntries(['openrouter', 'assemblyai'].map(provider => [provider, { autoRecharge: false, overdraftDisabled: true, hardCapUsd: 5, evidence: 'Isolated test fixture, never an operator attestation.' }])) }));
  const env = {
    S2T_BILLING_MODE: 'test', S2T_STAGING_REAL_PROVIDERS: 'explicitly-enabled',
    S2T_PUBLIC_ORIGIN: 'https://credits.example.com', S2T_OIDC_ISSUER: 'https://accounts.example.com',
    S2T_OIDC_AUDIENCE: 's2t-credits', S2T_OIDC_JWKS_URL: 'https://accounts.example.com/.well-known/jwks.json',
    STRIPE_SECRET_KEY: 'rk_test_fixture', STRIPE_WEBHOOK_SECRET: 'whsec_fixture',
    CLERK_PUBLISHABLE_KEY: 'pk_test_' + Buffer.from('accounts.example.com$').toString('base64'),
    S2T_PRICING_FILE: dir + '/pricing.json', S2T_PROVIDER_LIMITS_FILE: dir + '/limits.json',
    S2T_RESULT_KEY: 'a'.repeat(64), OPENROUTER_API_KEY: 'fixture', ASSEMBLYAI_API_KEY: 'fixture'
  };
  assert.throws(() => configuration(env), /allowlist/);
  env.S2T_STAGING_USERS = 'user_fixture';
  const config = configuration(env);
  assert.equal(config.realProviders, true);
  assert.deepEqual(config.allowedAccounts, [hash('https://accounts.example.com:user_fixture')]);
  assert.throws(() => configuration({ ...env, STRIPE_SECRET_KEY: 'rk_live_fixture' }), /match/);
  assert.throws(() => configuration({ ...env, S2T_BILLING_MODE: 'demo' }), /Demo mode/);
  assert.throws(() => configuration({ ...env, ASSEMBLYAI_API_KEY: '' }), /dedicated capped/);
});

test('Render cannot start anonymous demo accounts or use an ephemeral ledger path', () => {
  assert.throws(() => configuration({ RENDER: 'true' }), /customer sign-in/);
  const env = { RENDER: 'true', S2T_BILLING_MODE: 'test', S2T_PUBLIC_ORIGIN: 'https://credits.example.com', CLERK_PUBLISHABLE_KEY: 'pk_test_' + Buffer.from('accounts.example.com$').toString('base64') };
  assert.throws(() => configuration(env), /persistent/);
  assert.equal(configuration({ ...env, S2T_BILLING_DATA_DIR: '/var/data/s2t' }).realProviders, false);
});
