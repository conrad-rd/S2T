import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Miniflare, convertV4MiniflareOptions} from 'miniflare';
const regression=readFileSync('tests/provider-cost.test.mjs','utf8');
const body=regression.slice(regression.indexOf('  const ledger = openLedger',regression.indexOf("test('malformed")),regression.lastIndexOf('\n});'))
  .replace("const ledger = openLedger(':memory:');",'const ledger = this.ledger;')
  .replace('ledger.close();','');
const fixture=`\nimport assert from 'node:assert/strict';\nexport class CostFixture extends CreditsLedger { async verifyCosts() {${body}\nreturn {paused:this.ledger.health().paused, pending:this.ledger.health().pending.length};} }`;
const mf=new Miniflare(convertV4MiniflareOptions({name:'cost-test',modules:true,
  script:readFileSync('../build/cost-pause-repair/worker.js','utf8')+fixture,
  compatibilityDate:'2026-09-16',compatibilityFlags:['nodejs_compat'],
  durableObjects:{CREDITS:{className:'CostFixture',useSQLite:true}},
  bindings:{S2T_BILLING_MODE:'test',S2T_PUBLIC_ORIGIN:'https://credits.example.com',S2T_RESULT_KEY:'a'.repeat(64),CLERK_PUBLISHABLE_KEY:'pk_test_'+Buffer.from('accounts.example.com$').toString('base64'),STRIPE_SECRET_KEY:'rk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'},
}));
try {
 const ns=await mf.getDurableObjectNamespace('CREDITS');
 const result=await ns.get(ns.idFromName('cost-regression')).verifyCosts();
 assert.equal(result.paused,false);
 assert.equal(result.pending,1);
 console.log('PASS exact Worker: malformed cost is isolated, tiny/scientific costs settle exactly once, unrelated and subsequent requests work. No external calls.');
} finally {await mf.dispose();}
