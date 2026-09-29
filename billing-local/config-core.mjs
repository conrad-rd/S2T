import { hash } from "./ledger-core.mjs";
import { requireThat } from "./money.mjs";
import { fixturePolicy, validatePolicy } from "./policy.mjs";
export function requireFreshFundingReview(config, currentTime = Date.now()) {
  if (!config.realProviders) return;
  const reviewed = config.fundingReviewedAt;
  requireThat(Number.isFinite(reviewed) && reviewed <= currentTime && reviewed >= currentTime - 86400000,
    "funding_review_expired", "Provider funding evidence must be independently reviewed within the last 24 hours. Update reviewedAt only after a real funding and limit check.");
}
export function configuration(env, { root = "", dataDir = "", readFile = () => { throw new Error("Pricing files unavailable"); } } = {}) {
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
    config.policy = validatePolicy(JSON.parse(readFile(env.S2T_PRICING_FILE, "utf8")), {
      live: true,
    });
    const controls = JSON.parse(readFile(env.S2T_PROVIDER_LIMITS_FILE, "utf8"));
    const keys = { xai: env.XAI_API_KEY, openrouter: env.OPENROUTER_API_KEY, assemblyai: env.ASSEMBLYAI_API_KEY };
    config.fundingReviewedAt = Date.parse(controls.reviewedAt);
    requireThat(Number.isFinite(config.fundingReviewedAt) && config.fundingReviewedAt <= Date.now(),
      "funding_review_invalid", "Provider funding evidence needs a valid review timestamp that is not in the future.");
    for (const route of Object.keys(config.policy.routes)) {
      const provider = route.split(":")[0], control = controls.providers?.[provider];
      const bounded = control?.funding === "prepaid" ||
        (Number.isFinite(control?.hardCapUsd) && control.hardCapUsd > 0 && control.hardCapUsd <= 20);
      requireThat(keys[provider] && bounded && control?.autoRecharge === false &&
        typeof control.evidence === "string" && control.evidence.length >= 20,
        "config", `${provider} needs a dedicated capped or prepaid key, no auto-recharge, and recorded funding evidence.`);
      config.keys[provider] = keys[provider];
    }
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
  if (mode === "live") {
    requireThat(/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(env.S2T_ALLOWED_EMAIL || ""), "config", "Set the email approved for live credits.");
    config.identity.allowedEmail = env.S2T_ALLOWED_EMAIL.toLowerCase();
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
  requireThat(env.S2T_ASSEMBLY_STREAMING === undefined, "streaming_retired", "Direct streaming has been retired pending independently verified provider billing. Remove S2T_ASSEMBLY_STREAMING.");
  return config;
}
