import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { Readable } from 'node:stream';
import { createLedger } from '../ledger-core.mjs';
import { createApplication } from '../server.mjs';
import { fixturePolicy } from '../policy.mjs';

test('rejected rate-limit traffic performs no further database writes and remains rejected after restart', () => {
  let clock = 1800000000000;
  const db = new DatabaseSync(':memory:');
  let ledger = createLedger(db, { now: () => clock });
  try {
    for (let i = 0; i < 3; i++) assert.equal(ledger.rate('attacker', 3), true);
    const writes = () => db.prepare('SELECT total_changes() AS n').get().n;
    const before = writes();
    for (let i = 0; i < 1000; i++) assert.equal(ledger.rate('attacker', 3), false);
    assert.equal(writes() - before, 0, 'Rejected traffic must not exhaust durable write quota');
    ledger = createLedger(db, { now: () => clock });
    assert.equal(ledger.rate('attacker', 3), false);
    assert.equal(ledger.rate('another-client', 3), true);
    clock += 60000;
    assert.equal(ledger.rate('attacker', 3), true);
  } finally { db.close(); }
});

test('real-provider HTTP requests use the ledger funding gate and preserve paid replay after review expires', async () => {
  const dataDir = mkdtempSync(tmpdir() + '/s2t-live-http-');
  const config = { mode: 'test', realProviders: true, dataDir, origin: 'http://localhost:4317', port: 4317,
    policy: fixturePolicy, resultKey: Buffer.alloc(32, 9), fundingReviewedAt: Date.now() };
  let calls = 0;
  const app = createApplication(config, { execute: async request => {
    calls++;
    return { text: 'Billed once.', model: request.model, cost: 90, providerId: 'http-paid-receipt' };
  } });
  const account = app.ledger.createSession().account;
  app.ledger.grant({ account, cents: 500, session: 'cs_http', intent: 'pi_http' });
  const key = app.ledger.issueKey(account).key;
  const invoke = async (instance, id = 'live-http-request-001') => {
    const req = Readable.from([Buffer.from(JSON.stringify({ provider: 'openrouter', operation: 'cleanup', text: 'Synthetic fixture.' }))]);
    req.url = '/api/v1/requests'; req.method = 'POST';
    req.headers = { host: 'localhost:4317', authorization: `Bearer ${key}`, 'idempotency-key': id };
    req.socket = { remoteAddress: '127.0.0.1' };
    const res = { destroyed: false, setHeader() {}, writeHead(status) { this.status = status; }, end(body) { this.body = JSON.parse(body); } };
    await instance.server.listeners('request')[0](req, res);
    return res;
  };
  let active = app;
  try {
    const first = await invoke(app);
    assert.equal(first.status, 200, JSON.stringify(first.body));
    assert.equal(first.body.state, 'settled');
    await app.close();
    active = createApplication({ ...config, fundingReviewedAt: Date.now() - 86400001 }, { execute: async () => assert.fail('Expired review dispatched inference') });
    const replay = await invoke(active);
    assert.equal(replay.status, 200);
    assert.equal(replay.body.id, first.body.id);
    assert.equal(replay.body.result.text, 'Billed once.');
    const fresh = await invoke(active, 'live-http-request-002');
    assert.equal(fresh.status, 503);
    assert.equal(fresh.body.code, 'funding_review_expired');
    assert.equal(calls, 1);
  } finally { await active.close(); rmSync(dataDir, { recursive: true, force: true }); }
});
