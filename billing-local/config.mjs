import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { requireThat } from "./money.mjs";
import { fixturePolicy, validatePolicy } from "./policy.mjs";
export function configuration(env = process.env) {
  const mode = env.S2T_BILLING_MODE || "demo";
  requireThat(
    ["demo", "test", "live"].includes(mode),
    "config",
    "S2T_BILLING_MODE must be demo, test, or live.",
  );
  const port = Number(env.PORT || 4317);
  requireThat(Number.isInteger(port) && port > 0 && port < 65536, "config", "Invalid port.");
  const root = fileURLToPath(new URL(".", import.meta.url));
  const dataDir = resolve(
    env.S2T_BILLING_DATA_DIR || fileURLToPath(new URL(".data", import.meta.url)),
  );
  const config = {
    mode,
    port,
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
  if (mode === "live") {
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
      "STRIPE_LIVE_PAYMENT_LINK_ID",
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
      /^(sk|rk)_live_/.test(env.STRIPE_SECRET_KEY),
      "config",
      "A live Stripe server key is required.",
    );
    requireThat(
      /^[a-f0-9]{64}$/.test(env.S2T_RESULT_KEY),
      "config",
      "S2T_RESULT_KEY must be 32 random bytes encoded as hex.",
    );
    requireThat(
      env.S2T_ENABLE_LIVE_SPENDING === "explicitly-enabled",
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
  if (mode !== "live" && config.stripeKey)
    requireThat(
      /^(sk|rk)_test_/.test(config.stripeKey),
      "config",
      "Test and demo modes must never use a live Stripe key.",
    );
  return config;
}
