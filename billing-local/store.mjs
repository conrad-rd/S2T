import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createHash } from 'node:crypto';
export const hash = value => createHash('sha256').update(value).digest('hex');
export function createStore(path) {
  const db = new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, balance INTEGER NOT NULL DEFAULT 0); CREATE TABLE IF NOT EXISTS purchases(id TEXT PRIMARY KEY, account TEXT NOT NULL, cents INTEGER NOT NULL, created TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP); CREATE TABLE IF NOT EXISTS keys(hash TEXT PRIMARY KEY, account TEXT NOT NULL, suffix TEXT NOT NULL);`);
  return {
    create() { const id = randomBytes(32).toString('hex'); db.prepare('INSERT INTO accounts(id) VALUES(?)').run(hash(id)); return id; },
    account(token) { return db.prepare('SELECT * FROM accounts WHERE id=?').get(hash(token)); },
    summary(id) { return {balance: db.prepare('SELECT balance FROM accounts WHERE id=?').get(id).balance, purchases: db.prepare('SELECT id,cents,created FROM purchases WHERE account=? ORDER BY rowid DESC LIMIT 20').all(id), keys: db.prepare('SELECT suffix FROM keys WHERE account=?').all(id)}; },
    credit(id, cents, reference) {
      if (!Number.isInteger(cents) || cents < 100 || cents > 10000) throw Error('Choose an amount between $1 and $100.');
      db.exec('BEGIN IMMEDIATE');
      try {
        if (!db.prepare('SELECT id FROM accounts WHERE id=?').get(id)) throw Error('Account not found.');
        const existing = db.prepare('SELECT * FROM purchases WHERE id=?').get(reference);
        if (existing && (existing.account !== id || existing.cents !== cents)) throw Error('Payment reference conflict.');
        if (!existing) { db.prepare('INSERT INTO purchases(id,account,cents) VALUES(?,?,?)').run(reference,id,cents); db.prepare('UPDATE accounts SET balance=balance+? WHERE id=?').run(cents,id); }
        db.exec('COMMIT');
      } catch(e) { db.exec('ROLLBACK'); throw e; }
    },
    key(id) {
      if (!db.prepare('SELECT balance FROM accounts WHERE id=?').get(id)?.balance) throw Error('Add demo credits before creating a key.');
      if (db.prepare('SELECT count(*) AS count FROM keys WHERE account=?').get(id).count >= 10) throw Error('This demo allows ten keys per wallet.');
      const key = 's2t_demo_' + randomBytes(32).toString('hex');
      db.prepare('INSERT INTO keys(hash,account,suffix) VALUES(?,?,?)').run(hash(key),id,key.slice(-6)); return key;
    },
    close() { db.close(); }
  };
}
