# S2T credit purchases

Use Cloudflare Workers with one SQLite Durable Object for the credit ledger, Clerk for customer accounts, and Stripe Checkout for top-ups. The hosted test service is https://s2t-credits.ae-chef-license.workers.dev. The existing Node server remains available for isolated local verification. No Render service is required.

Customers buy S2T credits. The server spends money from dedicated S2T provider accounts and deducts each customer's measured usage. Provider balances and customer balances are separate. A Stripe payment does not automatically refill a provider account.

## Try it locally

Run `npm ci`, then `npm start` in `billing-local`. Open http://localhost:4317. Add demo credits, create an S2T key, and try a metered request. Demo mode makes no real payment or provider call.

In `build/S2T.app`, open Settings → API keys and paste and save the key under S2T. Under Models, choose S2T credits for Speech to text or Text cleanup. Credit transcription defaults to AssemblyAI Universal 3.5 Pro. Credit cleanup defaults to OpenRouter `openai/gpt-oss-120b` on `cerebras/fp16`. OpenRouter model and host choices are available with either a personal key or S2T credits. Each task keeps its personal provider settings when you switch billing methods. Demo responses are synthetic. They do not transcribe your voice. The key and configured service address stay together in the existing Keychain vault. Saving checks the key without spending credits.

The credit route supports available OpenRouter catalog models for speech and cleanup, including Cerebras hosting through OpenRouter. Recordings are limited to two minutes. Requests also need enough credits and must fit the service's per-request budget. Direct Cerebras API requests remain separate from OpenRouter hosting. Cleanup still uses your instructions, dictionary, writing mode, and opaque clipboard placeholders. If cleanup fails, the existing delivery path retains the original transcript.

## Test payments and sign-in

1. Copy `.env.example` to your own `.env` and set mode to `test`. Put Stripe sandbox secrets in that local file, never in chat or source control. Run `npm run start:env`.
2. Configure Stripe to send the checkout completion, asynchronous payment success, refund, and dispute events listed in `stripe-billing.mjs` to `/api/stripe/webhook`. For local testing, Stripe CLI can forward sandbox events to `localhost:4317`. Its webhook signing secret differs from a hosted endpoint's secret.
3. To test customer accounts, create a Clerk development application. Configure a JWT template named `s2t` with `{"aud":"s2t-credits"}` and a short lifetime. Add its publishable key to `CLERK_PUBLISHABLE_KEY`. The server derives the issuer and JWKS URL from that key unless the OIDC environment values override them. The browser mounts Clerk's sign-in and account controls, and requests a fresh token for API calls. The backend validates the signature, issuer, audience, and expiry. Browser tokens stay in memory.
4. Purchase through the dashboard. The server creates a Checkout Session for the selected USD amount and authenticated account. Balance changes only after the signed webhook and authoritative Stripe payment agree. Returning from checkout does not grant money. The dashboard refreshes every ten seconds while visible and on return to the tab.

Test mode uses synthetic provider responses. Its funds and keys cannot become live funds or keys. Without Clerk, local test sessions are browser-specific and expire after seven days. Use Clerk before involving other testers or relying on account recovery.

## Hosted staging

`wrangler.jsonc` is a portable demo configuration for the Cloudflare runtime and static dashboard. Keep account-specific deployment settings in the ignored `wrangler.local.jsonc`; copy the demo configuration there for a new deployment and configure your own identity provider, approved pricing, and independently reviewed funding controls. From `billing-local`, run `npm run test:cloudflare`, then `npm run deploy:cloudflare`, which requires that local override. Stay on the Workers Free plan. No paid-plan upgrade is performed by these commands. Free-limit exhaustion rejects requests; it does not grant credits or release uncertain reservations.

Store `S2T_RESULT_KEY`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET` as Worker secrets. The encryption key is 32 random bytes encoded as hex and must remain stable across deployments. Stripe sends checkout completion, asynchronous payment success, refund, and dispute events to `/api/stripe/webhook`. See `stripe-billing.mjs` for the exact event names.

Before enabling new guest purchases with the September 27 remediation, set `S2T_GUEST_CREDENTIAL_KEY` to a newly generated, independent 32-byte secret (64 lowercase hex characters). Keep the existing `S2T_RESULT_KEY` unchanged. The new secret derives credentials for new wallets and encrypts the preserved keys, recovery codes, and optional email records of old wallets. With the old result key still configured, call the authenticated operator action `{"action":"migrate_guest_credentials"}` repeatedly until it reports `remaining:0`; each call processes at most 100 old wallets. A wrong original result key stops migration, including for unpaid/keyless wallets, and leaves those rows in version 1. Verify the final zero count and recovery/key behavior against an authorized test wallet before considering a result-key rotation. Do not change the guest credential key without a separate future migration plan. The migration does not rotate an existing customer's key or recovery code.

Direct streaming token issuance and client-duration completion are retired. Keep historical streaming ledger rows and reconcile issued-token costs only from independent provider evidence through the operator `reconcile` action; use audited `writeoff` if evidence cannot be obtained. Previously client-settled tokens can have their provider expense corrected. Any customer amount above the verified cost is refunded as an immutable usage correction; any shortfall is absorbed without a new customer debit. The native early-transcription path uses ordinary paid speech uploads.

The Durable Object is selected by billing mode, so test and live ledgers remain separate. Synchronous SQL transactions protect balances, and the gateway waits for durable storage before sending provider requests. Restart recovery retains uncertain reservations. Preserve this single-ledger design until global budget coordination has been redesigned.

The deployment source branch is `codex/hosted-credits`. Build the Mac app with `S2T_CREDITS_URL=https://s2t-credits.ae-chef-license.workers.dev` so the S2T key connects to the deployed service.

Do not paste provider master keys into chat or embed them in the Mac app. Create dedicated provider keys for S2T, restrict them where supported, and enter them directly in the host's secret settings. Start with small prepaid balances and auto-refill off. The existing live configuration requires documented external spending limits; do not bypass those checks by inventing evidence. Provider auto-refill can be reconsidered after measured staging usage and an explicit spending policy.

Before live or real-provider staging spending, independently inspect current provider funding and limits. `S2T_PROVIDER_LIMITS_JSON.reviewedAt` must reflect that actual check within the preceding 24 hours; historical funding evidence is not a current review and new spending is intentionally rejected when it is stale. A stale review does not block balance reads, guest recovery, Stripe webhooks, or operator reconciliation. The timestamp is checked before each new paid reservation in a long-lived process or Durable Object. Independently reconcile aged settled requests and cumulative provider totals; spending pauses when a settled request is older than 24 hours without both confirmations. Existing idempotent request IDs may still be retried.

## Private real-dictation testing

Stripe sandbox normally returns synthetic provider results. To test real dictation without real payments, set `S2T_STAGING_REAL_PROVIDERS=explicitly-enabled` and `S2T_STAGING_USERS` to the approved Clerk user IDs, separated by commas. Every dashboard and app request checks this allowlist. Keep the Stripe key in test mode.

This mode also requires the live-mode provider controls, pricing, OIDC configuration, and result encryption key described in `config.mjs`. Put provider keys in Cloudflare Worker secrets. Store reviewed pricing and provider-limit JSON as `S2T_PRICING_JSON` and `S2T_PROVIDER_LIMITS_JSON`. The Worker maps these into the shared configuration checks. Set OIDC issuer and JWKS to the configured Clerk domain, and audience to `s2t-credits`. Do not use fixture values as evidence of real account limits. Start with only the routes whose provider accounts have been configured.

For the Stripe server key, create a sandbox restricted key with Checkout Sessions write access and Payment Intents, Refunds, and Disputes read access. The legacy Payment Link path additionally needs Payment Links read access. Store it as `STRIPE_SECRET_KEY` in Cloudflare. CLI authorization is for administration and is not a permanent server credential.

## Before live purchases

The service is deployed in Stripe test mode. Test credit balances do not represent real purchases. Live provider access stays disabled until dedicated provider credentials and reviewed limits are configured. Production still needs reviewed provider prices and billing rounding, a decision on taxes and Stripe fees, independent provider usage reconciliation, monitoring, consistent encrypted backups and restore checks, and a policy for retained encrypted results. The current policy blocks usage when reconciliation or pricing becomes overdue. These restrictions remain in force.

The credit conversion is $1 buys 100 credits funding $0.50 of provider usage. The remaining $0.50 is before Stripe fees, infrastructure, refunds, and taxes. Do not treat that as a confirmed profit margin. Taxes, discounts, and shipping are rejected by fulfillment until a matching pricing policy exists.

## Verification

- `npm run test:cloudflare`: real Cloudflare local runtime with isolated durable storage, mocked Clerk/Stripe endpoints, payment replay, simultaneous requests, exact balances, and persistence across runtime restarts.
- `node hosted-check.mjs`: deployed service and real Clerk development test account configured through `S2T_TEST_ORIGIN`, `CLERK_TEST_APP_ID`, `CLERK_TEST_USER_ID`, and `CLERK_FAPI`. It uses short-lived test sign-in tokens and never screenshots.
- `npm test`: ledger, checkout, payment, identity, provider, and failure cases with isolated fixtures.
- `npm run test:browser`: starts its own temporary service and drives the dashboard without screenshots or clipboard access.
- `npm run test:native`: starts an isolated demo service and exercises the packaged Mac client's real HTTP transport, authentication, editing request, and exact balance change.
- `build/S2T.app/Contents/MacOS/S2T --verify-credits`: preview-only native settings, key masking, readiness, and supported-route checks.

Reference documentation: [Cloudflare Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [Clerk JavaScript setup](https://clerk.com/docs/js-frontend/getting-started/quickstart), [Clerk JWT templates](https://clerk.com/docs/guides/sessions/jwt-templates), and [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create).
