import test from 'node:test';
import assert from 'node:assert/strict';
import { openLedger } from '../ledger.mjs';
import { createDeviceLink } from '../device-link.mjs';

test('device approval requires the signed-in account; polling cannot switch or duplicate keys', () => {
  let now = Date.now();
  const ledger = openLedger(':memory:', { now: () => now });
  const account = ledger.createSession().account;
  const other = ledger.createSession().account;
  const device = createDeviceLink({ ledger, mode: 'demo', encryptionKey: Buffer.alloc(32, 5), origin: 'http://localhost:4317' });
  const pending = device.start();
  assert.equal(device.poll(pending.deviceCode).state, 'pending');
  assert.throws(() => device.poll('bad-token'));
  device.approve(account, pending.userCode);
  assert.throws(() => device.approve(other, pending.userCode));
  const connected = device.poll(pending.deviceCode);
  assert.equal(connected.state, 'approved');
  assert.equal(ledger.authenticate(connected.key).account, account);
  assert.equal(device.poll(pending.deviceCode).key, connected.key);
  assert.equal(ledger.summary(account).keys.length, 1);
  ledger.revoke(account, ledger.authenticate(connected.key).id);
  assert.throws(() => device.poll(pending.deviceCode));
  const expiring = device.start();
  now += 600001;
  assert.throws(() => device.approve(account, expiring.userCode));
  ledger.close();
});

test('device approval remains available at zero credits while spending remains blocked', () => {
  const ledger = openLedger(':memory:');
  const account = ledger.createSession().account;
  const device = createDeviceLink({ ledger, mode: 'demo', encryptionKey: Buffer.alloc(32, 8), origin: 'http://localhost:4317' });
  const pending = device.start();
  device.approve(account, pending.userCode);
  assert.equal(ledger.summary(account).available, 0);
  assert.ok(ledger.authenticate(device.poll(pending.deviceCode).key));
  ledger.close();
});
