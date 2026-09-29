import { randomUUID } from "node:crypto";
import { integer, requireThat, withFee } from "./money.mjs";
import { requestDevice } from "./usage.mjs";
export function createDirectLedger(
  db,
  { now, tx, limits, keyBudgets, balance, held, audit, entry, pause, refreshFreeze },
) {
  db.exec(`CREATE TABLE IF NOT EXISTS direct_authorizations(id TEXT PRIMARY KEY,account TEXT NOT NULL REFERENCES accounts(id),key_id TEXT NOT NULL REFERENCES api_keys(id),dedup TEXT NOT NULL,model TEXT NOT NULL,host TEXT NOT NULL,price_version TEXT NOT NULL,fee_bps INTEGER NOT NULL,authorized INTEGER NOT NULL,expense_authorized INTEGER NOT NULL,observed INTEGER NOT NULL DEFAULT 0,charged INTEGER NOT NULL DEFAULT 0,expense INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL CHECK(status IN ('creating','active','closing','closed')),hash TEXT UNIQUE,secret_cipher TEXT,expires INTEGER NOT NULL,device_id TEXT,device_name TEXT,created INTEGER NOT NULL,updated INTEGER NOT NULL,UNIQUE(account,dedup));
  CREATE TABLE IF NOT EXISTS direct_refills(authorization_id TEXT NOT NULL REFERENCES direct_authorizations(id),dedup TEXT NOT NULL,amount INTEGER NOT NULL,PRIMARY KEY(authorization_id,dedup));`);
  const one = (s, ...a) => db.prepare(s).get(...a),
    run = (s, ...a) => db.prepare(s).run(...a);
  const get = (id) => one("SELECT * FROM direct_authorizations WHERE id=?", id);
  const outstanding = (filter, args = []) =>
    one(
      `SELECT COALESCE(SUM(authorized-charged),0) n FROM direct_authorizations WHERE status!='closed' ${filter}`,
      ...args,
    ).n;
  const exposure = ({ account, provider, since } = {}) => {
    if (provider && provider !== "openrouter") return 0;
    return one(
      `SELECT COALESCE(SUM(MAX(0,expense_authorized-expense)),0) n FROM direct_authorizations WHERE status!='closed' ${account ? "AND account=?" : ""}`,
      ...(account ? [account] : []),
    ).n;
  };
  function eligible(id) {
    const r = get(id);
    const enabled =
      !!r &&
      ["creating", "active"].includes(r.status) &&
      r.expires > now() &&
      one("SELECT value FROM metadata WHERE key='paused'").value === "0" &&
      !!one(
        "SELECT a.id FROM accounts a JOIN api_keys k ON k.account=a.id WHERE a.id=? AND a.frozen=0 AND k.id=? AND k.revoked=0 AND k.expires>?",
        r.account,
        r.key_id,
        now(),
      );
    if (!enabled) return false;
    try {
      keyBudgets.check(r.account, r.key_id, 0);
    } catch (error) {
      if (error.code === "key_limit") return false;
      throw error;
    }
    return balance(r.account) >= held(r.account);
  }
  function check(account, keyId, amount, fee) {
    integer(amount, 1, limits.perRequest ?? 1000000000000, "Direct allowance");
    requireThat(
      limits.perRequest === null || withFee(amount, fee) <= limits.perRequest,
      "request_limit",
      "Direct allowance including fees exceeds the spending ceiling.",
    );
    keyBudgets.check(account, keyId, amount);
    requireThat(
      one("SELECT value FROM metadata WHERE key='paused'").value === "0",
      "paused",
      "New requests are paused.",
    );
    requireThat(
      one("SELECT frozen FROM accounts WHERE id=?", account)?.frozen === 0,
      "frozen",
      "Account is frozen.",
    );
    requireThat(
      balance(account) - held(account) >= amount,
      "insufficient_credits",
      "Not enough available credits.",
      402,
    );
    const day = Math.floor(now() / 86400000) * 86400000,
      extra = withFee(amount, fee);
    for (const [filter, args, scope, limit, code] of [
      ["1=1", [], {}, limits.globalLifetime, "global_limit"],
      [
        `(updated>=? OR state IN ('reserved','submitted','uncertain') OR id IN (SELECT request_id FROM streaming_sessions WHERE window_end>${now()}))`,
        [day],
        { since: day },
        limits.globalDaily,
        "daily_limit",
      ],
      [
        `account=? AND (updated>=? OR state IN ('reserved','submitted','uncertain') OR id IN (SELECT request_id FROM streaming_sessions WHERE window_end>${now()}))`,
        [account, day],
        { account, since: day },
        limits.accountDaily,
        "account_limit",
      ],
      [
        "provider='openrouter' AND (updated>=? OR state IN ('reserved','submitted','uncertain'))",
        [day],
        { provider: "openrouter", since: day },
        limits.providerDaily,
        "provider_limit",
      ],
    ]) {
      if (limit === null) continue;
      const normal = one(
        `SELECT COALESCE(SUM(CASE WHEN state IN ('reserved','submitted','uncertain') THEN expense_reserved WHEN state='settled' THEN expense ELSE 0 END),0) n FROM requests WHERE ${filter}`,
        ...args,
      ).n;
      requireThat(
        normal + exposure(scope) + extra <= limit,
        code,
        "Direct spending limit reached.",
      );
    }
  }
  function observeInternal(id, { usageMicros, byokMicros = 0 }) {
    const r = get(id);
    requireThat(r, "direct", "Authorization not found.", 404);
    integer(usageMicros, 0, 1e12, "Provider usage");
    integer(byokMicros, 0, 1e12, "BYOK usage");
    const cost = usageMicros + byokMicros;
    integer(cost, 0, 1e12, "Total provider usage");
    if (cost < r.observed) {
      pause("Direct provider cumulative usage regressed", id);
      run(
        "UPDATE direct_authorizations SET status='closing' WHERE id=? AND status!='closed'",
        id,
      );
      return get(id);
    }
    if (cost > r.authorized) {
      pause("Direct provider exceeded authorization", id);
      run(
        "UPDATE direct_authorizations SET status='closing' WHERE id=? AND status!='closed'",
        id,
      );
    }
    const charged = Math.min(cost, r.authorized),
      expense = withFee(cost, r.fee_bps),
      delta = charged - r.charged,
      expenseDelta = expense - r.expense;
    if (delta > 0 || expenseDelta > 0) {
      const requestId = randomUUID();
      run(
        "INSERT INTO requests(id,account,key_id,dedup,fingerprint,provider,model,price_version,reserved,expense_reserved,fee_bps,cost,charged,expense,state,provider_id,created,updated) VALUES(?,?,?,?,?,'openrouter',?,?,?,?,?,?,?,?,'settled',?,?,?)",
        requestId,
        r.account,
        r.key_id,
        `direct:${id}:${cost}`,
        `direct:${id}:${cost}`,
        r.model,
        r.price_version,
        Math.max(1, delta),
        Math.max(1, delta, expenseDelta),
        r.fee_bps,
        cost - r.observed,
        delta,
        expenseDelta,
        `direct:${id}:${cost}`,
        now(),
        now(),
      );
      if (delta > 0) entry(r.account, -delta, "usage", `usage:${requestId}`);
      if (r.device_id)
        run(
          "INSERT INTO request_devices VALUES(?,?,?)",
          requestId,
          r.device_id,
          r.device_name,
        );
    }
    run(
      "UPDATE direct_authorizations SET observed=?,charged=?,expense=?,updated=? WHERE id=?",
      cost,
      charged,
      expense,
      now(),
      id,
    );
    return get(id);
  }
  return {
    get,
    eligible,
    exposure,
    held: (account) => outstanding("AND account=?", [account]),
    keyHeld: (key) => outstanding("AND key_id=?", [key]),
    pending: () =>
      db
        .prepare(
          "SELECT * FROM direct_authorizations WHERE status!='closed' ORDER BY created",
        )
        .all(),
    prepare(p) {
      return tx(() => {
        const device = p.device
          ? requestDevice(p.device.id, p.device.name)
          : null;
        for (const field of ["dedup", "model", "host", "priceVersion"])
          requireThat(
            typeof p[field] === "string" &&
              p[field].length > 0 &&
              p[field].length <= 500,
            "direct_input",
            "Invalid direct authorization metadata.",
          );
        keyBudgets.check(p.account, p.keyId, 0);
        const prior = one(
          "SELECT * FROM direct_authorizations WHERE account=? AND dedup=?",
          p.account,
          p.dedup,
        );
        if (prior) {
          requireThat(
            eligible(prior.id),
            "direct_ineligible",
            "Direct authorization is inactive.",
          );
          const initial = one(
            "SELECT amount FROM direct_refills WHERE authorization_id=? AND dedup='__initial'",
            prior.id,
          );
          requireThat(
            prior.key_id === p.keyId &&
              prior.model === p.model &&
              prior.host === p.host &&
              prior.price_version === p.priceVersion &&
              prior.fee_bps === (p.feeBps ?? 0) &&
              initial?.amount === p.allowanceMicros &&
              prior.device_id === (device?.id ?? null) &&
              prior.device_name === (device?.name ?? null),
            "idempotency_conflict",
            "Direct request ID was already used.",
          );
          return { authorization: prior, created: false };
        }
        integer(p.feeBps ?? 0, 0, 10000, "Provider fee");
        integer(p.expiresAt, now() + 1, Number.MAX_SAFE_INTEGER, "Expiry");
        check(p.account, p.keyId, p.allowanceMicros, p.feeBps ?? 0);
        requireThat(
          one(
            "SELECT COUNT(*) n FROM direct_authorizations WHERE account=? AND status='creating'",
            p.account,
          ).n < limits.concurrency &&
            one(
              "SELECT COUNT(*) n FROM direct_authorizations WHERE status='creating'",
            ).n < limits.concurrency,
          "concurrency",
          "Too many pending direct authorizations.",
          429,
        );
        requireThat(
          one(
            "SELECT COUNT(*) n FROM direct_authorizations WHERE account=? AND created>?",
            p.account,
            now() - 60000,
          ).n < limits.requestsPerMinute &&
            one(
              "SELECT COUNT(*) n FROM direct_authorizations WHERE created>?",
              now() - 60000,
            ).n < limits.requestsPerMinute,
          "rate_limit",
          "Direct authorization rate limit reached.",
          429,
        );
        const id = randomUUID();
        run(
          "INSERT INTO direct_authorizations(id,account,key_id,dedup,model,host,price_version,fee_bps,authorized,expense_authorized,status,expires,device_id,device_name,created,updated) VALUES(?,?,?,?,?,?,?,?,?,?,'creating',?,?,?,?,?)",
          id,
          p.account,
          p.keyId,
          p.dedup,
          p.model,
          p.host,
          p.priceVersion,
          p.feeBps ?? 0,
          p.allowanceMicros,
          withFee(p.allowanceMicros, p.feeBps ?? 0),
          p.expiresAt,
          device?.id ?? null,
          device?.name ?? null,
          now(),
          now(),
        );
        run(
          "INSERT INTO direct_refills VALUES(?,'__initial',?)",
          id,
          p.allowanceMicros,
        );
        audit("direct_prepare", id);
        return { authorization: get(id), created: true };
      });
    },
    refill(id, { allowanceMicros, dedup }) {
      return tx(() => {
        requireThat(
          typeof dedup === "string" &&
            dedup.length > 0 &&
            dedup.length <= 500 &&
            dedup !== "__initial",
          "direct_input",
          "Invalid refill identifier.",
        );
        const r = get(id);
        requireThat(r, "direct", "Authorization not found.", 404);
        const prior = one(
          "SELECT amount FROM direct_refills WHERE authorization_id=? AND dedup=?",
          id,
          dedup,
        );
        if (prior) {
          requireThat(
            prior.amount === allowanceMicros,
            "idempotency_conflict",
            "Refill amount changed.",
          );
          return get(id);
        }
        requireThat(
          eligible(id) && r.status === "active",
          "direct_ineligible",
          "Direct authorization is inactive.",
        );
        check(r.account, r.key_id, allowanceMicros, r.fee_bps);
        run(
          "INSERT INTO direct_refills VALUES(?,?,?)",
          id,
          dedup,
          allowanceMicros,
        );
        run(
          "UPDATE direct_authorizations SET authorized=?,expense_authorized=?,updated=? WHERE id=?",
          r.authorized + allowanceMicros,
          withFee(r.authorized + allowanceMicros, r.fee_bps),
          now(),
          id,
        );
        audit("direct_refill", id);
        return get(id);
      });
    },
    attach(id, { hash, secretCipher }) {
      return tx(() => {
        const r = get(id);
        requireThat(
          r && r.status === "creating",
          "direct_state",
          "Authorization is not awaiting provisioning.",
        );
        requireThat(
          typeof hash === "string" &&
            hash &&
            typeof secretCipher === "string" &&
            secretCipher,
          "direct_credentials",
          "Missing encrypted provider credentials.",
        );
        run(
          "UPDATE direct_authorizations SET hash=?,secret_cipher=?,status='active',updated=? WHERE id=?",
          hash,
          secretCipher,
          now(),
          id,
        );
        return get(id);
      });
    },
    observe: (id, evidence) => tx(() => observeInternal(id, evidence)),
    markClosing(id) {
      return tx(() => {
        requireThat(get(id), "direct", "Authorization not found.", 404);
        run(
          "UPDATE direct_authorizations SET status='closing',updated=? WHERE id=? AND status!='closed'",
          now(),
          id,
        );
        return get(id);
      });
    },
    close(id, evidence) {
      return tx(() => {
        requireThat(
          get(id)?.status === "closing",
          "direct_state",
          "Disable the provider key before closing.",
        );
        requireThat(
          evidence.finalUsageVerified === true,
          "direct_finality",
          "Independent final usage verification is required.",
        );
        requireThat(
          evidence.usageMicros + (evidence.byokMicros ?? 0) >= get(id).observed,
          "direct_finality",
          "Final usage cannot regress.",
        );
        observeInternal(id, evidence);
        run(
          "UPDATE direct_authorizations SET status='closed',updated=? WHERE id=?",
          now(),
          id,
        );
        refreshFreeze(get(id).account);
        audit("direct_closed", id);
        return get(id);
      });
    },
  };
}
