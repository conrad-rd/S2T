import test from 'node:test';
import assert from 'node:assert/strict';
import { workerConfiguration } from '../cloudflare/config.mjs';
import { requireFreshFundingReview } from '../config-core.mjs';
import { createLedger } from '../ledger-core.mjs';
import { DatabaseSync } from 'node:sqlite';
import { fixturePolicy } from '../policy.mjs';
const env = {
  S2T_BILLING_MODE: 'live', S2T_ENABLE_LIVE_SPENDING: 'explicitly-enabled',
  S2T_PUBLIC_ORIGIN: 'https://worker.example.com', S2T_BROWSER_ORIGIN: 'https://credits.example.com',
  S2T_OIDC_ISSUER: 'https://clerk.example.com', S2T_OIDC_AUDIENCE: 's2t-credits', S2T_OIDC_JWKS_URL: 'https://clerk.example.com/.well-known/jwks.json',
  CLERK_PUBLISHABLE_KEY: 'pk_live_' + Buffer.from('clerk.example.com$').toString('base64'),
  S2T_ALLOWED_EMAIL: 'owner@example.com', S2T_RESULT_KEY: 'a'.repeat(64),
  STRIPE_SECRET_KEY: 'rk_test_fixture', STRIPE_WEBHOOK_SECRET: 'whsec_test_fixture',
  STRIPE_LIVE_SECRET_KEY: 'rk_live_fixture', STRIPE_LIVE_WEBHOOK_SECRET: 'whsec_live_fixture',
  OPENROUTER_API_KEY: 'fixture', ASSEMBLYAI_API_KEY: 'fixture',
  S2T_PRICING_JSON: JSON.stringify({ version: 'production-fixture', expires: null, routes: { 'openrouter:cleanup': fixturePolicy.routes['openrouter:cleanup'], 'assemblyai:transcription': fixturePolicy.routes['assemblyai:transcription'] } }),
  S2T_PROVIDER_LIMITS_JSON: JSON.stringify({ reviewedAt: new Date().toISOString(), providers: { openrouter: { hardCapUsd: 5, autoRecharge: false, evidence: 'Fictional isolated provider limit for this test.' }, assemblyai: { funding: 'prepaid', autoRecharge: false, evidence: 'Fictional prepaid provider account for this test.' } } })
};
test('live mode selects isolated credentials, email access and funded routes without a daily shutdown', () => {
  const config = workerConfiguration(env);
  assert.equal(config.stripeKey, 'rk_live_fixture');
  assert.equal(config.webhookSecret, 'whsec_live_fixture');
  assert.equal(config.identity.allowedEmail, 'owner@example.com');
  assert.equal(config.browserOrigin, 'https://credits.example.com');
  assert.equal(config.realProviders, true);
  assert.deepEqual(Object.keys(config.keys).sort(), ['assemblyai', 'openrouter']);
  for (const overrides of [{STRIPE_LIVE_SECRET_KEY: undefined}, {STRIPE_LIVE_SECRET_KEY:'rk_test_wrong'}, {S2T_ALLOWED_EMAIL:''}, {ASSEMBLYAI_API_KEY:''}, {S2T_ENABLE_LIVE_SPENDING:''}]) assert.throws(() => workerConfiguration({...env,...overrides}));
  const stale = JSON.parse(env.S2T_PROVIDER_LIMITS_JSON);
  stale.reviewedAt = new Date(Date.now() - 2 * 86400000).toISOString();
  const staleConfig = workerConfiguration({...env,S2T_PROVIDER_LIMITS_JSON:JSON.stringify(stale)});
  assert.equal(staleConfig.realProviders, true);
  assert.throws(() => requireFreshFundingReview(staleConfig), {code:'funding_review_expired'});
  assert.throws(() => requireFreshFundingReview(config, config.fundingReviewedAt + 86400001), {code:'funding_review_expired'});
  assert.throws(() => workerConfiguration({...env,S2T_PROVIDER_LIMITS_JSON:JSON.stringify({...stale,reviewedAt:'not-a-date'})}), {code:'funding_review_invalid'});
});

test('cold restart with stale review keeps balance and replay available while new spending stops',()=>{
  const stale=JSON.parse(env.S2T_PROVIDER_LIMITS_JSON);
  stale.reviewedAt=new Date(Date.now()-2*86400000).toISOString();
  const config=workerConfiguration({...env,S2T_PROVIDER_LIMITS_JSON:JSON.stringify(stale)});
  const db=new DatabaseSync(':memory:');
  let clock=config.fundingReviewedAt+1000;
  const options={mode:'live',fundingReviewedAt:config.fundingReviewedAt,now:()=>clock};
  let ledger=createLedger(db,options);
  try {
    const account=ledger.createSession().account;
    ledger.grant({account,cents:500,session:'cs_stale_restart',intent:'pi_stale_restart'});
    const request=id=>({account,dedup:id,fingerprint:id,provider:'openrouter',model:'fixture',priceVersion:'v1',maxCost:100});
    const first=ledger.reserve(request('original-request')).request;
    clock=Date.now();
    ledger=createLedger(db,options);
    assert.equal(ledger.summary(account).balance,500);
    assert.equal(ledger.reserve(request('original-request')).request.id,first.id);
    assert.throws(()=>ledger.reserve(request('new-request')),{code:'funding_review_expired'});
  } finally {ledger.close();}
});
