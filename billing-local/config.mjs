import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { hash } from "./ledger.mjs";
import { requireThat } from "./money.mjs";
import { fixturePolicy, validatePolicy } from "./policy.mjs";
export function configuration(env = process.env) {
  const mode = env.S2T_BILLING_MODE || "demo";
  requireThat(
    ["demo", "test", "live"].includes(mode),
    "config",
    "S2T_BILLING_MODE must be demo, test, or live.",
  );
  const realProviders = mode === "live" || env.S2T_STAGING_REAL_PROVIDERS === "explicitly-enabled";
  requireThat(!realProviders || mode !== "demo", "config", "Demo mode cannot use real providers.");
  const port = Number(env.PORT || 4317);
  requireThat(Number.isInteger(port) && port > 0 && port < 65536, "config", "Invalid port.");
  const root = fileURLToPath(new URL(".", import.meta.url));
  const dataDir = resolve(
    env.S2T_BILLING_DATA_DIR || fileURLToPath(new URL(".data", import.meta.url)),
  );
  const config = {
    mode,
    realProviders,
    port,
    host: env.S2T_BIND_HOST || "127.0.0.1",
    dataDir,
    root,
    origin: env.S2T_PUBLIC_ORIGIN || `http://localhost:${port}`,
    policy: fixturePolicy,
    keys: {},
    webhookSecret: env.STRIPE_WEBHOOK_SECRET,
    paymentLinkId: env.STRIPE_TEST_PAYMENT_LINK_ID,
    stripeKey: env.STRIPE_SECRET_KEY,
    paymentLink: "https://buy.stripe.com/dRmbJ18vB4d5f6g2BV8IU02",
  };
  if (realProviders) {
    requireThat(
      !env.VERCEL,
      "deployment",
      "This SQLite service requires one persistent host. Port the ledger to hosted PostgreSQL before deploying functions to Vercel.",
    );
    for (const name of [
      "S2T_PUBLIC_ORIGIN",
      "S2T_OIDC_ISSUER",
      "S2T_OIDC_AUDIENCE",
      "S2T_OIDC_JWKS_URL",
      "STRIPE_SECRET_KEY",
      "STRIPE_WEBHOOK_SECRET",
      "CLERK_PUBLISHABLE_KEY",
      "S2T_PRICING_FILE",
      "S2T_PROVIDER_LIMITS_FILE",
      "S2T_RESULT_KEY",
    ])
      requireThat(env[name], "config", `${name} is required for live mode.`);
    requireThat(
      new URL(config.origin).protocol === "https:" &&
        new URL(config.origin).origin === config.origin,
      "config",
      "Live mode requires an exact HTTPS origin.",
    );
    for (const name of ["S2T_OIDC_ISSUER", "S2T_OIDC_JWKS_URL"])
      requireThat(
        new URL(env[name]).protocol === "https:",
        "config",
        "Identity provider URLs must use HTTPS.",
      );
    requireThat(
      (mode === "live" ? /^(sk|rk)_live_/ : /^(sk|rk)_test_/).test(env.STRIPE_SECRET_KEY),
      "config",
      "Stripe credentials must match the selected billing mode.",
    );
    requireThat(
      /^[a-f0-9]{64}$/.test(env.S2T_RESULT_KEY),
      "config",
      "S2T_RESULT_KEY must be 32 random bytes encoded as hex.",
    );
    requireThat(
      mode !== "live" || env.S2T_ENABLE_LIVE_SPENDING === "explicitly-enabled",
      "config",
      "Live spending must be explicitly enabled after reviewing provider limits.",
    );
    config.policy = validatePolicy(JSON.parse(readFileSync(env.S2T_PRICING_FILE, "utf8")), {
      live: true,
    });
    const controls = JSON.parse(readFileSync(env.S2T_PROVIDER_LIMITS_FILE, "utf8"));
    requireThat(
      Date.parse(controls.reviewedAt) <= Date.now() &&
        Date.parse(controls.reviewedAt) > Date.now() - 86400000,
      "config",
      "External provider limits must have been checked within 24 hours.",
    );
    const keys = {
      openrouter: env.OPENROUTER_API_KEY,
      assemblyai: env.ASSEMBLYAI_API_KEY,
      elevenlabs: env.ELEVENLABS_API_KEY,
    };
    for (const route of Object.keys(config.policy.routes)) {
      const provider = route.split(":")[0],
        control = controls.providers?.[provider];
      requireThat(
        keys[provider] &&
          control?.autoRecharge === false &&
          control?.overdraftDisabled === true &&
          Number.isFinite(control?.hardCapUsd) &&
          control.hardCapUsd > 0 &&
          control.hardCapUsd <= 20 &&
          typeof control.evidence === "string" &&
          control.evidence.length >= 20,
        "config",
        `${provider} needs a dedicated capped account, no auto-recharge or overdraft, and recorded operator evidence.`,
      );
      config.keys[provider] = keys[provider];
    }
    requireThat(
      Object.keys(config.keys).reduce((sum, p) => sum + controls.providers[p].hardCapUsd, 0) <= 20,
      "config",
      "Combined external provider caps must be at most $20 for initial launch.",
    );
    config.externalControlsExpire = Date.parse(controls.reviewedAt) + 86400000;
    config.paymentLinkId = env.STRIPE_LIVE_PAYMENT_LINK_ID;
    config.identity = {
      issuer: env.S2T_OIDC_ISSUER,
      audience: env.S2T_OIDC_AUDIENCE,
      jwks: env.S2T_OIDC_JWKS_URL,
    };
    config.resultKey = Buffer.from(env.S2T_RESULT_KEY, "hex");
  }
  if (env.CLERK_PUBLISHABLE_KEY) {
    requireThat(/^pk_(test|live)_[A-Za-z0-9=]+$/.test(env.CLERK_PUBLISHABLE_KEY), "config", "Invalid Clerk publishable key.");
    requireThat(mode !== "live" || env.CLERK_PUBLISHABLE_KEY.startsWith("pk_live_"), "config", "Live billing requires a production Clerk application.");
    const domain = Buffer.from(env.CLERK_PUBLISHABLE_KEY.split("_")[2], "base64").toString().replace(/\$$/, "");
    requireThat(/^[a-z0-9.-]+$/.test(domain) && domain.includes("."), "config", "Invalid Clerk domain.");
    config.clerk = { publishableKey: env.CLERK_PUBLISHABLE_KEY, origin: `https://${domain}`, template: "s2t" };
    config.identity = { issuer: env.S2T_OIDC_ISSUER || config.clerk.origin, audience: env.S2T_OIDC_AUDIENCE || "s2t-credits", jwks: env.S2T_OIDC_JWKS_URL || `${config.clerk.origin}/.well-known/jwks.json` };
  }
  if (realProviders && mode === "test") {
    const users = (env.S2T_STAGING_USERS || "").split(",").map(value => value.trim()).filter(Boolean);
    requireThat(users.length > 0 && users.length <= 10 && users.every(value => /^user_[A-Za-z0-9]+$/.test(value)), "config", "Real-provider sandbox testing requires an explicit Clerk user allowlist.");
    config.allowedAccounts = users.map(user => hash(`${config.identity.issuer}:${user}`));
  }
  if (env.RENDER) {
    requireThat(mode !== "demo" && config.identity && config.clerk, "config", "Hosted credits require customer sign-in and test or live billing.");
    requireThat(new URL(config.origin).protocol === "https:" && new URL(config.origin).origin === config.origin, "config", "Hosted credits require an exact HTTPS origin.");
    requireThat(dataDir === "/var/data/s2t", "config", "Render must mount the persistent credits disk at /var/data/s2t.");
  }
  if (mode !== "live" && config.stripeKey)
    requireThat(
      /^(sk|rk)_test_/.test(config.stripeKey),
      "config",
      "Test and demo modes must never use a live Stripe key.",
    );
  return config;
}
