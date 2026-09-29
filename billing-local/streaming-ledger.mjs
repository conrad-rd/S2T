import { Fault, requireThat, integer } from './money.mjs';
export function createStreamingLedger(db, { now, tx, entry, audit, keyBudgets, balance, held, refreshFreeze }) {
  db.exec(`CREATE TABLE IF NOT EXISTS streaming_sessions(request_id TEXT PRIMARY KEY REFERENCES requests(id),max_seconds INTEGER NOT NULL,window_end INTEGER NOT NULL,token_expires INTEGER,token_cipher TEXT,session_id TEXT UNIQUE,session_seconds REAL,audio_seconds REAL,billing TEXT NOT NULL DEFAULT 'client-reported-beta');`);
  db.exec(`CREATE TABLE IF NOT EXISTS streaming_cancellations(account TEXT NOT NULL,key_id TEXT NOT NULL,dedup TEXT NOT NULL,created INTEGER NOT NULL,PRIMARY KEY(account,key_id,dedup));`);
  const one = (s, ...args) => db.prepare(s).get(...args);
  const run = (s, ...args) => db.prepare(s).run(...args);
  const get = id => one('SELECT s.*,r.account,r.key_id,r.state,r.reserved,r.charged FROM streaming_sessions s JOIN requests r ON r.id=s.request_id WHERE s.request_id=?', id);
  const abandon = (id, reason) => {
    const r = get(id);
    if (!r || r.state !== 'submitted') return;
    // An issued token can already have reached a provider. Retain its hold
    // until independent usage is reconciled or an operator records a writeoff.
    if (r.token_expires === null) run("UPDATE requests SET state='released',updated=? WHERE id=?", now(), id);
    else run("UPDATE requests SET state='uncertain',updated=? WHERE id=?", now(), id);
    run('UPDATE streaming_sessions SET token_cipher=NULL WHERE request_id=?', id);
    refreshFreeze(r.account);
    audit(r.token_expires === null ? 'streaming_released_without_token' : 'streaming_requires_reconciliation', `${id}:${reason}`);
  };
  return {
    get,
    checkAuthorization(account, keyId, dedup) {
      requireThat(!one('SELECT 1 AS cancelled FROM streaming_cancellations WHERE account=? AND key_id=? AND dedup=?', account, keyId, dedup), 'streaming_cancelled', 'This recording authorization was cancelled. Start a new recording.', 409);
    },
    cancelAuthorization(account, keyId, dedup) {
      return tx(() => {
        const r = one('SELECT r.id FROM requests r JOIN streaming_sessions s ON s.request_id=r.id WHERE r.account=? AND r.key_id=? AND r.dedup=?', account, keyId, dedup);
        if (!r) return { abandoned: false };
        run('INSERT OR IGNORE INTO streaming_cancellations VALUES(?,?,?,?)', account, keyId, dedup, now());
        abandon(r.id, 'authorization_cancelled');
        return { abandoned: true };
      });
    },
    eligible(id) {
      const r = get(id);
      requireThat(r && one("SELECT value FROM metadata WHERE key='paused'").value === '0', 'paused', 'New requests are paused.');
      requireThat(one('SELECT frozen FROM accounts WHERE id=?', r.account)?.frozen === 0, 'frozen', 'Account is frozen.');
      keyBudgets.check(r.account, r.key_id, 0);
      requireThat(balance(r.account) >= held(r.account), 'insufficient_credits', 'Not enough available credits.', 402);
    },
    validateReservation(account, seconds) {
      integer(seconds, 60, 630, 'Maximum session duration');
      requireThat(one("SELECT COUNT(*) n FROM streaming_sessions s JOIN requests r ON r.id=s.request_id WHERE r.account=? AND r.state!='released' AND s.session_id IS NULL AND s.window_end>?", account, now()).n < 8, 'streaming_concurrency', 'Too many unconfirmed streaming sessions. Try again shortly.', 429);
    },
    reserve(id, seconds) {
      run('INSERT INTO streaming_sessions(request_id,max_seconds,window_end) VALUES(?,?,?)', id, seconds, now() + (seconds + 90) * 1000);
      run("UPDATE requests SET state='submitted' WHERE id=?", id);
      audit('streaming_authorized', id);
    },
    attach(id, cipher, expires) {
      return tx(() => {
        const r = get(id);
        requireThat(r && !r.token_cipher && r.state === 'submitted', 'streaming_state', 'Streaming authorization cannot be replaced.');
        run('UPDATE streaming_sessions SET token_cipher=?,token_expires=?,window_end=MAX(window_end,?) WHERE request_id=?', cipher, expires, expires + (r.max_seconds + 30) * 1000, id);
      });
    },
    abandon(account, keyId, id) {
      return tx(() => {
        const r = get(id);
        requireThat(r && r.account === account && r.key_id === keyId, 'streaming_session', 'Session not found.', 404);
        abandon(id, 'client_cancelled');
        return { abandoned: true };
      });
    },
    expire() { return tx(() => this.purge()); },
    purge() {
      run('UPDATE streaming_sessions SET token_cipher=NULL WHERE token_expires<=? AND token_cipher IS NOT NULL', now());
      run('DELETE FROM streaming_cancellations WHERE created<=?', now() - 86400000);
      const expired = db.prepare("SELECT s.request_id FROM streaming_sessions s JOIN requests r ON r.id=s.request_id WHERE r.state='submitted' AND s.window_end<=?").all(now());
      for (const r of expired) abandon(r.request_id, 'authorization_expired');
    },
    complete() {
      throw new Fault('streaming_retired', 'Client-reported streaming usage is no longer accepted. Provider usage requires operator reconciliation.', 410);
    },
  };
}
