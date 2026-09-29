import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';
import { createWithdrawals } from '../withdrawals.mjs';

test('withdrawal receipt survives retries, encrypts contact data and never changes money', async () => {
  const db=new DatabaseSync(':memory:');const ledger=createLedger(db);
  let saved=0;
  const withdrawals=createWithdrawals({ledger,encryptionKey:Buffer.alloc(32,1),confirmSaved:async()=>{saved++}});
  const declaration={id:'11111111-1111-4111-8111-111111111111',name:'Test Consumer',email:'test@example.com',contract:'Purchase on 19 September for $20',delivery:'download',confirmed:true};
  const first=await withdrawals.submit(declaration);
  assert.match(first.receipt,/Test Consumer/);assert.match(first.receipt,/Purchase on 19 September/);
  assert.match(first.receipt,/I withdraw from/);assert.match(first.receipt,/UTC/);
  assert.deepEqual(await withdrawals.submit(declaration),first);
  const stored=ledger.withdrawals()[0];assert.doesNotMatch(stored.payload,/Test Consumer|example.com|September/);
  assert.equal(ledger.withdrawals().length,1);assert.equal(saved,2);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM ledger').get().n,0);
  await assert.rejects(withdrawals.submit({...declaration,contract:'Another purchase'}),/identifier/);
  await assert.rejects(withdrawals.submit({...declaration,confirmed:false}),/confirm/);
  await assert.rejects(withdrawals.submit({...declaration,email:'bad\r\nBcc: bad'}),/email/);
  const recovered=createWithdrawals({ledger,encryptionKey:Buffer.alloc(32,1)});
  assert.equal(recovered.list()[0].receipt,first.receipt);
  db.close();
});

test('storage confirmation failure never acknowledges a withdrawal and retry recovers it', async()=>{
  const db=new DatabaseSync(':memory:');const ledger=createLedger(db);let failed=true;
  const manager=createWithdrawals({ledger,encryptionKey:Buffer.alloc(32,2),confirmSaved:async()=>{if(failed)throw Error('storage unavailable')}});
  const value={id:'22222222-2222-4222-8222-222222222222',name:'Buyer',email:'buyer@example.com',contract:'Receipt 123',delivery:'download',confirmed:true};
  await assert.rejects(manager.submit(value),/storage unavailable/);
  failed=false;const result=await manager.submit(value);assert.ok(result.receivedAt);assert.equal(ledger.withdrawals().length,1);
  db.close();
});
