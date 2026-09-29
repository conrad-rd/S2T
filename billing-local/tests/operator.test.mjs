import test from 'node:test';
import assert from 'node:assert/strict';
import { operate } from '../cloudflare/operator.mjs';
test('operator repair requires its separate secret and never accepts an app key', () => {
  let touched = 0;
  const ledger = { health() { touched++; return { paused: true }; }, resume() { touched++; }, reconcile(id, receipt) { touched++; assert.equal(id, 'request'); assert.equal(receipt.cost, 0); return true; }, confirmWriteOff() { touched++; return true; } };
  const secret = 'a'.repeat(64);
  for (const auth of [null, 'Bearer s2t_live_fixture', 'Bearer '+ 'b'.repeat(64)]) assert.throws(() => operate(ledger, secret, auth, {action:'health'}), /authentication/);
  assert.equal(touched, 0);
  for (const action of ['account', 'set_balance', 'funding']) {
    assert.throws(() => operate(ledger, secret, 'Bearer s2t_live_fixture', { action, targetCredits: 200 }), /authentication/);
  }
  assert.deepEqual(operate(ledger, secret, 'Bearer '+secret, {action:'health'}), {paused:true});
  assert.deepEqual(operate(ledger, secret, 'Bearer '+secret, {action:'confirm_writeoff',requestId:'request'}), {confirmed:true});
  assert.throws(() => operate(ledger, undefined, 'Bearer '+secret, {action:'resume'}), /authentication/);
  assert.throws(() => operate(ledger, secret, 'Bearer '+secret, {action:'grant',credits:100}), /Unknown/);
});

test('operator pricing recovery uses the deployed version and exposes provider total reconciliation', () => {
  const secret = 'a'.repeat(64), auth = 'Bearer ' + secret;
  const calls = [];
  const ledger = { reviewPricing: version => calls.push(version), reconcileReport: report => { calls.push(report); return true; } };
  assert.throws(() => operate(ledger, secret, 'Bearer customer-key', {action:'review_pricing'}, {version:'current-v2'}), /authentication/);
  assert.throws(() => operate(ledger, secret, auth, {action:'review_pricing',version:'invented'}), /deployed pricing/);
  assert.deepEqual(operate(ledger, secret, auth, {action:'review_pricing',version:'invented'}, {version:'current-v2'}), {reviewed:true,version:'current-v2'});
  const report = {provider:'openrouter',through:123,totalCostMicros:456,evidence:'b'.repeat(64)};
  assert.deepEqual(operate(ledger, secret, auth, {action:'reconcile_report',...report}), {reconciled:true});
  assert.deepEqual(calls, ['current-v2',report]);
});
