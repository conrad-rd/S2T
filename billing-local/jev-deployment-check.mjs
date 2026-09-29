import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
const metadata=JSON.parse(readFileSync('../build/jev-credits/upload-metadata.json','utf8'));
const pricing=JSON.parse(metadata.bindings.find(b=>b.name==='S2T_PRICING_JSON').text);
const source=readFileSync('tests/jev.test.mjs','utf8');
const start=source.indexOf(' const ledger=openLedger');
const end=source.indexOf("test('invalid Jev",start);
const code=source.slice(start,end).replace(" const ledger=openLedger(':memory:');",' const ledger=this.ledger;').replace(' finally {ledger.close();}',' finally {}').replace(/\n\}\);\s*$/,'');
const fixture=`\nimport assert from 'node:assert/strict';\nexport class JevFixture extends CreditsLedger { async verifyJev(policy) {const jevPrice=policy.routes['openrouter:decisions']; const decision={model:jevPrice.model,state:{transcript:'Uh, hello.'},questions:{edit0:{type:'noul',instructions:'Is this an accidental hesitation?'}}};const body={provider:'openrouter',operation:'decisions',model:jevPrice.model,text:JSON.stringify(decision)};${code}\nreturn true;}}`;
const mf=new Miniflare(convertV4MiniflareOptions({name:'jev-check',modules:true,script:readFileSync('../build/jev-credits/worker.js','utf8')+fixture,compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],durableObjects:{CREDITS:{className:'JevFixture',useSQLite:true}},bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:'https://credits.example.com',S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'}}));
try {const ns=await mf.getDurableObjectNamespace('CREDITS');assert.equal(await ns.get(ns.idFromName('jev')).verifyJev(pricing),true);console.log('PASS exact Worker: Jev pricing, credentials, ledger settlement, replay and account isolation. No real inference or payments.');} finally {await mf.dispose();}
