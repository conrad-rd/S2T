import { createHash, timingSafeEqual } from 'node:crypto';
import { requireThat } from '../money.mjs';
export function operate(ledger, expected, authorization, value, policy, withdrawals, guests) {
  const supplied = authorization?.startsWith('Bearer ') ? authorization.slice(7) : '';
  const digest = text => createHash('sha256').update(text).digest();
  requireThat(typeof expected === 'string' && expected.length === 64 && timingSafeEqual(digest(expected), digest(supplied)), 'operator_auth', 'Operator authentication required.', 401);
  if (value.action === 'funding') return ledger.funding();
  if (value.action === 'withdrawals') return { submissions: withdrawals.list() };
  if (value.action === 'health') return ledger.health();
  if (value.action === 'migrate_guest_credentials') {
    requireThat(guests, 'guest_migration', 'Guest migration is unavailable on this host.');
    return guests.migrateLegacyBatch();
  }
  if (value.action === 'account') return ledger.summary(value.account);
  if (value.action === 'set_balance') return ledger.setBalance({ account: value.account, targetCredits: value.targetCredits, id: value.id, reason: value.reason });
  if (value.action === 'reconcile') return { reconciled: ledger.reconcile(value.requestId, { cost: value.cost, providerId: value.providerId, evidence: value.evidence }) };
  if (value.action === 'reconcile_report') return { reconciled: ledger.reconcileReport({ provider: value.provider, through: value.through, totalCostMicros: value.totalCostMicros, evidence: value.evidence }) };
  if (value.action === 'review_pricing') {
    requireThat(typeof policy?.version === 'string' && policy.version.length > 0, 'pricing', 'A deployed pricing policy is required.');
    ledger.reviewPricing(policy.version);
    return { reviewed: true, version: policy.version };
  }
  if (value.action === 'reopen_reconciliation') return { reopened: ledger.reopenReconciliation(value.requestId, value.reason) };
  if (value.action === 'writeoff') return { writtenOff: ledger.writeOff(value.requestId, value.reason) };
  if (value.action === 'confirm_writeoff') return { confirmed: ledger.confirmWriteOff(value.requestId) };
  if (value.action === 'resume') { ledger.resume(); return { resumed: true }; }
  requireThat(false, 'operator_action', 'Unknown operator action.');
}
