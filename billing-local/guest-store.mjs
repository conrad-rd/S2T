import { randomUUID, createHash } from 'node:crypto';
import { requireThat } from './money.mjs';
const hash = value => createHash('sha256').update(value).digest('hex');

export function createGuestStore(db, tx, now) {
  db.exec(`CREATE TABLE IF NOT EXISTS guest_wallets(account TEXT PRIMARY KEY REFERENCES accounts(id), recovery_hash TEXT UNIQUE NOT NULL, email_opt_in INTEGER NOT NULL DEFAULT 0, email_hash TEXT, email_payload TEXT, key_id TEXT UNIQUE REFERENCES api_keys(id), credential_version INTEGER NOT NULL DEFAULT 1, key_payload TEXT, recovery_payload TEXT);
    CREATE TABLE IF NOT EXISTS guest_sessions(hash TEXT PRIMARY KEY,account TEXT NOT NULL REFERENCES guest_wallets(account),expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS guest_recoveries(hash TEXT PRIMARY KEY,account TEXT NOT NULL REFERENCES guest_wallets(account),expires INTEGER NOT NULL,used INTEGER NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS guest_email ON guest_wallets(email_hash);`);
  const columns = db.prepare('PRAGMA table_info(guest_wallets)').all().map(row => row.name);
  if (!columns.includes('credential_version')) db.exec('ALTER TABLE guest_wallets ADD COLUMN credential_version INTEGER NOT NULL DEFAULT 1');
  if (!columns.includes('key_payload')) db.exec('ALTER TABLE guest_wallets ADD COLUMN key_payload TEXT');
  if (!columns.includes('recovery_payload')) db.exec('ALTER TABLE guest_wallets ADD COLUMN recovery_payload TEXT');
  const get = (sql, ...args) => db.prepare(sql).get(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const session = (account, token) => run('INSERT INTO guest_sessions VALUES(?,?,?)', hash(token), account, now() + 180 * 86400000);
  return {
    purge() {
      run('DELETE FROM guest_recoveries WHERE expires<=? OR used=1', now());
      run('DELETE FROM guest_sessions WHERE expires<=?', now());
      // A browser wallet with no financial or API history is disposable once
      // its session and any recent checkout have expired. Paid history stays.
      const abandoned = db.prepare(`SELECT g.account FROM guest_wallets g JOIN accounts a ON a.id=g.account
        WHERE a.created<=? AND g.key_id IS NULL
          AND NOT EXISTS(SELECT 1 FROM guest_sessions s WHERE s.account=g.account)
          AND NOT EXISTS(SELECT 1 FROM guest_recoveries r WHERE r.account=g.account)
          AND NOT EXISTS(SELECT 1 FROM checkout_orders o WHERE o.account=g.account AND o.created>?)
          AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.account=g.account)
          AND NOT EXISTS(SELECT 1 FROM ledger l WHERE l.account=g.account)
          AND NOT EXISTS(SELECT 1 FROM requests r WHERE r.account=g.account)
          AND NOT EXISTS(SELECT 1 FROM api_keys k WHERE k.account=g.account)`).all(now() - 181 * 86400000, now() - 30 * 86400000);
      for (const row of abandoned) {
        run('DELETE FROM checkout_orders WHERE account=?', row.account);
        run('DELETE FROM guest_wallets WHERE account=?', row.account);
        run('DELETE FROM accounts WHERE id=?', row.account);
      }
    },
    get(account) { return get('SELECT * FROM guest_wallets WHERE account=?', account); },
    purchaseCount(account) { return get('SELECT COUNT(*) AS n FROM payments WHERE account=?', account).n; },
    start(account, token, recoveryHash, credentialVersion = 1) {
      return tx(() => {
        run('INSERT INTO accounts VALUES(?,0,?)', account, now());
        run('INSERT INTO guest_wallets(account,recovery_hash,credential_version) VALUES(?,?,?)', account, recoveryHash, credentialVersion);
        session(account, token);
      });
    },
    legacyBatch(limit = 100) { return db.prepare('SELECT * FROM guest_wallets WHERE credential_version=1 ORDER BY account LIMIT ?').all(limit); },
    legacyCount() { return get('SELECT COUNT(*) AS n FROM guest_wallets WHERE credential_version=1').n; },
    migrate(account, { keyPayload, recoveryPayload, recoveryCode, emailHash, emailPayload }) {
      return tx(() => {
        const row = this.get(account);
        requireThat(row && row.credential_version === 1, 'guest_migration', 'Legacy guest wallet changed during migration.');
        requireThat(row.recovery_hash === hash(recoveryCode), 'guest_migration', 'Legacy recovery code does not match the original result key. Keep the original key available.');
        requireThat(!row.key_id || get('SELECT hash FROM api_keys WHERE id=?', row.key_id).hash === hash(keyPayload.rawKey),
          'guest_migration', 'Legacy guest key does not match the original result key. Keep the original key available.');
        run('UPDATE guest_wallets SET credential_version=2,key_payload=?,recovery_payload=?,email_hash=?,email_payload=? WHERE account=?',
          keyPayload.cipher, recoveryPayload, emailHash, emailPayload, account);
      });
    },
    session(token) { return get('SELECT g.* FROM guest_sessions s JOIN guest_wallets g ON g.account=s.account WHERE s.hash=? AND s.expires>?', hash(token), now()); },
    optIn(account, enabled) {
      const row = this.get(account);
      requireThat(row, 'guest', 'Prepaid purchase not found.', 404);
      if (enabled) run('UPDATE guest_wallets SET email_opt_in=1 WHERE account=?', account);
      else {
        run('UPDATE guest_wallets SET email_opt_in=0,email_hash=NULL,email_payload=NULL WHERE account=?', account);
        run('DELETE FROM guest_recoveries WHERE account=?', account);
      }
    },
    email(account, emailHash, payload) {
      run('UPDATE guest_wallets SET email_hash=?,email_payload=? WHERE account=? AND email_opt_in=1 AND email_hash IS NULL', emailHash, payload, account);
    },
    byEmail(emailHash, afterAccount = '', limit = 20) {
      return db.prepare('SELECT * FROM guest_wallets WHERE email_hash=? AND key_id IS NOT NULL AND account>? ORDER BY account LIMIT ?').all(emailHash, afterAccount, limit);
    },
    issue(account, key) {
      return tx(() => {
        const row = this.get(account);
        requireThat(row, 'guest', 'Prepaid purchase not found.', 404);
        if (row.key_id) return row.key_id;
        if (!get('SELECT session FROM payments WHERE account=? LIMIT 1', account)) return null;
        requireThat(!get('SELECT frozen FROM accounts WHERE id=?', account).frozen, 'frozen', 'This purchase is under review.', 403);
        const id = randomUUID();
        run('INSERT INTO api_keys VALUES(?,?,?,?,0,?)', id, hash(key), account, key.slice(-6), Number.MAX_SAFE_INTEGER);
        run('UPDATE guest_wallets SET key_id=? WHERE account=?', id, account);
        run('INSERT INTO audit VALUES(?,?,?,?)', randomUUID(), 'guest_key_issued', id, now());
        return id;
      });
    },
    recovery(account, token) { run('INSERT INTO guest_recoveries VALUES(?,?,?,0)', hash(token), account, now() + 15 * 60000); },
    recover(code, token, emailLink = false) {
      return tx(() => {
        const row = emailLink
          ? get('SELECT account FROM guest_recoveries WHERE hash=? AND expires>? AND used=0', hash(code), now())
          : get('SELECT account FROM guest_wallets WHERE recovery_hash=?', hash(code));
        requireThat(row, 'recovery', 'Recovery code is invalid or the email link has expired.', 401);
        if (emailLink) run('UPDATE guest_recoveries SET used=1 WHERE hash=?', hash(code));
        session(row.account, token);
        return row.account;
      });
    },
  };
}
