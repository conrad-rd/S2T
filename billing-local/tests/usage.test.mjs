import test from 'node:test';
import assert from 'node:assert/strict';
import { openLedger } from '../ledger.mjs';
import { requestDevice } from '../usage.mjs';

test('device metadata is optional, bounded and limited to generic model labels', () => {
  assert.equal(requestDevice(null, null), null);
  const id = 'A42FB61A-8053-4336-9482-B3E5F27EC7A1';
  assert.equal(requestDevice(id, 'Mac').id, id.toLowerCase());
  for (const [key, name] of [['x', 'Mac'], [id, '<script>'], [id, 'Private computer name'], [null, 'Mac']]) assert.throws(() => requestDevice(key, name));
});

test('usage counts all settled debits, fills UTC days and isolates accounts', () => {
  let clock = Date.parse('2026-09-17T12:00:00Z');
  const ledger = openLedger(':memory:', { now: () => clock, limits: { requestsPerMinute: 100 } });
  const account = ledger.createSession().account;
  const other = ledger.createSession().account;
  ledger.grant({ account, cents: 500, session: 'usage-payment', intent: 'usage-intent' });
  ledger.grant({ account: other, cents: 500, session: 'other-payment', intent: 'other-intent' });
  let sequence = 0;
  const reserve = (owner = account, device = null) => ledger.reserve({ account: owner, device, dedup: `usage-${++sequence}`, fingerprint: `fixture-${sequence}`, provider: 'openrouter', model: 'fixture', priceVersion: 'test', maxCost: 5000 });
  const settle = (owner = account, device = null) => {
    const r = reserve(owner, device).request;
    ledger.submit(r.id);
    ledger.settle(r.id, { cost: 5000, providerId: `receipt-${sequence}` });
    return r;
  };
  try {
    clock = Date.parse('2026-09-10T23:59:59.999Z'); settle();
    clock++; settle();
    clock = Date.parse('2026-09-17T12:00:00Z');
    for (let i = 0; i < 25; i++) settle();
    settle(other);
    const device = { id: 'a42fb61a-8053-4336-9482-b3e5f27ec7a1', name: 'MacBook Pro' };
    clock++;
    const last = settle(account, device);
    const replay = ledger.reserve({ account, device: { ...device, name: 'Mac mini' }, dedup: last.dedup, fingerprint: last.fingerprint, provider: 'openrouter', model: 'fixture', priceVersion: 'test', maxCost: 5000 });
    assert.equal(replay.created, false);
    const pending = reserve().request;
    const usage = ledger.usage(account, 7);
    assert.equal(usage.series.length, 7);
    assert.equal(usage.series[0].day, '2026-09-11');
    assert.equal(usage.series[0].credits, 1);
    assert.equal(usage.series[1].credits, 0);
    assert.equal(usage.spentCredits, 27);
    assert.equal(usage.requestCount, 27);
    assert.equal(usage.lastUsed.at, clock);
    assert.deepEqual(usage.lastUsed.device, { name: 'MacBook Pro', suffix: 'C7A1' });
    assert.deepEqual(usage.providers, [{ provider: 'openrouter', credits: 27 }]);
    assert.equal(ledger.usage(other, 7).spentCredits, 1);
    assert.equal(ledger.usage(account, 30).spentCredits, 28);
    ledger.cancel(account, pending.id);
    assert.equal(ledger.usage(account, 7).spentCredits, 27);
    for (const days of [0, 8, 31, 10000, NaN, '30']) assert.throws(() => ledger.usage(account, days));
    assert.throws(() => ledger.usage('missing', 30));
  } finally { ledger.close(); }
});

test('empty usage has no fabricated last device or activity', () => {
  const ledger = openLedger(':memory:');
  try {
    const account = ledger.createSession().account;
    const usage = ledger.usage(account, 90);
    assert.equal(usage.lastUsed, null);
    assert.equal(usage.spentCredits, 0);
    assert.equal(usage.series.length, 90);
    assert.ok(usage.series.every(day => day.credits === 0 && day.requests === 0));
  } finally { ledger.close(); }
});
