import { randomBytes, randomUUID, createHmac, createCipheriv, createDecipheriv } from 'node:crypto';
import { hash } from './ledger-core.mjs';
import { requireThat } from './money.mjs';

export const guestCookie = token => `__Host-s2t-guest=${token}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=15552000`;
export function guestToken(request) {
  return /(?:^|;\s*)__Host-s2t-guest=([a-f0-9]{64})(?:;|$)/.exec(request.headers.get('cookie') || '')?.[1] || '';
}
export function createGuestPurchases({ ledger, mode, encryptionKey, credentialKey = null, origin, sendEmail, confirmSaved = async () => {} }) {
  requireThat(Buffer.isBuffer(encryptionKey) && encryptionKey.length === 32, 'config', 'Result encryption key is unavailable.');
  requireThat(credentialKey === null || (Buffer.isBuffer(credentialKey) && credentialKey.length === 32 && !credentialKey.equals(encryptionKey)),
    'config', 'Guest credential key must be a separate 32-byte secret.');
  const derive = (key, purpose, account, version) => createHmac('sha256', key).update(`s2t-guest-${purpose}-v${version}:${account}`).digest('hex');
  const legacyAppKey = account => `s2t_${mode}_${derive(encryptionKey, 'key', account, 1)}`;
  const legacyRecovery = account => derive(encryptionKey, 'recovery', account, 1);
  const v2Derive = (purpose, account) => {
    requireThat(credentialKey, 'guest_key_config', 'The separate guest credential key is unavailable.', 503);
    return derive(credentialKey, purpose, account, 2);
  };
  const emailHash = (email, version) => derive(version === 2 ? credentialKey : encryptionKey, 'email', email.trim().toLowerCase(), version);
  const seal = (account, purpose, value) => {
    requireThat(credentialKey, 'guest_key_config', 'Configure the separate guest credential key before creating or migrating prepaid wallets.', 503);
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', credentialKey, iv);
    cipher.setAAD(Buffer.from(`s2t-guest-${purpose}-v2:${account}`));
    const data = Buffer.concat([cipher.update(Buffer.from(value)), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), data]).toString('base64');
  };
  const unseal = (account, purpose, payload) => {
    requireThat(credentialKey, 'guest_key_config', 'The separate guest credential key is unavailable.', 503);
    const data = Buffer.from(payload, 'base64'), cipher = createDecipheriv('aes-256-gcm', credentialKey, data.subarray(0, 12));
    cipher.setAAD(Buffer.from(`s2t-guest-${purpose}-v2:${account}`));
    cipher.setAuthTag(data.subarray(12, 28));
    return Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString();
  };
  const appKey = row => row.credential_version === 2
    ? row.key_payload ? unseal(row.account, 'key', row.key_payload) : `s2t_${mode}_${v2Derive('key', row.account)}`
    : legacyAppKey(row.account);
  const recovery = row => row.credential_version === 2
    ? row.recovery_payload ? unseal(row.account, 'recovery', row.recovery_payload) : v2Derive('recovery', row.account)
    : legacyRecovery(row.account);
  function encodeLegacy(account, email) {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', encryptionKey, iv);
    cipher.setAAD(Buffer.from(account));
    const data = Buffer.concat([cipher.update(Buffer.from(email)), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), data]).toString('base64');
  }
  function decodeLegacy(row) {
    const data = Buffer.from(row.email_payload, 'base64'), cipher = createDecipheriv('aes-256-gcm', encryptionKey, data.subarray(0, 12));
    cipher.setAAD(Buffer.from(row.account));
    cipher.setAuthTag(data.subarray(12, 28));
    return Buffer.concat([cipher.update(data.subarray(28)), cipher.final()]).toString();
  }
  const encode = (row, email) => row.credential_version === 2 ? seal(row.account, 'email', email) : encodeLegacy(row.account, email);
  const decode = row => row.credential_version === 2 ? unseal(row.account, 'email', row.email_payload) : decodeLegacy(row);
  return {
    start(token) {
      if (token && ledger.guests.session(token)) return { token };
      if (mode === 'live') requireThat(credentialKey, 'guest_key_config', 'New prepaid wallets require a separate guest credential key. Existing purchases remain available.', 503);
      token = randomBytes(32).toString('hex');
      const account = randomUUID();
      const version = credentialKey ? 2 : 1;
      ledger.guests.start(account, token, hash(version === 2 ? v2Derive('recovery', account) : legacyRecovery(account)), version);
      return { token };
    },
    account(token) {
      const row = ledger.guests.session(token);
      requireThat(row, 'guest_session', 'Your browser session expired. Use your recovery code or email.', 401);
      return row;
    },
    checkoutAccount(token, recoveryCode) {
      const row = this.account(token);
      requireThat(recoveryCode === recovery(row), 'guest_changed', 'Your purchase changed in another tab. Reload this page and save the current recovery code before paying.', 409);
      return row;
    },
    status(token) {
      const row = this.account(token), key = appKey(row);
      const keyId = ledger.guests.issue(row.account, key);
      const usable = keyId && ledger.authenticate(key);
      const summary = ledger.summary(row.account);
      return { state: keyId ? usable ? 'paid' : 'unavailable' : 'pending', key: usable ? key : null, recoveryCode: recovery(row), balance: summary.balance, purchaseCount: ledger.guests.purchaseCount(row.account), emailRecovery: !!row.email_hash, emailOptIn: !!row.email_opt_in };
    },
    fulfilled(session) {
      const row = ledger.guests.get(session.client_reference_id);
      if (!row) return;
      ledger.guests.issue(row.account, appKey(row));
      const email = session.customer_details?.email;
      if (row.email_opt_in && typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        ledger.guests.email(row.account, emailHash(email, row.credential_version), encode(row, email));
      }
    },
    recover(code, emailLink) {
      requireThat(typeof code === 'string' && /^[a-f0-9]{64}$/.test(code), 'recovery', 'Enter a valid recovery code.', 401);
      const token = randomBytes(32).toString('hex');
      ledger.guests.recover(code, token, emailLink);
      return { token };
    },
    migrateLegacyBatch() {
      requireThat(credentialKey, 'guest_key_config', 'Configure the separate guest credential key before migration.', 503);
      let migrated = 0;
      for (const row of ledger.guests.legacyBatch()) {
        requireThat(!row.email_hash || row.email_payload, 'guest_migration', 'Legacy email recovery data is incomplete; do not rotate the result key.');
        const oldKey = legacyAppKey(row.account), oldRecovery = legacyRecovery(row.account);
        const email = row.email_payload ? decodeLegacy(row) : null;
        ledger.guests.migrate(row.account, {
          keyPayload: { cipher: seal(row.account, 'key', oldKey), rawKey: oldKey },
          recoveryPayload: seal(row.account, 'recovery', oldRecovery),
          recoveryCode: oldRecovery,
          emailHash: email === null ? null : emailHash(email, 2),
          emailPayload: email === null ? null : seal(row.account, 'email', email),
        });
        migrated++;
      }
      return { migrated, remaining: ledger.guests.legacyCount() };
    },
    async requestEmail(email) {
      requireThat(sendEmail, 'email_disabled', 'Email recovery is not available yet.', 503);
      requireThat(typeof email === 'string' && email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email), 'email', 'Enter your checkout email.');
      const normalized = email.trim().toLowerCase();
      const rateKey = derive(credentialKey || encryptionKey, 'email-rate', normalized, credentialKey ? 2 : 1);
      if (ledger.rate('guest-email:' + rateKey, 3, 3600000)) {
        for (const emailID of credentialKey ? [emailHash(email, 2), emailHash(email, 1)] : [emailHash(email, 1)]) {
          let afterAccount = '';
          for (;;) {
            const rows = ledger.guests.byEmail(emailID, afterAccount);
            if (!rows.length) break;
            const links = rows.map(row => {
              const token = randomBytes(32).toString('hex');
              ledger.guests.recovery(row.account, token);
              return `${origin}/prepaid.html#recover=${token}`;
            });
            await confirmSaved();
            try { await sendEmail({ to: decode(rows[0]), links, id: randomUUID() }); }
            catch { console.error('S2T guest recovery email delivery failed.'); }
            afterAccount = rows.at(-1).account;
            if (rows.length < 20) break;
          }
        }
      }
      return { message: 'If this email has an eligible prepaid purchase, a recovery link will arrive shortly. Links expire after 15 minutes.' };
    },
  };
}

export function recoveryMailer(apiKey, from, fetcher = fetch) {
  if (!apiKey || !from) return null;
  return async ({ to, links, id }) => {
    const response = await fetcher('https://api.resend.com/emails', {
      method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(10000),
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': `s2t-recovery-${id}` },
      body: JSON.stringify({ from, to: [to], subject: 'Recover your S2T prepaid key', text: `Open a link to retrieve your existing prepaid key. Each link works once and expires in 15 minutes.\n\n${links.join('\n\n')}\n\nIf you did not request this, you can ignore this email.` }),
    });
    requireThat(response.ok, 'email_delivery', 'Recovery email could not be sent. Try again later.', 503);
  };
}
