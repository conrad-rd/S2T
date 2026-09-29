import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { openLedger } from '../ledger.mjs';

function fixture() {
  let time = Date.UTC(2026, 8, 27);
  const ledger = openLedger(':memory:', {mode:'test', now:()=>time});
  const account = ledger.createSession().account;
  ledger.grant({account,cents:500,session:'historical-streaming',intent:'historical-streaming'});
  const keyId = ledger.issueKey(account).id;
  const reserve = (dedup=randomUUID()) => ledger.reserve({account,keyId,dedup,fingerprint:dedup,provider:'assemblyai',model:'universal-3-5-pro',priceVersion:'legacy-streaming',maxCost:60*125,feeBps:0,streamingSeconds:60}).request;
  return {ledger,account,keyId,reserve,advance:ms=>time+=ms,now:()=>time};
}

test('an issued legacy token cannot be released by client cancellation or client-reported duration', () => {
  const f=fixture();
  try {
    const r=f.reserve();
    f.ledger.streaming.attach(r.id,'encrypted-legacy-token',f.now()+60_000);
    assert.deepEqual(f.ledger.streaming.abandon(f.account,f.keyId,r.id),{abandoned:true});
    assert.equal(f.ledger.streaming.get(r.id).state,'uncertain');
    assert.equal(f.ledger.streaming.get(r.id).token_cipher,null);
    assert.ok(f.ledger.summary(f.account).reserved>0);
    assert.throws(()=>f.ledger.streaming.complete(f.account,f.keyId,r.id,{sessionDurationSeconds:'0'}),{code:'streaming_retired'});
    assert.equal(f.ledger.request(f.account,r.id).charged,null);
    assert.equal(f.ledger.reconcile(r.id,{cost:500,providerId:'independent-provider-receipt',evidence:'a'.repeat(64)}),true);
    assert.equal(f.ledger.request(f.account,r.id).charged,500);
  } finally {f.ledger.close();}
});

test('unknown cancellation does not create unbounded tombstones', () => {
  const f=fixture();
  try {
    for(let i=0;i<100;i++) assert.deepEqual(f.ledger.streaming.cancelAuthorization(f.account,f.keyId,`unknown-${i}`),{abandoned:false});
    assert.equal(f.ledger.streaming.checkAuthorization(f.account,f.keyId,'unknown-1'),undefined);
    const r=f.reserve('known');
    assert.deepEqual(f.ledger.streaming.cancelAuthorization(f.account,f.keyId,'known'),{abandoned:true});
    assert.equal(f.ledger.streaming.get(r.id).state,'released');
    assert.throws(()=>f.ledger.streaming.checkAuthorization(f.account,f.keyId,'known'),{code:'streaming_cancelled'});
  } finally {f.ledger.close();}
});

test('independent evidence corrects historical zero-settled token usage without retrocharging the customer', () => {
  const f=fixture();
  try {
    const r=f.reserve();
    f.ledger.streaming.attach(r.id,'encrypted-legacy-token',f.now()+60_000);
    f.ledger.settle(r.id,{cost:0,providerId:`streaming-client:${r.id}`});
    const before=f.ledger.summary(f.account).available;
    assert.equal(f.ledger.reconcile(r.id,{cost:1250,providerId:'independent-provider-receipt',evidence:'b'.repeat(64)}),true);
    const corrected=f.ledger.request(f.account,r.id);
    assert.equal(corrected.cost,1250);
    assert.equal(corrected.charged,0);
    assert.equal(corrected.provider_id,'independent-provider-receipt');
    assert.equal(corrected.reconciled,1);
    assert.equal(f.ledger.summary(f.account).available,before);
  } finally {f.ledger.close();}
});

test('independent evidence refunds an overcharged historical client report without adding a second request',()=>{
  const f=fixture();
  try {
    const r=f.reserve();
    f.ledger.streaming.attach(r.id,'encrypted-legacy-token',f.now()+60_000);
    f.ledger.settle(r.id,{cost:1250,providerId:`streaming-client:${r.id}`});
    const before=f.ledger.summary(f.account).balance;
    assert.equal(f.ledger.reconcile(r.id,{cost:500,providerId:'independent-lower-cost',evidence:'c'.repeat(64)}),true);
    assert.equal(f.ledger.request(f.account,r.id).charged,500);
    assert.equal(Math.round((f.ledger.summary(f.account).balance-before)*100),15);
    assert.equal(f.ledger.usage(f.account,30).requestCount,1);
    assert.equal(f.ledger.usage(f.account,30).spentCredits,0.1);
    assert.equal(f.ledger.usage(f.account,30).providers[0].credits,0.1);
    assert.equal(f.ledger.reconcile(r.id,{cost:500,providerId:'independent-lower-cost',evidence:'c'.repeat(64)}),true);
    assert.equal(Math.round((f.ledger.summary(f.account).balance-before)*100),15);
  } finally {f.ledger.close();}
});
