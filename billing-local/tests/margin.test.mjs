import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createLedger } from '../ledger-core.mjs';
import { fundedMicros, credits } from '../money.mjs';

test('purchases reserve 50 percent for providers, retaining the rest for tax, fees and service', () => {
  for (const cents of [100, 101, 500, 2500, 10000]) {
    assert.equal(fundedMicros(cents), cents * 5000);
    assert.equal(credits(fundedMicros(cents)), cents);
    assert.equal(cents * 10000 - fundedMicros(cents), cents * 5000);
  }
});

test('legacy purchased value survives repricing and refunds reverse the original grant', () => {
  const db = new DatabaseSync(':memory:');
  let ledger = createLedger(db);
  const { account } = ledger.createSession();
  db.prepare('INSERT INTO payments VALUES(?,?,?,?,0,?)').run('legacy-session', 'legacy-intent', account, 100, 1);
  db.prepare('INSERT INTO ledger VALUES(?,?,?,?,?,?)').run('legacy-grant', account, 900000, 'purchase', 'legacy-session', 1);
  ledger = createLedger(db);
  assert.equal(ledger.summary(account).balance, 180);
  ledger.reverse({ id: 'old-partial', intent: 'legacy-intent', cents: 33, kind: 'refund' });
  assert.equal(db.prepare('SELECT SUM(amount) AS amount FROM ledger').get().amount, 603000);
  ledger.reverse({ id: 'old-rest', intent: 'legacy-intent', cents: 67, kind: 'refund' });
  assert.equal(ledger.summary(account).balance, 0);
  ledger.grant({ account, cents: 100, session: 'new-session', intent: 'new-intent' });
  assert.equal(ledger.summary(account).balance, 100);
  ledger.reverse({ id: 'new-partial', intent: 'new-intent', cents: 33, kind: 'refund' });
  assert.equal(ledger.summary(account).balance, 67);
  ledger.reverse({ id: 'new-dispute', intent: 'new-intent', cents: 100, kind: 'dispute' });
  assert.equal(ledger.summary(account).balance, 0);
  db.close();
});

test('funding allocation is 70/30 after the margin, reverses refunds, and never claims a transfer', () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db);
  const { account } = ledger.createSession();
  ledger.grant({ account, cents: 2000, session: 'split-session', intent: 'split-intent' });
  const report = ledger.funding();
  assert.equal(report.grossMicros, 20000000);
  assert.equal(report.retainedBeforeTaxAndFeesMicros, 10000000);
  assert.equal(report.providers.openrouter.allocatedMicros, 7000000);
  assert.equal(report.providers.assemblyai.allocatedMicros, 3000000);
  assert.equal(report.transfersAutomated, false);
  assert.equal(report.availableForPayout, null);
  ledger.reverse({ id: 'refund', intent: 'split-intent', cents: 1500, kind: 'refund' });
  const refunded = ledger.funding();
  assert.equal(refunded.grossMicros, 5000000);
  assert.equal(refunded.providers.openrouter.allocatedMicros, 1750000);
  assert.equal(refunded.providers.assemblyai.allocatedMicros, 750000);
  ledger.reverse({ id: 'refund', intent: 'split-intent', cents: 1500, kind: 'refund' });
  assert.deepEqual(ledger.funding(), refunded);
  db.close();
});

test('provider batches accrue only from settled use, never a purchase or an opened $5 block', async () => {
  const { providerFunding } = await import('../provider-funding.mjs');
  let report = providerFunding(20000000, 16000000, 0);
  assert.equal(report.earnedProviderMicros, 0);
  assert.equal(report.providers.openrouter.cumulativeBatchedMicros, 0);
  report = providerFunding(20000000, 16000000, 4000);
  assert.equal(report.providers.openrouter.earnedMicros, 2800);
  assert.equal(report.providers.assemblyai.earnedMicros, 1200);
  assert.equal(report.providers.openrouter.cumulativeBatchedMicros, 0);
  report = providerFunding(20000000, 16000000, 8000000);
  assert.equal(report.providers.openrouter.cumulativeBatchedMicros, 5000000);
  assert.equal(report.providers.assemblyai.cumulativeBatchedMicros, 0);
  assert.equal(report.availableForPayout, null);
  report = providerFunding(5000000, 4000000, 8000000);
  assert.equal(report.earnedProviderMicros, 4000000);
});

test('unused purchases and complimentary usage cannot fund providers, including across accounts', () => {
  const db = new DatabaseSync(':memory:');
  const ledger = createLedger(db);
  const paid = ledger.createSession().account;
  ledger.grant({ account: paid, cents: 2000, session: 'paid', intent: 'paid' });
  const free = ledger.createSession().account;
  ledger.setBalance({ account: free, targetCredits: 1000, id: 'free-credit-fixture', reason: 'Isolated complimentary credit fixture.' });
  const settle = (account, id, cost) => {
    const r = ledger.reserve({ account, dedup: id, fingerprint: id, provider: 'openrouter', model: 'fixture', priceVersion: 'v1', maxCost: cost }).request;
    ledger.submit(r.id); ledger.settle(r.id, { cost, providerId: id });
  };
  settle(free, 'free-use', 5000000);
  assert.equal(ledger.funding().earnedProviderMicros, 0);
  ledger.setBalance({ account: paid, targetCredits: 2100, id: 'bonus-credit-fixture', reason: 'Isolated complimentary bonus fixture.' });
  settle(paid, 'bonus-use', 500000);
  assert.equal(ledger.funding().earnedProviderMicros, 0);
  settle(paid, 'paid-use', 4000);
  assert.equal(ledger.funding().earnedProviderMicros, 4000);
  db.close();
});
