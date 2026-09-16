import { randomBytes, createHash, randomUUID } from "node:crypto";
import { requireThat, integer, fundedMicros, withFee, credits } from "./money.mjs";
export const hash = (value) => createHash("sha256").update(value).digest("hex");
export const defaults = Object.freeze({
  perRequest: 250000,
  accountDaily: 1000000,
  globalDaily: 5000000,
  globalLifetime: 20000000,
  providerDaily: 3000000,
  concurrency: 2,
  requestsPerMinute: 20,
});
export function createLedger(
  db,
  { mode = "demo", limits = defaults, now = () => Date.now() } = {},
) {
  requireThat(["demo", "test", "live"].includes(mode), "config", "Invalid billing mode.");
  limits = { ...defaults, ...limits };
  for (const [name, value] of Object.entries(limits)) integer(value, 1, 1000000000000, name);
  db.exec(`
    CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, frozen INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS device_links(token_hash TEXT PRIMARY KEY, user_code TEXT UNIQUE NOT NULL, expires INTEGER NOT NULL, account TEXT REFERENCES accounts(id), key_id TEXT REFERENCES api_keys(id));
    CREATE TABLE IF NOT EXISTS api_keys(id TEXT PRIMARY KEY, hash TEXT UNIQUE NOT NULL, account TEXT NOT NULL REFERENCES accounts(id), suffix TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS ledger(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), amount INTEGER NOT NULL CHECK(typeof(amount)='integer'), kind TEXT NOT NULL, reference TEXT UNIQUE NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS checkout_orders(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), dedup TEXT NOT NULL, cents INTEGER NOT NULL, created INTEGER NOT NULL, session TEXT UNIQUE, url TEXT, UNIQUE(account,dedup));
    CREATE TABLE IF NOT EXISTS payments(session TEXT PRIMARY KEY, intent TEXT UNIQUE NOT NULL, account TEXT NOT NULL REFERENCES accounts(id), cents INTEGER NOT NULL, reversed INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS reversals(id TEXT PRIMARY KEY, intent TEXT NOT NULL, cents INTEGER NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('refund','dispute')), created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS requests(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id), key_id TEXT REFERENCES api_keys(id), dedup TEXT NOT NULL, fingerprint TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL, price_version TEXT NOT NULL, reserved INTEGER NOT NULL CHECK(reserved>0), expense_reserved INTEGER NOT NULL CHECK(expense_reserved>=reserved), fee_bps INTEGER NOT NULL DEFAULT 0, cost INTEGER, charged INTEGER, expense INTEGER, state TEXT NOT NULL CHECK(state IN ('reserved','submitted','uncertain','settled','released')), provider_id TEXT, result TEXT, result_expires INTEGER, created INTEGER NOT NULL, updated INTEGER NOT NULL, reconciled INTEGER NOT NULL DEFAULT 0, UNIQUE(account,dedup), UNIQUE(provider,provider_id));
    CREATE TABLE IF NOT EXISTS incidents(id TEXT PRIMARY KEY, request_id TEXT, reason TEXT NOT NULL, created INTEGER NOT NULL, resolved INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY, action TEXT NOT NULL, reference TEXT NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS provider_reports(provider TEXT PRIMARY KEY, through INTEGER NOT NULL, cost INTEGER NOT NULL, evidence TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS rate_limits(key TEXT PRIMARY KEY, count INTEGER NOT NULL, window INTEGER NOT NULL);
    CREATE TRIGGER IF NOT EXISTS ledger_no_update BEFORE UPDATE ON ledger BEGIN SELECT RAISE(ABORT,'Ledger entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS ledger_no_delete BEFORE DELETE ON ledger BEGIN SELECT RAISE(ABORT,'Ledger entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS audit_no_update BEFORE UPDATE ON audit BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END;
    CREATE TRIGGER IF NOT EXISTS audit_no_delete BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT,'Audit entries are immutable'); END;`);
  db.prepare("INSERT OR IGNORE INTO metadata VALUES('mode',?)").run(mode);
  requireThat(
    db.prepare("SELECT value FROM metadata WHERE key='mode'").get().value === mode,
    "config",
    "Cannot mix demo, test, and live funds in one database.",
  );
  db.prepare("INSERT OR IGNORE INTO metadata VALUES('paused','0')").run();
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
  const one = (sql, ...args) => db.prepare(sql).get(...args);
  const all = (sql, ...args) => db.prepare(sql).all(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  const balance = (account) =>
    one("SELECT COALESCE(SUM(amount),0) AS n FROM ledger WHERE account=?", account).n;
  const held = (account) =>
    one(
      "SELECT COALESCE(SUM(reserved),0) AS n FROM requests WHERE account=? AND state IN ('reserved','submitted','uncertain')",
      account,
    ).n;
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
  function applyReversals(intent) {
    const p = one("SELECT * FROM payments WHERE intent=?", intent);
    if (!p) return;
    const rows = all("SELECT * FROM reversals WHERE intent=?", intent);
    const refunds = rows.filter((r) => r.kind === "refund").reduce((sum, r) => sum + r.cents, 0);
    const disputed = rows.some((r) => r.kind === "dispute");
    const reversed = disputed ? p.cents : Math.min(p.cents, refunds);
    if (reversed > p.reversed) {
      entry(
        p.account,
        -(reversed - p.reversed) * 9000,
        "reversal",
        `reversal:${intent}:${reversed}`,
      );
      run("UPDATE payments SET reversed=? WHERE intent=?", reversed, intent);
    }
    if (disputed || balance(p.account) < held(p.account))
      run("UPDATE accounts SET frozen=1 WHERE id=?", p.account);
  }
  const api = {
    mode,
    limits,
    claim() { db.claim?.(); },
    unclaim() { db.unclaim?.(); },
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
    issueKey(account) {
      return tx(() => {
        accountExists(account);
        requireThat(
          one("SELECT frozen FROM accounts WHERE id=?", account).frozen === 0,
          "frozen",
          "Account is frozen.",
        );
        requireThat(
          one("SELECT count(*) AS n FROM api_keys WHERE account=? AND revoked=0", account).n < 10,
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
        audit("key_issued", id);
        return { id, key };
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
    checkoutOrder(account, cents, dedup) {
      integer(cents, 100, 10000, "Top-up");
      requireThat(typeof dedup === "string" && /^[A-Za-z0-9_-]{16,128}$/.test(dedup), "idempotency", "Provide a stable purchase identifier.");
      return tx(() => {
        accountExists(account);
        requireThat(!one("SELECT frozen FROM accounts WHERE id=?", account).frozen, "frozen", "Account is frozen.");
        const existing = one("SELECT * FROM checkout_orders WHERE account=? AND dedup=?", account, dedup);
        if (existing) {
          requireThat(existing.cents === cents, "checkout_conflict", "Purchase amount changed. Start a new checkout.");
          requireThat(existing.session || existing.created > now() - 23 * 3600000, "checkout_expired", "This checkout attempt expired. Reload and start a new purchase.");
          return existing;
        }
        const id = randomUUID();
        run("INSERT INTO checkout_orders(id,account,dedup,cents,created) VALUES(?,?,?,?,?)", id, account, dedup, cents, now());
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
        run("INSERT INTO payments VALUES(?,?,?,?,0,?)", session, intent, account, cents, now());
        entry(account, fundedMicros(cents), "purchase", session);
        applyReversals(intent);
        audit("payment", session);
        return true;
      });
    },
    reverse({ id, intent, cents, kind }) {
      integer(cents, 1, 10000000, "Reversal");
      requireThat(["refund", "dispute"].includes(kind), "reversal", "Invalid reversal.");
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
        run(
          "INSERT INTO rate_limits VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN window=excluded.window THEN count+1 ELSE 1 END,window=excluded.window",
          key,
          window,
        );
        return one("SELECT count FROM rate_limits WHERE key=?", key).count <= limit;
      });
    },
    reserve({
      account,
      keyId = null,
      dedup,
      fingerprint,
      provider,
      model,
      priceVersion,
      maxCost,
      feeBps = 0,
    }) {
      integer(maxCost, 1, limits.perRequest, "Maximum request cost");
      integer(feeBps, 0, 10000, "Provider funding fee");
      const maxExpense = withFee(maxCost, feeBps);
      requireThat(
        maxExpense <= limits.perRequest,
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
            prior.fingerprint === fingerprint,
            "idempotency_conflict",
            "This request ID was already used for different input.",
          );
          return { request: prior, created: false };
        }
        requireThat(
          one("SELECT value FROM metadata WHERE key='paused'").value === "0",
          "paused",
          "New requests are paused.",
        );
        requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests WHERE state='settled' AND reconciled=0 AND updated<?",
            now() - 86400000,
          ).n === 0,
          "reconciliation_due",
          "Provider reconciliation is overdue.",
        );
        requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests r WHERE state='settled' AND updated<? AND NOT EXISTS (SELECT 1 FROM provider_reports p WHERE p.provider=r.provider AND p.through>=r.created)",
            now() - 86400000,
          ).n === 0,
          "reconciliation_due",
          "Provider account-total reconciliation is overdue.",
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
        requireThat(
          one(
            "SELECT COUNT(*) AS n FROM requests WHERE account=? AND state IN ('reserved','submitted','uncertain')",
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
        const daily = "(updated>=? OR state IN ('reserved','submitted','uncertain'))";
        requireThat(
          spend("1=1") + maxExpense <= limits.globalLifetime,
          "global_limit",
          "Service spending limit reached.",
        );
        requireThat(
          spend(daily, day) + maxExpense <= limits.globalDaily,
          "daily_limit",
          "Service daily limit reached.",
        );
        requireThat(
          spend(`account=? AND ${daily}`, account, day) + maxExpense <= limits.accountDaily,
          "account_limit",
          "Account daily limit reached.",
        );
        requireThat(
          spend(`provider=? AND ${daily}`, provider, day) + maxExpense <= limits.providerDaily,
          "provider_limit",
          "Provider daily limit reached.",
        );
        const id = randomUUID();
        run(
          "INSERT INTO requests(id,account,key_id,dedup,fingerprint,provider,model,price_version,reserved,expense_reserved,fee_bps,state,created,updated) VALUES(?,?,?,?,?,?,?,?,?,?,?,'reserved',?,?)",
          id,
          account,
          keyId,
          dedup,
          fingerprint,
          provider,
          model,
          priceVersion,
          maxCost,
          maxExpense,
          feeBps,
          now(),
          now(),
        );
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
          audit("cancel_before_submit", id);
        }
        return one("SELECT * FROM requests WHERE id=?", id);
      });
    },
    uncertain(id, reason, providerId = null) {
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
        pause(reason, id);
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
    reconcileReport({ provider, through, totalCostMicros, evidence }) {
      integer(totalCostMicros, 0, 1000000000000, "Report cost");
      requireThat(
        ["openrouter", "assemblyai", "elevenlabs"].includes(provider) &&
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
        run("UPDATE requests SET state='released',updated=? WHERE state='reserved'", now());
        const pending = all("SELECT id FROM requests WHERE state='submitted'");
        for (const r of pending) {
          run("UPDATE requests SET state='uncertain',updated=? WHERE id=?", now(), r.id);
          pause("Process stopped with an in-flight provider request", r.id);
        }
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
          "SELECT session AS id,cents,created,reversed FROM payments WHERE account=? ORDER BY created DESC LIMIT 20",
          account,
        ),
        keys: all(
          "SELECT id,suffix,revoked,expires FROM api_keys WHERE account=? ORDER BY rowid",
          account,
        ),
        requests: all(
          "SELECT id,provider,model,state,reserved,cost,charged,created FROM requests WHERE account=? ORDER BY created DESC LIMIT 20",
          account,
        ),
      };
    },
    health() {
      return {
        mode,
        paused: one("SELECT value FROM metadata WHERE key='paused'").value === "1",
        limits,
        incidents: all("SELECT * FROM incidents WHERE resolved=0"),
        pending: all(
          "SELECT id,provider,provider_id,state,reserved,cost,created FROM requests WHERE state IN ('submitted','uncertain')",
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
