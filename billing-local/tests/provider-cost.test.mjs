import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { dollarsToMicros } from '../money.mjs';
import { providerClient } from '../providers.mjs';
import { openLedger } from '../ledger.mjs';
import { createGateway } from '../gateway.mjs';
import { fixturePolicy } from '../policy.mjs';

test('provider costs accept exact decimal and scientific notation with conservative microdollar rounding', () => {
  for (const [value, expected] of [[0,0],[1e-7,1],['7.25e-7',1],['1.0000001e-6',2],['2.5E-4',250],['0.00004800000000001',49],[5e-324,1],['1e6',1e12],['0e400',0],['0.000250',250]]) {
    assert.equal(dollarsToMicros(value), expected, String(value));
  }
});
test('invalid provider costs still cannot become ledger charges', () => {
  for (const value of [undefined,null,true,{},[],NaN,Infinity,-1,'-0','01','1e','1e401','1e7','1000000.0000001','1'.repeat(129),' 1','0x10']) {
    assert.throws(() => dollarsToMicros(value), {code:'invalid_cost'}, String(value));
  }
});
test('malformed cost holds only its request; valid tiny costs settle once and other accounts remain usable', async () => {
  const ledger = openLedger(':memory:');
  let cost = 'bad', calls = 0;
  const execute = providerClient({keys:{openrouter:'fixture'},fetchImpl:async (_url, options) => {
    calls++;
    const request=JSON.parse(options.body);
    return Response.json({id:`receipt-${calls}`,model:request.model,usage:{cost},choices:[{finish_reason:'stop',message:{content:'Edited.'}}]});
  }});
  const gateway=createGateway({ledger,policy:fixturePolicy,encryptionKey:randomBytes(32),execute});
  const a=ledger.createSession().account, b=ledger.createSession().account;
  for(const account of [a,b])ledger.grant({account,cents:500,session:`cs-${account}`,intent:`pi-${account}`});
  const input=(account,key)=>({account,idempotencyKey:key,body:{provider:'openrouter',operation:'cleanup',text:'Example.'}});
  try {
    const failed=await gateway.run(input(a,'malformed-cost-request'));
    assert.equal(failed.state,'uncertain');
    assert.equal(ledger.health().paused,false);
    assert.ok(ledger.summary(a).reserved>0);
    assert.equal(ledger.summary(a).balance,500);
    const hold=ledger.summary(a).reserved;
    await gateway.run(input(a,'malformed-cost-request'));
    assert.equal(calls,1);
    cost=7.25e-7;
    const completed=await gateway.run(input(b,'valid-small-cost-request'));
    assert.equal(completed.state,'settled');
    assert.equal(completed.chargedCredits,0.0002);
    assert.equal(ledger.request(b,completed.id).cost,1);
    await gateway.run(input(b,'valid-small-cost-request'));
    assert.equal(calls,2);
    cost='0.00004800000000001';
    assert.equal((await gateway.run(input(a,'same-account-next-request'))).state,'settled');
    assert.equal(ledger.summary(a).reserved,hold);
    assert.equal(ledger.health().paused,false);
  } finally { ledger.close(); }
});
