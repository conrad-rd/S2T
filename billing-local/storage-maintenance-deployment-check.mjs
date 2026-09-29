import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';

const tests=readFileSync('tests/streaming-maintenance.test.mjs','utf8').replace(/^import .*;\n/gm,'');
const fixture=`
import assert from 'node:assert/strict';
let maintenanceStorage;
class DatabaseSync { constructor() {return durableDatabase(maintenanceStorage);} }
const maintenanceTests=[];
const test=(name,run)=>maintenanceTests.push({name,run});
${tests}
export class MaintenanceFixture extends CreditsLedger {
  async fetch(request) {
    const path=new URL(request.url).pathname;
    if(path==='/fixture/list')return Response.json(maintenanceTests.map(t=>t.name));
    if(path.startsWith('/fixture/test/')) {
      maintenanceStorage=this.ctx.storage;
      const t=maintenanceTests[Number(path.split('/').pop())];
      try {await t.run();return Response.json({name:t.name});}
      catch(error){return Response.json({error:String(error)},{status:500});}
    }
    if(path==='/fixture/health') {
      const sql=this.ctx.storage.sql, writes=()=>sql.exec('SELECT total_changes() AS n').one().n;
      const before=writes(),healthRequest=new Request(this.config.origin+'/health');
      const healthy=await super.fetch(healthRequest),body=await healthy.json();
      const after=writes();
      sql.exec("UPDATE metadata SET value='1' WHERE key='paused'");
      const paused=await super.fetch(healthRequest),pausedBody=await paused.json();
      return Response.json({healthy:healthy.status,body,paused:paused.status,pausedBody,writes:after-before});
    }
    return super.fetch(request);
  }
}
const maintenanceDefault={async fetch(request,env) {
  const path=new URL(request.url).pathname;
  if(path==='/fixture/quota'||path==='/fixture/outage') {
    const message=path.endsWith('quota')?'Exceeded allowed rows written in Durable Objects free tier.':'private fixture detail';
    const CREDITS={idFromName:()=> 'fixture',get:()=>({fetch:async()=>{throw Error(message);}})};
    return worker_default.fetch(new Request(env.S2T_PUBLIC_ORIGIN+'/health'),{...env,CREDITS});
  }
  return worker_default.fetch(request,env);
}};
`;
const artifact=process.env.S2T_DEPLOYMENT_ARTIFACT;
assert.ok(artifact,'Set S2T_DEPLOYMENT_ARTIFACT to the exact Worker upload.');
const script=readFileSync(artifact,'utf8').replace('worker_default as default','maintenanceDefault as default')+fixture;
const origin='https://credits.example.com';
const mf=new Miniflare(convertV4MiniflareOptions({name:'storage-maintenance-test',modules:true,script,compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],durableObjects:{CREDITS:{className:'MaintenanceFixture',useSQLite:true}},bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:origin,S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'}}));
let failures=0;
async function check(name,run){try{await run();console.log('PASS',name);}catch(error){failures++;console.error('FAIL',name,String(error));}}
try {
  const ns=await mf.getDurableObjectNamespace('CREDITS');
  const stub=name=>ns.get(ns.idFromName(name));
  const names=await (await stub('list').fetch(origin+'/fixture/list')).json();
  for(let index=0;index<names.length;index++)await check(names[index],async()=>{
    const response=await stub('test-'+index).fetch(origin+'/fixture/test/'+index);
    assert.equal(response.status,200,JSON.stringify(await response.json()));
  });
  await check('health reaches SQLite without rate-counter writes and reports spending pause',async()=>{
    const response=await stub('health').fetch(origin+'/fixture/health'),result=await response.json();
    assert.equal(response.status,200,JSON.stringify(result));
    assert.equal(result.healthy,200,JSON.stringify(result));assert.equal(result.body.status,'ok');
    assert.equal(result.writes,0);assert.equal(result.paused,503);assert.equal(result.pausedBody.status,'paused');
    assert.deepEqual(Object.keys(result.body).sort(),['mode','status','storage']);
  });
  await check('public health propagates database quota failures safely',async()=>{
    const response=await mf.dispatchFetch(origin+'/fixture/quota');
    assert.equal(response.status,503);assert.equal((await response.json()).code,'storage_quota');
    assert.equal(response.headers.get('cache-control'),'no-store');
  });
  await check('public health propagates other database failures without exposing details',async()=>{
    const response=await mf.dispatchFetch(origin+'/fixture/outage');
    assert.equal(response.status,503);assert.ok(!(await response.text()).includes('private fixture detail'));
  });
  await check('healthy public endpoint still routes successfully',async()=>{
    const response=await mf.dispatchFetch(origin+'/health');
    assert.equal(response.status,200);assert.equal((await response.json()).status,'ok');
  });
}finally{await mf.dispose();}
assert.equal(failures,0,failures+' storage regression checks failed');
