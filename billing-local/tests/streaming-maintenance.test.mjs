import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';

function fixture() {
  const db=new DatabaseSync(':memory:');
  let time=Date.UTC(2026,8,27);
  const ledger=createLedger(db,{mode:'test',now:()=>time});
  const account=ledger.createSession().account;
  ledger.grant({account,cents:500,session:'maintenance-fixture',intent:'maintenance-fixture'});
  const keyId=ledger.issueKey(account).id;
  const reserve=dedup=>ledger.reserve({account,keyId,dedup,fingerprint:dedup,provider:'assemblyai',model:'universal-3-5-pro',priceVersion:'legacy-streaming',maxCost:7500,feeBps:0,streamingSeconds:60}).request;
  return {db,ledger,account,keyId,reserve,advance:ms=>time+=ms,now:()=>time,writes:()=>db.prepare('SELECT total_changes() AS n').get().n};
}

test('an expired issued token remains uncertain and reserved until independent reconciliation',()=>{
  const f=fixture();
  try {
    const r=f.reserve('issued');
    f.ledger.streaming.attach(r.id,'encrypted-token',f.now()+60_000);
    f.advance(60_001);
    f.ledger.streaming.expire();
    assert.equal(f.ledger.streaming.get(r.id).token_cipher,null);
    f.advance(150_000);
    f.ledger.streaming.expire();
    assert.equal(f.ledger.streaming.get(r.id).state,'uncertain');
    assert.ok(f.ledger.summary(f.account).reserved>0);
    const writes=f.writes();
    f.ledger.streaming.expire();
    assert.equal(f.writes(),writes);
  } finally {f.db.close();}
});

test('unissued authorization releases safely and cancellation tombstones expire',()=>{
  const f=fixture();
  try {
    const r=f.reserve('never-issued');
    f.ledger.streaming.cancelAuthorization(f.account,f.keyId,'never-issued');
    assert.equal(f.ledger.streaming.get(r.id).state,'released');
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM streaming_cancellations').get().n,1);
    f.advance(86_400_001);
    f.ledger.streaming.purge();
    assert.equal(f.db.prepare('SELECT COUNT(*) n FROM streaming_cancellations').get().n,0);
  } finally {f.db.close();}
});
