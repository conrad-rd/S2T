import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';

const bundle = process.env.S2T_STREAMING_BUNDLE || '../build/cloudflare-bundle/worker.js';
const origin = 'https://credits.example.com';
const fixture = `
export class StreamingRetirementFixture extends CreditsLedger {
  async fetch(request) {
    if (new URL(request.url).pathname === '/api/fixture/seed') {
      const account = this.ledger.createSession().account;
      this.ledger.grant({account,cents:500,session:'fixture-'+account,intent:'fixture-'+account});
      return Response.json({key:this.ledger.issueKey(account).key});
    }
    if (new URL(request.url).pathname === '/api/fixture/historical') {
      const account = this.ledger.createSession().account;
      this.ledger.grant({account,cents:500,session:'legacy-'+account,intent:'legacy-'+account});
      const keyId = this.ledger.issueKey(account).id;
      const id = crypto.randomUUID();
      const r = this.ledger.reserve({account,keyId,dedup:id,fingerprint:id,provider:'assemblyai',model:'universal-3-5-pro',priceVersion:'legacy-streaming',maxCost:7500,streamingSeconds:60}).request;
      this.ledger.streaming.attach(r.id,'encrypted-historical-token',Date.now()+60000);
      this.ledger.streaming.abandon(account,keyId,r.id);
      const pending = this.ledger.streaming.get(r.id);
      const accepted = this.ledger.reconcile(r.id,{cost:500,providerId:'independent-receipt-'+id,evidence:'a'.repeat(64)});
      return Response.json({pendingState:pending.state,pendingCharged:pending.charged,accepted,charged:this.ledger.request(account,r.id).charged});
    }
    return super.fetch(request);
  }
}
`;
const directory = mkdtempSync(tmpdir() + '/s2t-stream-retired-cf-');
const mf = new Miniflare({ ...convertV4MiniflareOptions({
  name:'streaming-retirement-test', modules:true, script:readFileSync(bundle,'utf8') + '\n' + fixture,
  compatibilityDate:'2026-09-16', compatibilityFlags:['nodejs_compat'],
  durableObjects:{CREDITS:{className:'StreamingRetirementFixture',useSQLite:true}}, durableObjectsPersist:directory,
  bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:origin,S2T_RESULT_KEY:'a'.repeat(64),
    CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),
    STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'},
  outboundService:async()=>{throw Error('Unexpected outbound request');}
}), resourcePersistencePath:directory });
const read = async (response,status=200) => {const value=await response.json();assert.equal(response.status,status,JSON.stringify(value));return value;};
try {
  const {key} = await read(await mf.dispatchFetch(origin+'/api/fixture/seed'));
  const call = (path, data) => mf.dispatchFetch(origin+path,{method:data===undefined?'GET':'POST',
    headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','Idempotency-Key':'retired-check'},
    ...(data===undefined?{}:{body:JSON.stringify(data)})});
  const balance = await read(await call('/api/v1/balance'));
  assert.equal('assemblyStreaming' in balance,false);
  for (const path of ['/api/v1/streaming/sessions','/api/v1/streaming/cancel','/api/v1/streaming/sessions/missing/complete','/api/v1/streaming/sessions/missing/abandon'])
    assert.equal((await read(await call(path,{}),404)).code,'not_found');
  const historical = await read(await mf.dispatchFetch(origin+'/api/fixture/historical'));
  assert.deepEqual(historical,{pendingState:'uncertain',pendingCharged:null,accepted:true,charged:500});
  console.log('PASS: exact Worker retires direct streaming endpoints and retains historical token holds until independent reconciliation. Providers and payments mocked.');
} finally {await mf.dispose();}
