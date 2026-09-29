import { createGuestStore } from './guest-store.mjs';
import { providerFunding } from "./provider-funding.mjs";
import { quoteCredits } from './public/credit-pricing.js';
import { createStreamingLedger } from "./streaming-ledger.mjs";
import { createDirectLedger } from "./direct-ledger.mjs";
import { createKeyLimits } from "./key-limits.mjs";
import { randomBytes, createHash, createHmac, randomUUID } from "node:crypto";
import { usageSummary, requestDevice } from './usage.mjs';
import { requireThat, integer, fundedMicros, withFee, credits, MICRO_USD_PER_CREDIT } from "./money.mjs";
export const hash = (value) => createHash("sha256").update(value).digest("hex");
export const defaults = Object.freeze({
  perRequest: null,
  accountDaily: null,
  globalDaily: null,
  globalLifetime: null,
  providerDaily: null,
  concurrency: 2,
  requestsPerMinute: 60,
});
export function createLedger(
  db,
  { mode = "demo", limits = defaults, now = () => Date.now(), enforceReconciliation = mode === "live", fundingReviewedAt = null } = {},
) {
  requireThat(["demo", "test", "live"].includes(mode), "config", "Invalid billing mode.");
  limits = { ...defaults, ...limits };
  for (const [name, value] of Object.entries(limits)) {
    if (["perRequest", "accountDaily", "globalDaily", "globalLifetime", "providerDaily"].includes(name) && value === null) continue;
    integer(value, 1, 1000000000000, name);
  }
  const tx = db.transaction || ((fn) => {
    db.exec("BEGIN IMMEDIATE");
    try {
      const value = fn();
      db.exec("COMMIT");
      return value;
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  });
  db.exec(`
    CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS withdrawals(id TEXT PRIMARY KEY,fingerprint TEXT NOT NULL,payload TEXT NOT NULL,created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, frozen INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS device_links(token_hash TEXT PRIMARY KEY, user_code TEXT UNIQUE NOT NULL, expires INTEGER NOT NULL, account TEXT REFERENCES accounts(id), key_id TEXT REFERENCES api_keys(id));
    CREATE TABLE IF NOT EXISTS api_keys(id TEXT PRIMARY KEY, hash TEXT UNIQUE NOT NULL, account TEXT NOT NULL REFERENCES accounts(id), suffix TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS ledger(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), amount INTEGER NOT NULL CHECK(typeof(amount)='integer'), kind TEXT NOT NULL, reference TEXT UNIQUE NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS balance_adjustments(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), target INTEGER NOT NULL, reason TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS checkout_orders(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), dedup TEXT NOT NULL, cents INTEGER NOT NULL, created INTEGER NOT NULL, session TEXT UNIQUE, url TEXT, UNIQUE(account,dedup));
    CREATE TABLE IF NOT EXISTS payments(session TEXT PRIMARY KEY, intent TEXT UNIQUE NOT NULL, account TEXT NOT NULL REFERENCES accounts(id), cents INTEGER NOT NULL, reversed INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS reversals(id TEXT PRIMARY KEY, intent TEXT NOT NULL, cents INTEGER NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('refund','dispute')), created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS dispute_states(id TEXT PRIMARY KEY REFERENCES reversals(id),status TEXT NOT NULL,updated INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS requests(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), key_id TEXT REFERENCES api_keys(id), dedup TEXT NOT NULL, fingerprint TEXT NOT NULL, body_hash TEXT, provider TEXT NOT NULL, model TEXT NOT NULL, operation TEXT, price_version TEXT NOT NULL, reserved INTEGER NOT NULL CHECK(reserved>0), expense_reserved INTEGER NOT NULL CHECK(expense_reserved>=reserved), fee_bps INTEGER NOT NULL DEFAULT 0, cost INTEGER, charged INTEGER, expense INTEGER, state TEXT NOT NULL CHECK(state IN ('reserved','submitted','uncertain','settled','released')), provider_id TEXT, result TEXT, result_expires INTEGER, created INTEGER NOT NULL, updated INTEGER NOT NULL, reconciled INTEGER NOT NULL DEFAULT 0, UNIQUE(account,dedup), UNIQUE(provider,provider_id));
    CREATE TABLE IF NOT EXISTS incidents(id TEXT PRIMARY KEY, request_id TEXT, reason TEXT NOT NULL, created INTEGER NOT NULL, resolved INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY, action TEXT NOT NULL, reference TEXT NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS provider_reports(provider TEXT PRIMARY KEY, through INTEGER NOT NULL, cost INTEGER NOT NULL, evidence TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS request_devices(request_id TEXT PRIMARY KEY REFERENCES requests(id), device_id TEXT NOT NULL, name TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS ledger_account_usage_time ON ledger(account,kind,created);
    CREATE INDEX IF NOT EXISTS requests_account_time ON requests(account,created);
    CREATE TABLE IF NOT EXISTS rate_limits(key TEXT PRIMARY KEY, count INTEGER NOT NULL, window INTEGER NOT NULL);
    CREATE TRIGGER IF NOT EXISTS ledger_no_update BEFORE UPDATE ON ledger BEGIN SELECT RAISE(ABORT,'Ledger entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS ledger_no_delete BEFORE DELETE ON ledger BEGIN SELECT RAISE(ABORT,'Ledger entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS audit_no_update BEFORE UPDATE ON audit BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS audit_no_delete BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END;`);
  if (!db.prepare('PRAGMA table_info(checkout_orders)').all().some(column => column.name === 'funding_rate')) {
    tx(() => {
      db.exec('ALTER TABLE checkout_orders ADD COLUMN funding_rate INTEGER NOT NULL DEFAULT 8000');
      db.prepare('UPDATE checkout_orders SET funding_rate=9000 WHERE created<?').run(Date.parse('2026-09-19T13:22:28.870Z'));
    });
  }
  if (!db.prepare('PRAGMA table_info(checkout_orders)').all().some(column => column.name === 'grant_micros')) {
    tx(() => {
      db.exec("ALTER TABLE checkout_orders ADD COLUMN grant_micros INTEGER; ALTER TABLE checkout_orders ADD COLUMN price_version TEXT NOT NULL DEFAULT 'legacy';");
      db.prepare('UPDATE checkout_orders SET grant_micros=cents*funding_rate').run();
    });
  }
  if (!db.prepare('PRAGMA table_info(requests)').all().some(column => column.name === 'operation')) {
    db.exec('ALTER TABLE requests ADD COLUMN operation TEXT');
  }
  if (!db.prepare('PRAGMA table_info(requests)').all().some(column => column.name === 'body_hash')) {
    db.exec('ALTER TABLE requests ADD COLUMN body_hash TEXT');
  }
  db.prepare("INSERT OR IGNORE INTO metadata VALUES('mode',?)").run(mode);
  requireThat(
    db.prepare("SELECT value FROM metadata WHERE key='mode'").get().value === mode,
    "config",
    "Cannot mix demo, test, and live funds in one database.",
  );
  db.prepare("INSERT OR IGNORE INTO metadata VALUES('paused','0')").run();
  if (!db.prepare('PRAGMA table_info(rate_limits)').all().some(column => column.name === 'expires')) {
    db.exec('ALTER TABLE rate_limits ADD COLUMN expires INTEGER');
  }
  db.exec('CREATE INDEX IF NOT EXISTS rate_limits_expiry ON rate_limits(expires); CREATE INDEX IF NOT EXISTS requests_result_expiry ON requests(result_expires) WHERE result IS NOT NULL;');
  db.prepare("INSERT OR IGNORE INTO metadata VALUES('rate_secret',?)").run(randomBytes(32).toString('hex'));
  const rateSecret = Buffer.from(db.prepare("SELECT value FROM metadata WHERE key='rate_secret'").get().value, 'hex');
  const guests = createGuestStore(db, tx, now);
  const keyBudgets = createKeyLimits(db, now);
  const one = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const balance = (account) =>
    one("SELECT COALESCE(SUM(amount),0) AS n FROM ledger WHERE account=?", account).n;
  const held = (account) =>
    one(
      "SELECT COALESCE(SUM(reserved),0) AS n FROM requests WHERE account=? AND state IN ('reserved','submitted','uncertain')",
      account,
    ).n + direct.held(account);
  const audit = (action, reference) =>
    run("INSERT INTO audit VALUES(?,?,?,?)", randomUUID(), action, reference, now());
  const entry = (account, amount, kind, reference) =>
    run(
      "INSERT INTO ledger VALUES(?,?,?,?,?,?)",
      randomUUID(),
      account,
      amount,
      kind,
      reference,
      now(),
    );
  const pause = (reason, id = null) => {
    run("UPDATE metadata SET value='1' WHERE key='paused'");
    run(
      "INSERT INTO incidents(id,request_id,reason,created) VALUES(?,?,?,?)",
      randomUUID(),
      id,
      reason,
      now(),
    );
    audit("pause", reason);
  };
  const accountExists = (id) =>
    requireThat(
      one("SELECT id FROM accounts WHERE id=?", id),
      "account",
      "Account not found.",
      404,
    );
  const disputedAccount = account => one(`SELECT COUNT(*) AS n FROM reversals r
    JOIN payments p ON p.intent=r.intent LEFT JOIN dispute_states d ON d.id=r.id
    WHERE p.account=? AND r.kind='dispute' AND COALESCE(d.status,'needs_response')
      IN ('needs_response','under_review','lost')`, account).n > 0;
  const refreshFreeze = account => run("UPDATE accounts SET frozen=? WHERE id=?",
    disputedAccount(account) || balance(account) < held(account) ? 1 : 0, account);
  function applyReversals(intent) {
    const p = one("SELECT * FROM payments WHERE intent=?", intent);
    if (!p) return;
    const rows = all("SELECT r.*,d.status FROM reversals r LEFT JOIN dispute_states d ON d.id=r.id WHERE r.intent=?", intent);
    const reversed = Math.min(p.cents, rows.reduce((sum, r) => sum +
      (r.kind === "refund" || ["needs_response", "under_review", "lost"].includes(r.status || "needs_response") ? r.cents : 0), 0));
    if (reversed !== p.reversed) {
      const purchase = one("SELECT amount FROM ledger WHERE reference=? AND kind='purchase' AND account=?", p.session, p.account);
      requireThat(purchase && Number.isSafeInteger(purchase.amount) && purchase.amount > 0,
        "payment_integrity", "Original purchase funding is unavailable.");
      entry(p.account, Math.floor(purchase.amount * p.reversed / p.cents) - Math.floor(purchase.amount * reversed / p.cents), "reversal", `reversal:${intent}:${randomUUID()}`);
      run("UPDATE payments SET reversed=? WHERE intent=?", reversed, intent);
    }
    refreshFreeze(p.account);
  }
  const streaming = createStreamingLedger(db, {now,tx,entry,audit,keyBudgets,balance,held,refreshFreeze});
  const direct = createDirectLedger(db, {now,tx,limits,keyBudgets,balance,held,audit,entry,pause,refreshFreeze});
  const api = {
    direct,
    streaming,
    mode,
    limits,
    claim() { db.claim?.(); },
    unclaim() { db.unclaim?.(); },
    purgeExpired() {
      return tx(() => {
        const time = now();
        streaming.purge();
        guests.purge();
        run('UPDATE requests SET result=NULL,result_expires=NULL WHERE result IS NOT NULL AND (result_expires IS NULL OR result_expires<=?)', time);
        run('DELETE FROM rate_limits WHERE expires IS NULL OR expires<=?', time);
        run('DELETE FROM sessions WHERE expires<=?', time);
        run('DELETE FROM device_links WHERE expires<=?', time);
        run(`DELETE FROM request_devices WHERE request_id IN (
          SELECT r.id FROM requests r WHERE r.state='released' OR
          (r.state='settled' AND 'usage:' || r.id <> COALESCE((
            SELECT l.reference FROM ledger l WHERE l.account=r.account AND l.kind='usage'
            ORDER BY l.created DESC,l.rowid DESC LIMIT 1
          ),'')))`);
      });
    },
    guests,
    identity(subject) {
      return tx(() => {
        const id = hash(subject);
        run("INSERT OR IGNORE INTO accounts VALUES(?,0,?)", id, now());
        return { id };
      });
    },
    createSession() {
      return tx(() => {
        const id = randomUUID(),
          token = randomBytes(32).toString("hex");
        run("INSERT INTO accounts VALUES(?,0,?)", id, now());
        run("INSERT INTO sessions VALUES(?,?,?)", hash(token), id, now() + 7 * 86400000);
        return { token, account: id };
      });
    },
    session(token) {
      return one(
        "SELECT a.* FROM sessions s JOIN accounts a ON a.id=s.account WHERE s.hash=? AND s.expires>?",
        hash(token),
        now(),
      );
    },
    startDevice(tokenHash, userCode) {
      run("INSERT INTO device_links(token_hash,user_code,expires) VALUES(?,?,?)", tokenHash, userCode, now() + 600000);
    },
    device(tokenHash) {
      const link = one("SELECT * FROM device_links WHERE token_hash=? AND expires>?", tokenHash, now());
      requireThat(link, "device_expired", "Connection expired. Start again from S2T.", 410);
      return link;
    },
    approveDevice(account, userCode, deriveKey) {
      requireThat(!guests.get(account), "guest_key", "Use your prepaid key to connect S2T.", 403);
      return tx(() => {
        accountExists(account);
        requireThat(!one("SELECT frozen FROM accounts WHERE id=?", account).frozen, "frozen", "Account is frozen.");
        const link = one("SELECT * FROM device_links WHERE user_code=? AND expires>?", userCode, now());
        requireThat(link, "device_expired", "Connection expired. Start again from S2T.", 410);
        if (link.account) {
          requireThat(link.account === account, "device_used", "This connection has already been approved by another account.", 409);
          return;
        }
        requireThat(one("SELECT count(*) AS n FROM api_keys WHERE account=? AND revoked=0 AND expires>?", account, now()).n < 10, "keys", "Revoke an old app key before connecting another app.");
        const key = deriveKey(link.token_hash), id = randomUUID();
        run("INSERT INTO api_keys VALUES(?,?,?,?,0,?)", id, hash(key), account, key.slice(-6), now() + 90 * 86400000);
        run("UPDATE device_links SET account=?, key_id=? WHERE token_hash=?", account, id, link.token_hash);
        audit("device_connected", id);
      });
    },
    issueKey(account, options = {}) {
      requireThat(!guests.get(account), "guest_key", "Prepaid purchases have one key.", 403);
      return tx(() => {
        accountExists(account);
        requireThat(
          one("SELECT frozen FROM accounts WHERE id=?", account).frozen === 0,
          "frozen",
          "Account is frozen.",
        );
        requireThat(
          one("SELECT count(*) AS n FROM api_keys WHERE account=? AND revoked=0 AND expires>?", account, now()).n < 10,
          "keys",
          "Revoke a key before creating another.",
        );
        const key = `s2t_${mode}_` + randomBytes(32).toString("hex"),
          id = randomUUID();
        run(
          "INSERT INTO api_keys VALUES(?,?,?,?,0,?)",
          id,
          hash(key),
          account,
          key.slice(-6),
          now() + 90 * 86400000,
        );
        const limits = keyBudgets.configure(account, id, options);
        audit("key_issued", id);
        return { id, key, limits };
      });
    },
    keyLimits(account, id) { return keyBudgets.read(account, id); },
    setKeyLimits(account, id, options) {
      return tx(() => {
        const limits = keyBudgets.configure(account, id, options);
        audit("key_limits_updated", id);
        return limits;
      });
    },
    authenticate(key) {
      return one(
        "SELECT * FROM api_keys WHERE hash=? AND revoked=0 AND expires>?",
        hash(key),
        now(),
      );
    },
    revoke(account, id) {
      return tx(() => {
        requireThat(
          run("UPDATE api_keys SET revoked=1 WHERE account=? AND id=?", account, id).changes === 1,
          "key",
          "Key not found.",
          404,
        );
        audit("key_revoked", id);
      });
    },
    submitWithdrawal(id, fingerprint, payload) {
      return tx(() => {
        const existing=one('SELECT * FROM withdrawals WHERE id=?',id);
        requireThat(!existing || existing.fingerprint===fingerprint,'withdrawal_conflict','Submission identifier already used for another declaration.',409);
        if(existing) return existing;
        run('INSERT INTO withdrawals VALUES(?,?,?,?)',id,fingerprint,payload,now());
        audit('withdrawal_received',id);
        return one('SELECT * FROM withdrawals WHERE id=?',id);
      });
    },
    withdrawals() { return all('SELECT * FROM withdrawals ORDER BY created DESC LIMIT 100'); },
    checkoutOrder(account, cents, dedup) {
      integer(cents, 100, 10000, "Top-up");
      requireThat(typeof dedup === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(dedup), "idempotency", "Provide a stable purchase identifier.");
      return tx(() => {
        accountExists(account);
        requireThat(!disputedAccount(account), "frozen", "Account is frozen.");
        const existing = one("SELECT * FROM checkout_orders WHERE account=? AND dedup=?", account, dedup);
        if (existing) {
          requireThat(existing.cents === cents, "checkout_conflict", "Purchase amount changed. Start a new checkout.");
          requireThat(existing.session || existing.created > now() - 23 * 3600000, "checkout_expired", "This checkout attempt expired. Reload and start a new purchase.");
          return existing;
        }
        integer(cents, 500, 10000, "Top-up");
        const id = randomUUID();
        const quote = quoteCredits(cents);
        run("INSERT INTO checkout_orders(id,account,dedup,cents,created,funding_rate,grant_micros,price_version) VALUES(?,?,?,?,?,?,?,?)", id, account, dedup, cents, now(), MICRO_USD_PER_CREDIT, quote.grantMicros, quote.version);
        return one("SELECT * FROM checkout_orders WHERE id=?", id);
      });
    },
    attachCheckout(id, session, url = null) {
      return tx(() => {
        const order = one("SELECT * FROM checkout_orders WHERE id=?", id);
        requireThat(order && (!order.session || order.session === session), "checkout_conflict", "Checkout session changed.");
        run("UPDATE checkout_orders SET session=?, url=COALESCE(?,url) WHERE id=?", session, url, id);
      });
    },
    verifyCheckout(id, account, cents, session) {
      const order = one("SELECT * FROM checkout_orders WHERE id=?", id);
      requireThat(order && order.account === account && order.cents === cents && (!order.session || order.session === session), "checkout_order", "Payment does not match an S2T purchase.");
      this.attachCheckout(id, session);
    },
    grant({ account, cents, session, intent }) {
      fundedMicros(cents);
      return tx(() => {
        accountExists(account);
        const existing = one("SELECT * FROM payments WHERE session=? OR intent=?", session, intent);
        if (existing) {
          requireThat(
            existing.session === session &&
              existing.intent === intent &&
              existing.account === account &&
              existing.cents === cents,
            "payment_conflict",
            "Payment identity conflict.",
          );
          return false;
        }
        const order = one("SELECT account,cents,funding_rate,grant_micros FROM checkout_orders WHERE session=?", session);
        requireThat(!order || (order.account === account && order.cents === cents), "payment_conflict", "Payment does not match its checkout.");
        const fundingRate = order?.funding_rate ?? MICRO_USD_PER_CREDIT;
        requireThat([5000, 8000, 9000].includes(fundingRate), "payment_integrity", "Checkout funding rate is invalid.");
        const grantMicros = order?.grant_micros ?? cents * fundingRate;
        integer(grantMicros, 1, cents * 10000, 'Checkout credit grant');
        run("INSERT INTO payments VALUES(?,?,?,?,0,?)", session, intent, account, cents, now());
        entry(account, grantMicros, "purchase", session);
        applyReversals(intent);
        audit("payment", session);
        return true;
      });
    },
    dispute({ id, intent, cents, status }) {
      integer(cents, 1, 10000000, "Disputed amount");
      requireThat(typeof id === "string" && id.length > 0 && typeof intent === "string" && intent.length > 0,
        "dispute", "Dispute identity is missing.");
      requireThat(["needs_response", "under_review", "won", "lost", "warning_needs_response", "warning_under_review", "warning_closed"].includes(status), "dispute", "Unexpected dispute status.");
      return tx(() => {
        const previous = one("SELECT r.*,d.status FROM reversals r LEFT JOIN dispute_states d ON d.id=r.id WHERE r.id=?", id);
        requireThat(!previous || (previous.intent === intent && previous.kind === "dispute"), "reversal_conflict", "Dispute identity conflict.");
        if (previous && ["won", "lost"].includes(previous.status)) {
          requireThat(!["won", "lost"].includes(status) || status === previous.status, "reversal_conflict", "Dispute terminal status changed.");
          return false;
        }
        if (previous?.status === status && previous.cents === cents) return false;
        if (previous) run("UPDATE reversals SET cents=? WHERE id=?", cents, id);
        else run("INSERT INTO reversals VALUES(?,?,?,'dispute',?)", id, intent, cents, now());
        run("INSERT INTO dispute_states VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,updated=excluded.updated", id, status, now());
        applyReversals(intent);
        audit("dispute", `${id}:${status}`);
        return true;
      });
    },
    reverse({ id, intent, cents, kind }) {
      integer(cents, 1, 10000000, "Reversal");
      requireThat(["refund", "dispute"].includes(kind), "reversal", "Invalid reversal.");
      if (kind === "dispute") return api.dispute({ id, intent, cents, status: "needs_response" });
      return tx(() => {
        const old = one("SELECT * FROM reversals WHERE id=?", id);
        if (old)
          requireThat(
            old.intent === intent && old.cents === cents && old.kind === kind,
            "reversal_conflict",
            "Reversal identity conflict.",
          );
        else run("INSERT INTO reversals VALUES(?,?,?,?,?)", id, intent, cents, kind, now());
        applyReversals(intent);
        audit("reversal", id);
      });
    },
    rate(key, limit, windowMs = 60000) {
      return tx(() => {
        const window = Math.floor(now() / windowMs);
        const identifier = createHmac('sha256', rateSecret).update(JSON.stringify([key, windowMs, window])).digest('hex');
        const admitted = one(
          "INSERT INTO rate_limits(key,count,window,expires) VALUES(?,1,?,?) ON CONFLICT(key) DO UPDATE SET count=count+1 WHERE count<? RETURNING count",
          identifier,
          window,
          (window + 1) * windowMs,
          limit,
        );
        return !!admitted;
      });
    },
    reserve({
      account,
      keyId = null,
      device = null,
      dedup,
      fingerprint,
      bodyHash = null,
      provider,
      model,
      operation = null,
      priceVersion,
      maxCost,
      feeBps = 0,
      streamingSeconds = null,
    }) {
      if (device) device = requestDevice(device.id, device.name);
      integer(maxCost, 1, limits.perRequest ?? 1000000000000, "Maximum request cost");
      integer(feeBps, 0, 10000, "Provider funding fee");
      let maxExpense = withFee(maxCost, feeBps);
      requireThat(
        limits.perRequest === null || maxExpense <= limits.perRequest,
        "request_limit",
        "Request including provider fees exceeds the spending ceiling.",
      );
      return tx(() => {
        accountExists(account);
        if (keyId)
          requireThat(
            one(
              "SELECT id FROM api_keys WHERE id=? AND account=? AND revoked=0 AND expires>?",
              keyId,
              account,
              now(),
            ),
            "key",
            "API key is invalid.",
            401,
          );
        const prior = one("SELECT * FROM requests WHERE account=? AND dedup=?", account, dedup);
        if (prior) {
          requireThat(
            prior.fingerprint === fingerprint && (prior.body_hash === null || prior.body_hash === bodyHash),
            "idempotency_conflict",
            "This request ID was already used for different input.",
          );
          return { request: prior, created: false };
        }
        if (fundingReviewedAt !== null)
          requireThat(Number.isSafeInteger(fundingReviewedAt) && fundingReviewedAt <= now() && fundingReviewedAt >= now() - 86400000,
            "funding_review_expired", "Provider funding evidence is more than 24 hours old. New spending is paused until an operator independently reviews funding and limits.", 503);
        if (enforceReconciliation) {
          const overdue = one(`SELECT r.id FROM requests r WHERE r.state='settled' AND r.cost IS NOT NULL
            AND r.created<=? AND (r.reconciled=0 OR NOT EXISTS(
              SELECT 1 FROM provider_reports p WHERE p.provider=r.provider AND p.through>=r.created)) LIMIT 1`, now() - 86400000);
          requireThat(!overdue, "reconciliation_overdue", "Independent provider receipt and account-total reconciliation is overdue. New spending is paused until an operator completes it.", 503);
        }
        if (streamingSeconds !== null) {
          requireThat(provider === "assemblyai" && model === "universal-3-5-pro" && feeBps === 0 && maxCost === streamingSeconds * 125 && keyId, "streaming_input", "Invalid streaming authorization.");
          keyBudgets.check(account, keyId, 1);
          const remaining = keyBudgets.read(account, keyId).remainingCredits;
          maxCost = Math.min(maxCost, balance(account) - held(account), remaining === null ? maxCost : Math.round(remaining * MICRO_USD_PER_CREDIT));
          requireThat(maxCost >= 60 * 125, "insufficient_credits", "At least 60 seconds of credits are required for a streaming authorization.", 402);
          streamingSeconds = Math.max(60, Math.min(streamingSeconds, Math.floor(maxCost / 125)));
          maxExpense = streamingSeconds * 300;
          requireThat(limits.perRequest === null || maxExpense <= limits.perRequest, "request_limit", "Request exceeds the spending limit.");
          streaming.validateReservation(account, streamingSeconds);
        }
        if (keyId) keyBudgets.check(account, keyId, maxCost);
        requireThat(
          one("SELECT value FROM metadata WHERE key='paused'").value === "0",
          "paused",
          "New requests are paused.",
        );
        requireThat(
          !one("SELECT frozen FROM accounts WHERE id=?", account).frozen,
          "frozen",
          "Account is frozen.",
        );
        requireThat(
          balance(account) - held(account) >= maxCost,
          "insufficient_credits",
          "Not enough available credits.",
          402,
        );
        if (streamingSeconds === null) requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests WHERE account=? AND state IN ('reserved','submitted') AND id NOT IN (SELECT request_id FROM streaming_sessions)",
            account,
          ).n < limits.concurrency,
          "concurrency",
          "Too many pending requests.",
          429,
        );
        requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests WHERE account=? AND created>?",
            account,
            now() - 60000,
          ).n < limits.requestsPerMinute,
          "rate_limit",
          "Request limit reached.",
          429,
        );
        const day = Math.floor(now() / 86400000) * 86400000;
        const spend = (where, ...args) =>
          one(
            `SELECT COALESCE(SUM(CASE WHEN state IN ('reserved','submitted','uncertain') THEN expense_reserved WHEN state='settled' THEN expense ELSE 0 END),0) AS n FROM requests WHERE ${where}`,
            ...args,
          ).n;
        const daily = `(updated>=? OR state IN ('reserved','submitted','uncertain') OR id IN (SELECT request_id FROM streaming_sessions WHERE window_end>${now()}))`;
        requireThat(
          limits.globalLifetime === null || spend("1=1") + direct.exposure() + maxExpense <= limits.globalLifetime,
          "global_limit",
          "Service spending limit reached.",
        );
        requireThat(
          limits.globalDaily === null || spend(daily, day) + direct.exposure({since:day}) + maxExpense <= limits.globalDaily,
          "daily_limit",
          "Service daily limit reached.",
        );
        requireThat(
          limits.accountDaily === null || spend(`account=? AND ${daily}`, account, day) + direct.exposure({account,since:day}) + maxExpense <= limits.accountDaily,
          "account_limit",
          "Account daily limit reached.",
        );
        requireThat(
          limits.providerDaily === null || spend(`provider=? AND ${daily}`, provider, day) + direct.exposure({provider,since:day}) + maxExpense <= limits.providerDaily,
          "provider_limit",
          "Provider daily limit reached.",
        );
        const id = randomUUID();
        run(
          "INSERT INTO requests(id,account,key_id,dedup,fingerprint,body_hash,provider,model,operation,price_version,reserved,expense_reserved,fee_bps,state,created,updated) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'reserved',?,?)",
          id,
          account,
          keyId,
          dedup,
          fingerprint,
          bodyHash,
          provider,
          model,
          operation,
          priceVersion,
          maxCost,
          maxExpense,
          feeBps,
          now(),
          now(),
        );
        if (device) run('INSERT INTO request_devices VALUES(?,?,?)', id, device.id, device.name);
        if (streamingSeconds !== null) streaming.reserve(id, streamingSeconds);
        audit("reserve", id);
        return { request: one("SELECT * FROM requests WHERE id=?", id), created: true };
      });
    },
    submit(id) {
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        requireThat(r?.state === "reserved", "state", "Request cannot be submitted.");
        requireThat(
          one("SELECT value FROM metadata WHERE key='paused'").value === "0",
          "paused",
          "New requests are paused.",
        );
        requireThat(
          !one("SELECT frozen FROM accounts WHERE id=?", r.account).frozen,
          "frozen",
          "Account is frozen.",
        );
        if (r.key_id)
          requireThat(
            one("SELECT id FROM api_keys WHERE id=? AND revoked=0 AND expires>?", r.key_id, now()),
            "key",
            "API key has been revoked.",
            401,
          );
        if (r.key_id) keyBudgets.check(r.account, r.key_id);
        run("UPDATE requests SET state='submitted',updated=? WHERE id=?", now(), id);
        audit("submit", id);
      });
    },
    cancel(account, id) {
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=? AND account=?", id, account);
        requireThat(r, "request", "Request not found.", 404);
        if (r.state === "reserved") {
          run("UPDATE requests SET state='released',updated=? WHERE id=?", now(), id);
          refreshFreeze(account);
          audit("cancel_before_submit", id);
        }
        return one("SELECT * FROM requests WHERE id=?", id);
      });
    },
    reject(id, result) {
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        requireThat(r && r.state === "submitted" && r.cost === null && r.provider_id === null, "state", "Only a definitively rejected submission can be released.");
        run("UPDATE requests SET state='released',result=?,result_expires=?,updated=? WHERE id=?", result, now() + 15 * 60 * 1000, now(), id);
        refreshFreeze(r.account);
        audit("provider_rejected", id);
      });
    },
    uncertain(id, reason, providerId = null, { pauseSpending = true } = {}) {
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        if (!r || !["submitted", "uncertain"].includes(r.state)) return;
        run("UPDATE requests SET state='uncertain',updated=? WHERE id=?", now(), id);
        if (
          providerId &&
          !one(
            "SELECT id FROM requests WHERE provider=? AND provider_id=? AND id<>?",
            r.provider,
            providerId,
            id,
          )
        )
          run("UPDATE requests SET provider_id=? WHERE id=?", providerId, id);
        if (pauseSpending) pause(reason, id);
        else audit("provider_outcome_unknown", `${id}:${reason}`);
      });
    },
    settle(id, { cost, providerId, result = null }, { reconciliation = false } = {}) {
      integer(cost, 0, 1000000000000, "Provider cost");
      requireThat(
        typeof providerId === "string" && providerId.length > 0 && providerId.length <= 200,
        "receipt",
        "Provider receipt ID is missing.",
      );
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        requireThat(r, "request", "Request not found.", 404);
        if (r.state === "settled") {
          if (r.cost !== cost || r.provider_id !== providerId) {
            pause("Receipt changed after settlement", id);
            return false;
          }
          return true;
        }
        requireThat(
          ["submitted", "uncertain"].includes(r.state),
          "state",
          "Unsubmitted request cannot be charged.",
        );
        if (
          (r.provider_id && r.provider_id !== providerId) ||
          one(
            "SELECT id FROM requests WHERE provider=? AND provider_id=? AND id<>?",
            r.provider,
            providerId,
            id,
          )
        ) {
          pause("Provider receipt identity conflict", id);
          return false;
        }
        const expense = withFee(cost, r.fee_bps);
        if ((cost > r.reserved || expense > r.expense_reserved) && !reconciliation) {
          run(
            "UPDATE requests SET state='uncertain',cost=?,expense=?,provider_id=?,updated=? WHERE id=?",
            cost,
            expense,
            providerId,
            now(),
            id,
          );
          pause("Provider exceeded the reserved maximum", id);
          return false;
        }
        const charged = Math.min(cost, r.reserved);
        entry(r.account, -charged, "usage", `usage:${id}`);
        if (cost > r.reserved || expense > r.expense_reserved)
          pause(
            "Provider overrun absorbed; review pricing before resuming",
            "pricing:" + r.price_version,
          );
        run(
          "UPDATE requests SET state='settled',cost=?,charged=?,expense=?,provider_id=?,result=?,result_expires=?,updated=?,reconciled=? WHERE id=?",
          cost,
          charged,
          expense,
          providerId,
          result,
          now() + 3600000,
          now(),
          reconciliation ? 1 : 0,
          id,
        );
        refreshFreeze(r.account);
        audit(reconciliation ? "reconciled_settlement" : "settle", id);
        return true;
      });
    },
    reconcile(id, { cost, providerId, evidence }) {
      requireThat(
        typeof evidence === "string" && /^[a-f0-9]{64}$/.test(evidence),
        "evidence",
        "A SHA-256 digest of independent provider evidence is required.",
      );
      const r = one("SELECT * FROM requests WHERE id=?", id);
      requireThat(r, "request", "Request not found.", 404);
      const historicalStreaming = one("SELECT token_expires FROM streaming_sessions WHERE request_id=?", id);
      if (r.state === "settled" && historicalStreaming?.token_expires !== null && historicalStreaming?.token_expires !== undefined &&
          (r.provider_id === `streaming-client:${id}` || (r.charged === 0 && r.provider_id === null))) {
        integer(cost, 0, 1000000000000, "Provider cost");
        requireThat(typeof providerId === "string" && providerId.length > 0 && providerId.length <= 200 && providerId !== `streaming-client:${id}`,
          "receipt", "An independent provider receipt ID is required.");
        return tx(() => {
          const current = one("SELECT state,charged,provider_id FROM requests WHERE id=?", id);
          requireThat(current?.state === r.state && current.charged === r.charged && current.provider_id === r.provider_id,
            "reconciliation_state", "Historical streaming row changed during reconciliation.");
          if (one("SELECT id FROM requests WHERE provider=? AND provider_id=? AND id<>?", r.provider, providerId, id)) {
            pause("Provider receipt identity conflict", id);
            return false;
          }
          const expense = withFee(cost, r.fee_bps);
          const charged = Math.min(r.charged, cost);
          if (charged < r.charged) entry(r.account, r.charged - charged, "usage_correction", `usage-correction:${id}`);
          run("UPDATE requests SET cost=?,charged=?,expense=?,provider_id=?,reconciled=1,updated=? WHERE id=?", cost, charged, expense, providerId, now(), id);
          run("UPDATE incidents SET resolved=1 WHERE request_id=?", id);
          audit("historical_streaming_writeoff", `${id}:${evidence}`);
          refreshFreeze(r.account);
          if (cost > r.reserved || expense > r.expense_reserved)
            pause("Historical streaming provider cost exceeded its reservation", id);
          return true;
        });
      }
      if (r.state === "settled")
        return tx(() => {
          if (r.cost !== cost || r.provider_id !== providerId) {
            pause("Provider report does not match ledger", id);
            return false;
          }
          run("UPDATE requests SET reconciled=1 WHERE id=?", id);
          run("UPDATE incidents SET resolved=1 WHERE request_id=?", id);
          audit("provider_evidence", `${id}:${evidence}`);
          return true;
        });
      const ok = api.settle(id, { cost, providerId }, { reconciliation: true });
      if (ok)
        tx(() => {
          run("UPDATE incidents SET resolved=1 WHERE request_id=?", id);
          audit("provider_evidence", `${id}:${evidence}`);
        });
      return ok;
    },
    reopenReconciliation(id, reason) {
      requireThat(typeof reason === "string" && reason.length >= 20 && reason.length <= 500, "reconciliation_reason", "Record why the previous reconciliation is unsupported.");
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        requireThat(r && r.state === "settled" && r.cost !== null, "reconciliation_state", "Only a settled provider receipt can be reopened.");
        if (!r.reconciled) return false;
        run("UPDATE requests SET reconciled=0 WHERE id=?", id);
        audit("reconciliation_reopened", `${id}:${reason}`);
        return true;
      });
    },
    reconcileReport({ provider, through, totalCostMicros, evidence }) {
      integer(totalCostMicros, 0, 1000000000000, "Report cost");
      requireThat(
        ["openrouter", "assemblyai", "xai"].includes(provider) &&
          Number.isSafeInteger(through) &&
          through <= now() &&
          /^[a-f0-9]{64}$/.test(evidence),
        "report",
        "Invalid provider report.",
      );
      return tx(() => {
        const old = one("SELECT through FROM provider_reports WHERE provider=?", provider);
        requireThat(
          !old || through >= old.through,
          "report",
          "Provider report is older than the last reconciliation.",
        );
        requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests WHERE provider=? AND created<=? AND state IN ('reserved','submitted','uncertain')",
            provider,
            through,
          ).n === 0,
          "report",
          "Resolve pending requests before reconciling this period.",
        );
        const expected = one(
          "SELECT COALESCE(SUM(cost),0) AS n FROM requests WHERE provider=? AND created<=? AND state='settled'",
          provider,
          through,
        ).n;
        if (expected !== totalCostMicros) {
          pause("Provider account total differs from recorded usage", "provider:" + provider);
          return false;
        }
        run(
          "INSERT INTO provider_reports VALUES(?,?,?,?) ON CONFLICT(provider) DO UPDATE SET through=excluded.through,cost=excluded.cost,evidence=excluded.evidence",
          provider,
          through,
          totalCostMicros,
          evidence,
        );
        run("UPDATE incidents SET resolved=1 WHERE request_id=?", "provider:" + provider);
        audit("provider_total", `${provider}:${evidence}`);
        return true;
      });
    },
    recover() {
      return tx(() => {
        run("UPDATE requests SET state='released',updated=? WHERE state='reserved' AND id NOT IN (SELECT request_id FROM streaming_sessions)", now());
        const pending = all("SELECT id FROM requests WHERE state='submitted' AND id NOT IN (SELECT request_id FROM streaming_sessions)");
        for (const r of pending) {
          run("UPDATE requests SET state='uncertain',updated=? WHERE id=?", now(), r.id);
          audit("provider_outcome_unknown", `${r.id}:Process stopped with an in-flight provider request`);
        }
        for (const account of all("SELECT id FROM accounts WHERE frozen=1")) refreshFreeze(account.id);
        return pending.length;
      });
    },
    pause(reason = "Operator stop") {
      return tx(() => pause(reason));
    },
    reviewPricing(version) {
      requireThat(
        typeof version === "string" && version.length > 0,
        "pricing",
        "A reviewed pricing version is required.",
      );
      return tx(() => {
        const old = all(
          "SELECT DISTINCT request_id FROM incidents WHERE resolved=0 AND request_id LIKE 'pricing:%'",
        );
        requireThat(
          old.every((row) => row.request_id !== "pricing:" + version),
          "pricing",
          "Change the pricing version after reviewing the overrun.",
        );
        run("UPDATE incidents SET resolved=1 WHERE request_id LIKE 'pricing:%'");
        audit("pricing_review", version);
      });
    },
    writeOff(id, reason) {
      requireThat(typeof reason === "string" && reason.length >= 20 && reason.length <= 500, "writeoff_reason", "Record why S2T is absorbing this unknown charge.");
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        if (r?.state === "settled" && r.cost === null && r.charged === 0) return false;
        requireThat(r && r.state === "uncertain" && r.cost === null, "writeoff_state", "Only an unresolved, uncharged request can be written off.");
        run("UPDATE requests SET state='settled',charged=0,expense=expense_reserved,reconciled=1,updated=? WHERE id=?", now(), id);
        run("UPDATE incidents SET resolved=1 WHERE request_id=?", id);
        refreshFreeze(r.account);
        audit("operator_writeoff", `${id}:${reason}`);
        return true;
      });
    },
    confirmWriteOff(id) {
      return tx(() => {
        const r = one("SELECT * FROM requests WHERE id=?", id);
        requireThat(r && r.state === "settled" && r.charged === 0 && r.cost === null, "writeoff_state", "Only an operator writeoff can be confirmed.");
        run("UPDATE requests SET reconciled=1,updated=? WHERE id=?", now(), id);
        run("UPDATE incidents SET resolved=1 WHERE request_id=?", id);
        audit("operator_writeoff_confirmed", id);
        return true;
      });
    },
    resume() {
      return tx(() => {
        requireThat(
          one("SELECT COUNT(*) AS n FROM requests WHERE state='uncertain'").n === 0,
          "unresolved",
          "Resolve uncertain requests before resuming.",
        );
        requireThat(
          one("SELECT COUNT(*) AS n FROM incidents WHERE resolved=0 AND request_id IS NOT NULL")
            .n === 0,
          "unresolved",
          "Unresolved billing incidents prevent resuming.",
        );
        run("UPDATE incidents SET resolved=1 WHERE request_id IS NULL");
        run("UPDATE metadata SET value='0' WHERE key='paused'");
        audit("resume", "operator");
      });
    },
    request(account, id) {
      return one("SELECT * FROM requests WHERE account=? AND id=?", account, id);
    },
    replay({account,keyId=null,dedup,bodyHash,legacyFingerprint,bodyProvider=null,legacyAudioProvided=false}) {
      return tx(() => {
        accountExists(account);
        if (keyId) requireThat(one("SELECT id FROM api_keys WHERE id=? AND account=? AND revoked=0 AND expires>?",keyId,account,now()),
          "key", "API key is invalid.", 401);
        const prior=one("SELECT * FROM requests WHERE account=? AND dedup=?",account,dedup);
        if (!prior) return null;
        if (prior.body_hash !== null) {
          requireThat(prior.body_hash === bodyHash,"idempotency_conflict","This request ID was already used for different input.");
          return prior;
        }
        if (legacyFingerprint !== null) {
          requireThat(prior.fingerprint === legacyFingerprint,"idempotency_conflict","This request ID was already used for different input.");
          return prior;
        }
        if (prior.operation === 'transcription' || (prior.operation === null && prior.provider === bodyProvider && legacyAudioProvided))
          requireThat(false,"idempotency_conflict","This request ID was already used for different input.");
        return null;
      });
    },
    setBalance({ account, targetCredits, id, reason }) {
      const target = integer(targetCredits, 0, 10000, "Target credits") * MICRO_USD_PER_CREDIT;
      requireThat(typeof id === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(id), "adjustment_id", "Provide a unique adjustment identifier.");
      requireThat(typeof reason === "string" && reason.length >= 20 && reason.length <= 500, "adjustment_reason", "Record why the balance is being adjusted.");
      return tx(() => {
        accountExists(account);
        const previous = one("SELECT * FROM balance_adjustments WHERE id=?", id);
        if (previous) {
          requireThat(previous.account === account && previous.target === target && previous.reason === reason, "adjustment_conflict", "Adjustment identifier was already used for a different change.", 409);
          return { applied: false, balance: credits(balance(account)) };
        }
        requireThat(!one("SELECT frozen FROM accounts WHERE id=?", account).frozen, "frozen", "Account is frozen.");
        requireThat(held(account) === 0, "pending", "Resolve pending requests before adjusting the balance.");
        const before = balance(account);
        run("INSERT INTO balance_adjustments VALUES(?,?,?,?)", id, account, target, reason);
        entry(account, target - before, "adjustment", `balance-adjustment:${id}`);
        audit("balance_adjustment", JSON.stringify({ id, account, before, target, reason }));
        return { applied: true, previousBalance: credits(before), balance: credits(target) };
      });
    },
    usage(account, days = 30) {
      accountExists(account);
      return usageSummary(db, account, days, now());
    },
    summary(account) {
      accountExists(account);
      const b = balance(account),
        h = held(account);
      return {
        balance: credits(b),
        available: credits(b - h),
        reserved: credits(h),
        frozen: !!one("SELECT frozen FROM accounts WHERE id=?", account).frozen,
        paused: one("SELECT value FROM metadata WHERE key='paused'").value === "1",
        purchases: all(
          "SELECT p.session AS id,p.cents,p.created,p.reversed,l.amount AS grantMicros FROM payments p JOIN ledger l ON l.reference=p.session AND l.kind='purchase' AND l.account=p.account WHERE p.account=? ORDER BY p.created DESC LIMIT 20",
          account,
        ).map(p => ({ ...p, grantedCredits: credits(p.grantMicros), netCredits: credits(p.grantMicros - Math.floor(p.grantMicros * p.reversed / p.cents)) })),
        keys: all(
          "SELECT id,suffix,revoked,expires FROM api_keys WHERE account=? ORDER BY rowid",
          account,
        ).map(key => ({ ...key, limits: keyBudgets.read(account, key.id) })),
        requests: all(
          "SELECT id,provider,model,operation,state,reserved,cost,charged,created FROM requests WHERE account=? ORDER BY created DESC LIMIT 20",
          account,
        ),
      };
    },
    funding() {
      const totals = one(`SELECT COALESCE(SUM((p.cents-p.reversed)*10000),0) AS gross,
        COALESCE(SUM(l.amount-CAST(l.amount*p.reversed/p.cents AS INTEGER)),0) AS providers
        FROM payments p JOIN ledger l ON l.reference=p.session AND l.kind='purchase' AND l.account=p.account`);
      const consumed = one(`WITH paid AS (
        SELECT p.account, SUM(l.amount-CAST(l.amount*p.reversed/p.cents AS INTEGER)) AS principal
        FROM payments p JOIN ledger l ON l.reference=p.session AND l.kind='purchase' AND l.account=p.account
        GROUP BY p.account
      ), wallets AS (
        SELECT account, SUM(amount) AS balance,
          -SUM(CASE WHEN kind='usage' THEN amount ELSE 0 END) AS used FROM ledger GROUP BY account
      ) SELECT COALESCE(SUM(MAX(0,MIN(paid.principal,wallets.used,paid.principal-wallets.balance))),0) AS n
        FROM paid JOIN wallets ON wallets.account=paid.account`).n;
      return providerFunding(totals.gross, totals.providers, consumed);
    },
    health() {
      return {
        mode,
        paused: one("SELECT value FROM metadata WHERE key='paused'").value === "1",
        limits,
        incidents: all("SELECT * FROM incidents WHERE resolved=0"),
        pending: all(
          `SELECT r.id,r.provider,r.provider_id,r.state,r.reserved,r.cost,r.created,
            (SELECT substr(a.reference,length(r.id)+2) FROM audit a
             WHERE a.action='provider_outcome_unknown' AND a.reference LIKE r.id || ':%'
             ORDER BY a.created DESC,a.rowid DESC LIMIT 1) AS reason
           FROM requests r WHERE r.state IN ('submitted','uncertain')`,
        ),
        unreconciled: all(
          "SELECT id,provider,provider_id,cost FROM requests WHERE state='settled' AND reconciled=0",
        ),
        expense: one(
          "SELECT COALESCE(SUM(CASE WHEN state='settled' THEN expense ELSE 0 END),0) AS n FROM requests",
        ).n,
      };
    },
    close() {
      db.close();
    },
  };
  return api;
}
