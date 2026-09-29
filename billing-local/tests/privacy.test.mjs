import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';

test('expired content is removed without changing money, pending requests or replay identity', () => {
  let clock = 1800000000000;
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db, { now: () => clock });
  const { account } = ledger.createSession();
  ledger.grant({ account, cents: 100, session: 'payment', intent: 'intent' });
  const input = { account, dedup: 'privacy-request-0001', fingerprint: 'digest', provider: 'openrouter', model: 'model', priceVersion: 'fixture', maxCost: 1000 };
  const { request } = ledger.reserve(input);
  ledger.submit(request.id);
  ledger.settle(request.id, { cost: 90, providerId: 'receipt', result: 'encrypted-fixture' });
  const pending = ledger.reserve({ ...input, dedup: 'pending-request-0002' }).request;
  ledger.startDevice('fixture-token-hash', 'ABCD1234');
  const before = ledger.summary(account);
  clock += 3599999;
  ledger.purgeExpired();
  assert.equal(ledger.request(account, request.id).result, 'encrypted-fixture');
  clock++;
  ledger.purgeExpired();
  assert.equal(ledger.request(account, request.id).result, null);
  assert.equal(ledger.request(account, request.id).result_expires, null);
  assert.equal(ledger.reserve(input).created, false);
  assert.equal(ledger.request(account, pending.id).state, 'reserved');
  assert.deepEqual(ledger.summary(account), before);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM device_links').get().n, 0);
  clock += 7 * 86400000;
  ledger.purgeExpired();
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM sessions').get().n, 0);
  ledger.purgeExpired();
  assert.equal(ledger.summary(account).balance, before.balance);
  db.close();
});

test('rate limits store no raw identifiers, survive restart and expire at the window boundary', () => {
  let clock = 1800000000000;
  const db = new DatabaseSync(':memory:');
  let ledger = createLedger(db, { now: () => clock });
  assert.equal(ledger.rate('ip:192.0.2.40', 2), true);
  assert.equal(ledger.rate('ip:192.0.2.40', 2), true);
  const first = db.prepare('SELECT * FROM rate_limits').get();
  assert.match(first.key, /^[a-f0-9]{64}$/);
  assert.ok(!JSON.stringify(first).includes('192.0.2.40'));
  ledger = createLedger(db, { now: () => clock });
  assert.equal(ledger.rate('ip:192.0.2.40', 2), false);
  assert.equal(ledger.rate('ip:192.0.2.41', 2), true);
  assert.equal(ledger.rate('sessions:192.0.2.40', 1, 3600000), true);
  clock += 60000;
  ledger.purgeExpired();
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM rate_limits').get().n, 1);
  assert.equal(ledger.rate('ip:192.0.2.40', 2), true);
  assert.ok(!db.prepare('SELECT key FROM rate_limits').all().some(row => row.key === first.key));
  assert.equal(ledger.rate('sessions:192.0.2.40', 1, 3600000), false);
  clock += 3600000;
  ledger.purgeExpired();
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM rate_limits').get().n, 0);
  db.close();
});

test('legacy raw rate identifiers are retired during schema migration', () => {
  const db = new DatabaseSync(':memory:');
  db.exec("CREATE TABLE rate_limits(key TEXT PRIMARY KEY, count INTEGER NOT NULL, window INTEGER NOT NULL); INSERT INTO rate_limits VALUES('ip:192.0.2.40',1,0)");
  const ledger = createLedger(db);
  ledger.purgeExpired();
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM rate_limits').get().n, 0);
  assert.equal(ledger.rate('ip:192.0.2.40', 1), true);
  db.close();
});

test('device attribution keeps only pending requests and each account’s latest completed use', () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db);
  const first = ledger.createSession().account, second = ledger.createSession().account;
  for (const account of [first, second]) ledger.grant({ account, cents: 100, session: account, intent: account });
  let count = 0;
  const create = (account, { settle = true, device = true } = {}) => {
    const id = String(++count);
    const { request } = ledger.reserve({ account, dedup: 'device-request-000' + id, fingerprint: id,
      provider: 'openrouter', model: 'fixture', priceVersion: 'fixture', maxCost: 1000,
      device: device ? { id: '00000000-0000-4000-8000-000000000001', name: 'Mac' } : null });
    if (settle) { ledger.submit(request.id); ledger.settle(request.id, { cost: 90, providerId: 'provider-' + id }); }
    return request.id;
  };
  create(first);
  const other = create(second), latest = create(first), pending = create(first, { settle: false });
  ledger.purgeExpired();
  assert.deepEqual(new Set(db.prepare('SELECT request_id FROM request_devices').all().map(row => row.request_id)), new Set([other, latest, pending]));
  assert.equal(ledger.usage(first).lastUsed.device.name, 'Mac');
  ledger.cancel(first, pending);
  create(first, { device: false });
  ledger.purgeExpired();
  assert.deepEqual(db.prepare('SELECT request_id FROM request_devices').all().map(row => row.request_id), [other]);
  assert.equal(ledger.usage(first).lastUsed.device, null, 'Never infer a missing current device from an older request');
  assert.equal(ledger.usage(second).lastUsed.device.name, 'Mac');
  db.close();
});
