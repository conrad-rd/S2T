import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse } from 'miniflare';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import Stripe from 'stripe';
const origin = 'https://credits.example.com', issuer = 'https://accounts.example.com', secret = 'whsec_fixture';
const pair = await generateKeyPair('RS256');
const jwk = { ...await exportJWK(pair.publicKey), kid: 'fixture', alg: 'RS256', use: 'sig' };
const token = sub => new SignJWT({}).setProtectedHeader({alg:'RS256',kid:'fixture'}).setIssuer(issuer).setAudience('s2t-credits').setSubject(sub).setIssuedAt().setExpirationTime('1h').sign(pair.privateKey);
const owner = await token('user_owner'), other = await token('user_other');
let session, creates = 0;
const models = JSON.parse(JSON.parse(readFileSync('wrangler.jsonc', 'utf8')).vars.S2T_PRICING_JSON).routes['openrouter:cleanup'].alternatives;
const catalogFixture = `fixturePolicy.routes['openrouter:cleanup'].alternatives = ${JSON.stringify(models)};`;
const options = () => ({ ...convertV4MiniflareOptions({
  name:'credits-test', modules:true, script:readFileSync('../build/s2t-provider-worker.js','utf8') + '\n' + catalogFixture, compatibilityDate:'2026-09-16', compatibilityFlags:['nodejs_compat'],
  durableObjects:{CREDITS:{className:'CreditsLedger',useSQLite:true}}, durableObjectsPersist:directory,
  bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:origin,S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:secret},
  serviceBindings: {ASSETS: async () => new WorkerResponse(readFileSync('public/index.html'), {headers:{'Content-Type':'text/html'}})},
  outboundService: async request => {
    const url = new URL(request.url);
    if (url.origin === issuer && url.pathname === '/.well-known/jwks.json') return WorkerResponse.json({keys:[jwk]});
    assert.equal(url.origin,'https://api.stripe.com');
    if (url.pathname === '/v1/checkout/sessions' && request.method === 'POST') {
      creates++;
      const form = new URLSearchParams(await request.text());
      session = {id:'cs_test_fixture',url:'https://checkout.stripe.com/c/pay/cs_test_fixture',livemode:false,mode:'payment',currency:'usd',payment_status:'paid',amount_total:Number(form.get('line_items[0][price_data][unit_amount]')),client_reference_id:form.get('client_reference_id'),metadata:{s2t_order:form.get('metadata[s2t_order]')},total_details:{},payment_intent:{id:'pi_fixture',status:'succeeded',currency:'usd',livemode:false,amount_received:500}};
      return WorkerResponse.json(session);
    }
    assert.equal(url.pathname,'/v1/checkout/sessions/cs_test_fixture');
    return WorkerResponse.json(session);
  }
}), resourcePersistencePath: directory });
const directory = mkdtempSync(tmpdir()+'/s2t-cloudflare-');
let mf = new Miniflare(options());
const call = (path,{auth=owner,data,headers={},method=data === undefined ? 'GET':'POST'}={}) => mf.dispatchFetch(origin+path,{method,headers:{...(auth?{Authorization:'Bearer '+auth}:{}),Origin:origin,'Content-Type':'application/json',...headers},...(data===undefined?{}:{body:JSON.stringify(data)})});
const read = async (res,status=200) => { const data=await res.json();assert.equal(res.status,status,JSON.stringify(data));return data; };
try {
  const home = await call('/',{auth:null});
  assert.match(home.headers.get('Content-Type'), /text\/html/);
  const html = await home.text();
  assert.match(html, /id="sign-in"/);
  assert.doesNotMatch(html, /elevenlabs|scribe_v2/i);
  assert.match(html, /Settings → API keys/);
  await read(await call('/api/account',{auth:null}),401);
  await read(await call('/api/account',{auth:'invalid'}),401);
  const account = await read(await call('/api/account'));
  assert.equal(account.available,0);
  assert.equal(account.usage.series.length,30);
  assert.equal(account.usage.lastUsed,null);
  await read(await call('/api/account?days=12'),400);
  const pending = await read(await call('/api/device/start',{auth:null,data:{}}));
  await read(await call('/api/device/approve',{data:{userCode:pending.userCode},headers:{Origin:'https://evil.example'}}),403);
  await read(await call('/api/device/approve',{data:{userCode:pending.userCode}}));
  await read(await call('/api/device/approve',{auth:other,data:{userCode:pending.userCode}}),409);
  const {key} = await read(await call('/api/device/poll',{auth:null,data:{deviceCode:pending.deviceCode}}));
  await read(await call('/api/checkout',{data:{cents:500},headers:{'Idempotency-Key':'checkout-fixture-0001'}}));
  await read(await call('/api/checkout',{data:{cents:500},headers:{'Idempotency-Key':'checkout-fixture-0001'}}));
  assert.equal(creates,1);
  assert.equal((await read(await call('/api/account'))).available,0);
  const event={id:'evt_fixture',livemode:false,type:'checkout.session.completed',data:{object:{id:'cs_test_fixture'}}};
  const raw=JSON.stringify(event),signature=Stripe.webhooks.generateTestHeaderString({payload:raw,secret});
  await read(await call('/api/stripe/webhook',{auth:null,data:event,headers:{'stripe-signature':'invalid'}}),400);
  await read(await call('/api/stripe/webhook',{auth:null,data:event,headers:{'stripe-signature':signature}}));
  await read(await call('/api/stripe/webhook',{auth:null,data:event,headers:{'stripe-signature':signature}}));
  assert.equal((await read(await call('/api/account'))).available,500);
  const beforeConsent = await read(await call('/api/v1/balance',{auth:key}));
  assert.equal(beforeConsent.models.filter(m => m.operation === 'cleanup').length,3);
  assert.equal(beforeConsent.models.find(m => m.model === 'meta/muse-spark-1.3-contributor').requiresDataCollection,true);
  await read(await call('/api/v1/requests',{auth:key,data:{provider:'openrouter',operation:'cleanup',model:'meta/muse-spark-1.3-contributor',text:'Do not transmit without consent.'},headers:{'Idempotency-Key':'no-consent-fixture'}}),400);
  const afterConsent = await read(await call('/api/v1/balance',{auth:key}));
  assert.equal(afterConsent.requests.length,beforeConsent.requests.length);
  assert.equal(afterConsent.available,beforeConsent.available);
  assert.equal(afterConsent.reserved,0);
  const requests=await Promise.all(Array.from({length:8},()=>call('/api/v1/requests',{auth:key,data:{provider:'openrouter',operation:'cleanup',text:'Cloudflare fixture.',model:'meta/muse-spark-1.3-contributor',host:'',reasoning:'low',fast:'true',allowDataCollection:'true'},headers:{'Idempotency-Key':'request-fixture-00001','X-S2T-Device-Id':'a42fb61a-8053-4336-9482-b3e5f27ec7a1','X-S2T-Device-Name':'MacBook Pro'}})));
  assert.ok(requests.some(r => r.status === 200), JSON.stringify(await Promise.all(requests.map(async r => [r.status, await r.clone().text()]))));
  for (const response of requests.filter(r => r.status === 429)) assert.equal((await response.json()).code, 'busy');
  const results=await Promise.all(requests.filter(r => r.status !== 429).map(async r=>{assert.ok([200,202].includes(r.status),await r.clone().text());return r.json()}));
  assert.equal(new Set(results.map(r=>r.id)).size,1);
  assert.ok(results.every(r => r.model === 'meta/muse-spark-1.3-contributor'));
  const balance=await read(await call('/api/v1/balance',{auth:key}));
  assert.equal(balance.models.find(model => model.operation === 'cleanup').model, 'openai/gpt-oss-120b');
  assert.equal(balance.models.find(model => model.operation === 'cleanup').host, 'cerebras/fp16');
  assert.equal(balance.models.find(model => model.operation === 'transcription').maxSeconds, 120);
  assert.equal(balance.available,499.99);assert.equal(balance.reserved,0);
  const before=await read(await call('/api/account'));assert.equal(before.requests.length,1);
  assert.equal(before.usage.spentCredits,0.01);
  assert.equal(before.usage.lastUsed.device.name,'MacBook Pro');
  const isolated=await read(await call('/api/account?days=7',{auth:other}));
  assert.equal(isolated.usage.spentCredits,0);assert.equal(isolated.usage.lastUsed,null);
  await mf.dispose();mf=new Miniflare(options());
  assert.equal((await read(await call('/api/v1/balance',{auth:key}))).available,499.99);
  assert.equal((await read(await call('/api/account'))).usage.lastUsed.device.suffix,'C7A1');
  await read(await call('/api/keys/revoke',{data:{id:before.keys[0].id}}));
  await read(await call('/api/v1/balance',{auth:key}),401);
  console.log('PASS: scoped deployment artifact, three configured models, pre-reservation Contributor opt-in, Cloudflare runtime, durable SQL persistence, JWT validation, browser pairing, CSRF, checkout replay, signed payment deduplication, concurrent reservation, exact balance, revocation. All external calls mocked.');
} finally { await mf.dispose(); }
