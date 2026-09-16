# S2T credit purchases

Use Render for the server, Clerk for customer accounts, and Stripe Checkout for one-time top-ups. Keep the marketing website on its existing host. The server keeps its SQLite ledger on a persistent disk. Run one instance. A second instance or serverless deployment needs a different database design.

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

`render.yaml` describes a single paid Render service with a persistent disk, starting in Stripe test mode. `Dockerfile` installs production dependencies without local databases or secrets. Set the public HTTPS origin to the service's actual address, configure Clerk and Stripe, and register the webhook URL. Use server environment secrets for Stripe and provider credentials. The deployment branch is `codex/hosted-credits`. Publish only the `billing-local` service from that branch. Build the Mac app with `S2T_CREDITS_URL` set to the verified hosted origin so Sign in works without entering an address.

Do not paste provider master keys into chat or embed them in the Mac app. Create dedicated provider keys for S2T, restrict them where supported, and enter them directly in the host's secret settings. Start with small prepaid balances and auto-refill off. The existing live configuration requires documented external spending limits; do not bypass those checks by inventing evidence. Provider auto-refill can be reconsidered after measured staging usage and an explicit spending policy.

## Private real-dictation testing

Stripe sandbox normally returns synthetic provider results. To test real dictation without real payments, set `S2T_STAGING_REAL_PROVIDERS=explicitly-enabled` and `S2T_STAGING_USERS` to the approved Clerk user IDs, separated by commas. Every dashboard and app request checks this allowlist. Keep the Stripe key in test mode.

This mode also requires the live-mode provider controls, pricing, OIDC configuration, and result encryption key described in `config.mjs`. Put provider keys in Render secrets. Add reviewed pricing and provider-limit JSON as Render secret files and point `S2T_PRICING_FILE` and `S2T_PROVIDER_LIMITS_FILE` at their `/etc/secrets/` paths. Do not use fixture values as evidence of real account limits. Start with only the routes whose provider accounts have been configured.

For the Stripe server key, create a sandbox restricted key with Checkout Sessions write access and Payment Intents, Refunds, and Disputes read access. The legacy Payment Link path additionally needs Payment Links read access. Store it as `STRIPE_SECRET_KEY` in Render. CLI authorization is for administration and is not a permanent server credential.

## Before live purchases

The implementation is locally verified, not a launched payment service. Actual Clerk sign-in, Stripe sandbox events, provider billing, and Render deployment require your external accounts and have not been exercised here. Production still needs reviewed provider prices and billing rounding, a decision on taxes and Stripe fees, independent provider usage reconciliation, monitoring, consistent encrypted backups and restore checks, and a policy for retained encrypted results. The current policy blocks usage when reconciliation or pricing becomes overdue. These restrictions remain in force.

The current credit conversion is inherited from the prototype: $1 buys 100 credits funding $0.90 of provider usage. The remaining $0.10 is before Stripe fees, infrastructure, refunds, and taxes. Do not treat that as a confirmed profit margin. Taxes, discounts, and shipping are rejected by fulfillment until a matching pricing policy exists.

## Verification

- `npm test`: ledger, checkout, payment, identity, provider, and failure cases with isolated fixtures.
- `npm run test:browser`: starts its own temporary service and drives the dashboard without screenshots or clipboard access.
- `npm run test:native`: starts an isolated demo service and exercises the packaged Mac client's real HTTP transport, authentication, editing request, and exact balance change.
- `build/S2T.app/Contents/MacOS/S2T --verify-credits`: preview-only native settings, key masking, readiness, and supported-route checks.

Reference documentation: [Render disks](https://render.com/docs/disks), [Clerk JavaScript setup](https://clerk.com/docs/js-frontend/getting-started/quickstart), [Clerk JWT templates](https://clerk.com/docs/guides/sessions/jwt-templates), and [Stripe Checkout](https://docs.stripe.com/api/checkout/sessions/create).
