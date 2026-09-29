import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync } from 'node:fs';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse } from 'miniflare';
const origin='https://credits.example.com';
const fixture=`
export class VolumeFixtureLedger extends CreditsLedger {
  async fetch(request) {
    if(new URL(request.url).pathname!='/api/fixture-volume')return super.fetch(request);
    const account=this.ledger.createSession().account;
    const results=[];
    for(const cents of [500,1000,2000,5000,10000,2001]) {
      const id='volume-fixture-'+cents;
      const order=this.ledger.checkoutOrder(account,cents,id);
      this.ledger.attachCheckout(order.id,'cs_'+id);
      this.ledger.grant({account,cents,session:'cs_'+id,intent:'pi_'+id});
      const balance=this.ledger.summary(account).balance;
      this.ledger.reverse({id:'re1_'+id,intent:'pi_'+id,cents:1,kind:'refund'});
      const partial=this.ledger.summary(account).balance;
      const funded=this.ledger.funding().providerMicros;
      this.ledger.reverse({id:'re2_'+id,intent:'pi_'+id,cents:cents-1,kind:'refund'});
      results.push({cents,grant:order.grant_micros,balance,partial,funded,after:this.ledger.summary(account).balance});
    }
    return Response.json(results);
  }
}`;
const directory=mkdtempSync('/private/tmp/s2t-volume-runtime-');
const options=()=>({...convertV4MiniflareOptions({name:'volume-test',modules:true,
 script:readFileSync(process.env.S2T_DEPLOYMENT_ARTIFACT,'utf8')+'\n'+fixture,
 compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],
 durableObjects:{CREDITS:{className:'VolumeFixtureLedger',useSQLite:true}},durableObjectsPersist:directory,
 bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:origin,S2T_RESULT_KEY:'a'.repeat(64),S2T_OPERATOR_KEY:'b'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'},
 outboundService:async request=>{throw Error('Unexpected external request '+new URL(request.url).origin)},
 serviceBindings:{ASSETS:async()=>new WorkerResponse('fixture')},
}),resourcePersistencePath:directory});
let mf=new Miniflare(options());
const call=(path,data,headers={})=>mf.dispatchFetch(origin+path,{method:data?'POST':'GET',headers:{Origin:origin,'Content-Type':'application/json',...headers},...(data?{body:JSON.stringify(data)}:{})});
try {
 const results=await (await call('/api/fixture-volume')).json();
 const expected=[2500000,5500000,11500000,29000000,59000000,11505833];
 for(const [i,row] of results.entries()) {
  assert.equal(row.grant,expected[i]);assert.equal(row.balance,expected[i]/5000);
  assert.equal(row.partial,(expected[i]-Math.floor(expected[i]/row.cents))/5000);
  assert.equal(row.funded,expected[i]-Math.floor(expected[i]/row.cents));assert.equal(row.after,0);
 }
 const declaration={id:'44444444-4444-4444-8444-444444444444',name:'Runtime Buyer',email:'runtime@example.com',contract:'Fixture payment',delivery:'download',confirmed:true};
 assert.equal((await call('/api/withdrawals',declaration,{Origin:'https://evil.example'})).status,403);
 const response=await call('/api/withdrawals',declaration);assert.equal(response.status,200,await response.clone().text());
 const receipt=await response.json();assert.match(receipt.receipt,/Runtime Buyer/);
 assert.equal((await call('/api/operator',{action:'withdrawals'})).status,401);
 assert.equal((await call('/api/account')).status,401);
 await mf.dispose();mf=new Miniflare(options());
 assert.deepEqual(await (await call('/api/withdrawals',declaration)).json(),receipt);
 const inbox=await (await call('/api/operator',{action:'withdrawals'},{Authorization:'Bearer '+'b'.repeat(64)})).json();
 assert.equal(inbox.submissions.length,1);assert.equal(inbox.submissions[0].receipt,receipt.receipt);
 console.log('PASS exact Worker: all tiers, custom amount, partial/full refund accounting, anonymous withdrawal, origin check, operator-only inbox and restart-safe receipt. No external calls.');
} finally {await mf.dispose();}
