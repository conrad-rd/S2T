import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';
import { createGuestPurchases } from '../guest-purchases.mjs';

test('legacy paid key, saved recovery code and email survive result-key rotation after explicit migration', async () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, { mode: 'test' });
  const original = Buffer.alloc(32, 1), separate = Buffer.alloc(32, 2), rotated = Buffer.alloc(32, 3);
  const sent = [];
  const make = encryptionKey => createGuestPurchases({ ledger, mode: 'test', encryptionKey,
    credentialKey: separate, origin: 'https://credits.example.test', sendEmail: async mail => sent.push(mail) });
  try {
    const legacy = createGuestPurchases({ ledger, mode: 'test', encryptionKey: original,
      origin: 'https://credits.example.test', sendEmail: async mail => sent.push(mail) });
    const { token } = legacy.start('');
    const account = legacy.account(token).account;
    ledger.guests.optIn(account, true);
    ledger.grant({ account, cents: 500, session: 'cs_legacy', intent: 'pi_legacy' });
    legacy.fulfilled({ client_reference_id: account, customer_details: { email: 'owner@example.test' } });
    const before = legacy.status(token);
    assert.equal(ledger.guests.get(account).credential_version, 1);
    assert.deepEqual(make(original).migrateLegacyBatch(), { migrated: 1, remaining: 0 });
    assert.equal(ledger.guests.get(account).credential_version, 2);
    const after = make(rotated);
    assert.equal(after.status(token).key, before.key);
    assert.equal(after.status(token).recoveryCode, before.recoveryCode);
    const recovered = after.recover(before.recoveryCode, false);
    assert.equal(after.status(recovered.token).key, before.key);
    await after.requestEmail('OWNER@example.test');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'owner@example.test');
    assert.equal(sent[0].links.length, 1);
    assert.equal(after.status(after.recover(new URL(sent[0].links[0]).hash.split('=')[1], true).token).key, before.key);
    assert.equal(ledger.authenticate(before.key).account, account);
  } finally { db.close(); }
});

test('guest top-ups preserve one key and email opt-out revokes outstanding recovery links', async () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, { mode: 'test' });
  const sent = [];
  const guest = createGuestPurchases({ ledger, mode: 'test', encryptionKey: Buffer.alloc(32, 1),
    credentialKey: Buffer.alloc(32, 2), origin: 'https://credits.example.test', sendEmail: async mail => sent.push(mail) });
  try {
    const { token } = guest.start('');
    const account = guest.account(token).account;
    ledger.guests.optIn(account, true);
    ledger.grant({ account, cents: 500, session: 'cs_first', intent: 'pi_first' });
    guest.fulfilled({ client_reference_id: account, customer_details: { email: 'owner@example.test' } });
    const first = guest.status(token);
    await guest.requestEmail('owner@example.test');
    const oldLink = new URL(sent[0].links[0]).hash.split('=')[1];
    ledger.guests.optIn(account, false);
    assert.throws(() => guest.recover(oldLink, true), { code: 'recovery' });
    assert.equal(guest.status(token).emailRecovery, false);
    ledger.grant({ account, cents: 500, session: 'cs_second', intent: 'pi_second' });
    guest.fulfilled({ client_reference_id: account, customer_details: { email: 'owner@example.test' } });
    assert.equal(guest.status(token).key, first.key);
    assert.equal(guest.status(token).purchaseCount, 2);
    assert.equal(guest.status(token).balance, 1000);
    assert.equal(guest.status(token).emailRecovery, false);
  } finally { db.close(); }
});

test('email recovery pages through every paid wallet instead of silently omitting later purchases', async () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, { mode: 'test' });
  const sent = [];
  const guest = createGuestPurchases({ ledger, mode: 'test', encryptionKey: Buffer.alloc(32, 1),
    credentialKey: Buffer.alloc(32, 2), origin: 'https://credits.example.test', sendEmail: async mail => sent.push(mail) });
  try {
    for (let i = 0; i < 21; i++) {
      const { token } = guest.start('');
      const account = guest.account(token).account;
      ledger.guests.optIn(account, true);
      ledger.grant({ account, cents: 500, session: `cs_${i}`, intent: `pi_${i}` });
      guest.fulfilled({ client_reference_id: account, customer_details: { email: 'owner@example.test' } });
    }
    await guest.requestEmail('owner@example.test');
    assert.deepEqual(sent.map(mail => mail.links.length), [20, 1]);
  } finally { db.close(); }
});

test('keyless legacy wallets block migration with the wrong original result key', () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, { mode: 'test' });
  const original = Buffer.alloc(32, 1), wrong = Buffer.alloc(32, 4), separate = Buffer.alloc(32, 2);
  try {
    const legacy = createGuestPurchases({ ledger, mode:'test', encryptionKey:original, origin:'https://credits.example.test' });
    const { token } = legacy.start('');
    const account = legacy.account(token).account;
    const recoveryCode = legacy.status(token).recoveryCode;
    const migrated = key => createGuestPurchases({ ledger, mode:'test', encryptionKey:key, credentialKey:separate, origin:'https://credits.example.test' });
    assert.throws(() => migrated(wrong).migrateLegacyBatch(), { code:'guest_migration' });
    assert.equal(ledger.guests.get(account).credential_version, 1);
    assert.deepEqual(migrated(original).migrateLegacyBatch(), {migrated:1,remaining:0});
    assert.equal(migrated(wrong).status(token).recoveryCode, recoveryCode);
  } finally {db.close();}
});

test('email recovery rate-limit keys do not retain raw address in persistent storage', async () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, {mode:'test'});
  const guest = createGuestPurchases({ledger, mode:'test', encryptionKey:Buffer.alloc(32,1), credentialKey:Buffer.alloc(32,2), origin:'https://credits.example.test', sendEmail:async()=>{}});
  try {
    await guest.requestEmail('private@example.test');
    const stored = db.prepare('SELECT key FROM rate_limits').get().key;
    assert.equal(stored.includes('private@example.test'), false);
    assert.match(stored, /^[a-f0-9]{64}$/);
  } finally {db.close();}
});

test('retention prunes abandoned guest credentials while preserving funded wallet history', () => {
  const db = new DatabaseSync(':memory:');
  let time = Date.UTC(2026,8,27);
  const ledger = createLedger(db, {mode:'test', now:()=>time});
  const guest = createGuestPurchases({ledger, mode:'test', encryptionKey:Buffer.alloc(32,1), credentialKey:Buffer.alloc(32,2), origin:'https://credits.example.test'});
  try {
    const abandonedToken = guest.start('').token;
    const abandoned = guest.account(abandonedToken).account;
    const paidToken = guest.start('').token;
    const paid = guest.account(paidToken).account;
    ledger.grant({account:paid,cents:500,session:'cs_retained',intent:'pi_retained'});
    guest.status(paidToken);
    time += 182 * 86400000;
    ledger.purgeExpired();
    assert.equal(ledger.guests.get(abandoned),undefined);
    assert.equal(db.prepare('SELECT id FROM accounts WHERE id=?').get(abandoned),undefined);
    assert.ok(ledger.guests.get(paid));
    assert.ok(db.prepare('SELECT session FROM payments WHERE account=?').get(paid));
    assert.equal(db.prepare('SELECT COUNT(*) n FROM guest_sessions').get().n,0);
  } finally {db.close();}
});
