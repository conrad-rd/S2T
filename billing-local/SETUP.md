# S2T credit purchases

Use Cloudflare Workers with one SQLite Durable Object for the credit ledger, Clerk for customer accounts, and Stripe Checkout for top-ups. The hosted test service is https://s2t-credits.ae-chef-license.workers.dev. The existing Node server remains available for isolated local verification. No Render service is required.

Customers buy S2T credits. The server spends money from dedicated S2T provider accounts and deducts each customer's measured usage. Provider balances and customer balances are separate. A Stripe payment does not automatically refill a provider account.

## Try it locally

Run `npm ci`, then `npm start` in `billing-local`. Open http://localhost:4317. Add demo credits, create an S2T key, and try a metered request. Demo mode makes no real payment or provider call.

In `build/S2T.app`, open Settings → Models → S2T credits. Enter the service address and choose Sign in. Compare the code shown by the app and browser, then approve the connection. You can also save a demo key manually. Select Use S2T credits and choose AssemblyAI or ElevenLabs in the credit transcription selector. Credit cleanup uses OpenRouter `openai/gpt-oss-120b` on `cerebras/fp16`; personal model settings remain separate. Demo responses are synthetic; they are not transcription of your voice. Return to Use my own provider keys for normal dictation. The key and service address stay together in the existing Keychain vault, and checking them is an explicit action.

The credit route currently supports recordings up to two minutes and the models listed above. It does not fund Prompt vision, long recordings, other model IDs, or direct Cerebras requests. Personal-key mode retains those existing capabilities. Cleanup still uses the system prompt, dictionary, writing mode, and opaque clipboard placeholders. If cleanup fails, the existing delivery path retains the original transcript.

## Test payments and sign-in

1. Copy `.env.example` to your own `.env` and set mode to `test`. Put Stripe sandbox secrets in that local file, never in chat or source control. Run `npm run start:env`.
2. Configure Stripe to send the checkout completion, asynchronous payment success, refund, and dispute events listed in `stripe-billing.mjs` to `/api/stripe/webhook`. For local testing, Stripe CLI can forward sandbox events to `localhost:4317`. Its webhook signing secret differs from a hosted endpoint's secret.
3. To test customer accounts, create a Clerk development application. Configure a JWT template named `s2t` with `{"aud":"s2t-credits"}` and a short lifetime. Add its publishable key to `CLERK_PUBLISHABLE_KEY`. The server derives the issuer and JWKS URL from that key unless the OIDC environment values override them. The browser mounts Clerk's sign-in and account controls, and requests a fresh token for API calls. The backend validates the signature, issuer, audience, and expiry. Browser tokens stay in memory.
4. Purchase through the dashboard. The server creates a Checkout Session for the selected USD amount and authenticated account. Balance changes only after the signed webhook and authoritative Stripe payment agree. Returning from checkout does not grant money. The dashboard refreshes every ten seconds while visible and on return to the tab.

Test mode uses synthetic provider responses. Its funds and keys cannot become live funds or keys. Without Clerk, local test sessions are browser-specific and expire after seven days. Use Clerk before involving other testers or relying on account recovery.

## Hosted staging

`wrangler.jsonc` configures the Cloudflare deployment and static dashboard. From `billing-local`, run `npm run test:cloudflare`, then `npm run deploy:cloudflare`. Stay on the Workers Free plan. No paid-plan upgrade is performed by these commands. Free-limit exhaustion rejects requests; it does not grant credits or release uncertain reservations.

Store `S2T_RESULT_KEY`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET` as Worker secrets. The encryption key is 32 random bytes encoded as hex and must remain stable across deployments. Stripe sends checkout completion, asynchronous payment success, refund, and dispute events to `/api/stripe/webhook`. See `stripe-billing.mjs` for the exact event names.

The Durable Object is selected by billing mode, so test and live ledgers remain separate. Synchronous SQL transactions protect balances, and the gateway waits for durable storage before sending provider requests. Restart recovery retains uncertain reservations. Preserve this single-ledger design until global budget coordination has been redesigned.

The deployment source branch is `codex/hosted-credits`. Build the Mac app with `S2T_CREDITS_URL=https://s2t-credits.ae-chef-license.workers.dev` so Sign in opens the deployed service.

Do not paste provider master keys into chat or embed them in the Mac app. Create dedicated provider keys for S2T, restrict them where supported, and enter them directly in the host's secret settings. Start with small prepaid balances and auto-refill off. The existing live configuration requires documented external spending limits; do not bypass those checks by inventing evidence. Provider auto-refill can be reconsidered after measured staging usage and an explicit spending policy.

## Private real-dictation testing

Stripe sandbox normally returns synthetic provider results. To test real dictation without real payments, set `S2T_STAGING_REAL_PROVIDERS=explicitly-enabled` and `S2T_STAGING_USERS` to the approved Clerk user IDs, separated by commas. Every dashboard and app request checks this allowlist. Keep the Stripe key in test mode.

This mode also requires the live-mode provider controls, pricing, OIDC configuration, and result encryption key described in `config.mjs`. Put provider keys in Cloudflare Worker secrets. Store reviewed pricing and provider-limit JSON as `S2T_PRICING_JSON` and `S2T_PROVIDER_LIMITS_JSON`. The Worker maps these into the shared configuration checks. Set OIDC issuer and JWKS to the configured Clerk domain, and audience to `s2t-credits`. Do not use fixture values as evidence of real account limits. Start with only the routes whose provider accounts have been configured.

For the Stripe server key, create a sandbox restricted key with Checkout Sessions write access and Payment Intents, Refunds, and Disputes read access. The legacy Payment Link path additionally needs Payment Links read access. Store it as `STRIPE_SECRET_KEY` in Cloudflare. CLI authorization is for administration and is not a permanent server credential.

## Before live purchases

The service is deployed in Stripe test mode. Test credit balances do not represent real purchases. Live provider access stays disabled until dedicated provider credentials and reviewed limits are configured. Production still needs reviewed provider prices and billing rounding, a decision on taxes and Stripe fees, independent provider usage reconciliation, monitoring, consistent encrypted backups and restore checks, and a policy for retained encrypted results. The current policy blocks usage when reconciliation or pricing becomes overdue. These restrictions remain in force.

The current credit conversion is inherited from the prototype: $1 buys 100 credits funding $0.90 of provider usage. The remaining $0.10 is before Stripe fees, infrastructure, refunds, and taxes. Do not treat that as a confirmed profit margin. Taxes, discounts, and shipping are rejected by fulfillment until a matching pricing policy exists.

## Verification

- `npm run test:cloudflare`: real Cloudflare local runtime with isolated durable storage, mocked Clerk/Stripe endpoints, payment replay, simultaneous requests, exact balances, and persistence across runtime restarts.
- `node hosted-check.mjs`: deployed service and real Clerk development test account. It uses short-lived test sign-in tokens and never screenshots.
- `npm test`: ledger, checkout, payment, identity, provider, and failure cases with isolated fixtures.
- `npm run test:browser`: starts its own temporary service and drives the dashboard without screenshots or clipboard access.
- `npm run test:native`: starts an isolated demo service and exercises the packaged Mac client's real HTTP transport, authentication, editing request, and exact balance change.
- `build/S2T.app/Contents/MacOS/S2T --verify-credits`: preview-only native settings, key masking, readiness, and supported-route checks.

Reference documentation: [Cloudflare Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [Clerk JavaScript setup](https://clerk.com/docs/js-frontend/getting-started/quickstart), [Clerk JWT templates](https://clerk.com/docs/guides/sessions/jwt-templates), and [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create).
