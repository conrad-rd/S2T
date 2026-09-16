# S2T Credits

The Cloudflare test service is [S2T Credits](https://s2t-credits.ae-chef-license.workers.dev). See [SETUP.md](SETUP.md) for app sign-in, Stripe Checkout, secrets, and deployment. The service uses a SQLite Durable Object and targets the Workers Free limits. Real provider access remains disabled until dedicated credentials and reviewed spending controls are configured.


Run `npm start` from this folder, then open http://localhost:4317. Node 22.13 or newer is required. The service listens only on 127.0.0.1.

The local dashboard now uses the transactional billing ledger. Add demo credits, create a key, run a metered synthetic request, inspect the remaining balance, and revoke the key. A synthetic request costs 0.01 demo credit. No real provider request or payment occurs in demo mode.

## Implemented controls

- Integer micro-dollar accounting. $1 purchases 100 credits, funding $0.90 of provider usage. One credit is 9,000 micro-dollars. Fractional charges never round to whole credits.
- Immutable balance entries and an audit log. SQLite WAL, FULL synchronization, foreign keys, transactions, and unique payment/request/receipt identifiers enforce consistency across database connections.
- Atomic reservations before dispatch. The same money cannot fund simultaneous requests. Actual cost settles once; unused reservations return to available funds.
- A client must supply a stable `Idempotency-Key`. Reusing it with changed input is rejected. Completed retries return the encrypted saved result for one hour. Unknown outcomes never resubmit.
- A durable submitted state is committed before a provider call. On restart, unsubmitted reservations release; submitted requests become uncertain and stop new spending. A second server cannot claim the same database while its owner is alive.
- Cancellation only releases work that has not been submitted. Disconnects and timeouts do not prove that a provider did no work.
- Strict provider destinations, separate credentials, redirect rejection, response/upload limits, model allowlists, output limits, and server-side mono PCM WAV duration validation. Unknown models or expired pricing cannot reach providers.
- Initial internal limits, including configured provider funding fees: $0.25 per request, $1 per account per UTC day, $3 per provider per UTC day, $5 service-wide per UTC day, $20 lifetime service spend. Two pending requests per account, 20 new requests per account per minute, plus HTTP/key/session rate limits. Unknown prior-day costs remain reserved against the next day's limit.
- Signed Stripe events are verified with the Stripe SDK. The server retrieves the authoritative Checkout Session and successful PaymentIntent before granting funds. Session and PaymentIntent uniqueness prevent duplicate grants across event types. Paid USD top-ups must be $1–$100.
- Partial refunds debit the ledger once. Disputes freeze affected accounts. Reversals arriving before checkout completion apply when the purchase is recorded. Dispute reversals are deliberately not automatically undone; operator review is required.
- Key hashing, expiration, revocation, account-scoped access, HttpOnly local sessions, exact-origin browser writes, bounded requests, CSP, and authenticated OIDC/JWKS identity for the live API.
- AES-256-GCM encryption for saved results, authenticated to each request ID. Results are inaccessible after one hour. Accounting records contain no input text or audio. Encrypted result bytes remain in the database until a production retention policy is implemented.
- Independent provider receipt and full-account reconciliation. Mismatches pause spending; overdue reconciliation blocks new work after 24 hours. Missing costs never become free usage.
- If independent evidence confirms a provider overrun, the operator can settle the actual expense while charging the customer no more than the original reservation. The service absorbs the difference and requires a revised pricing version before resuming.

## Files and modes

`server.mjs` uses `ledger.mjs`, `gateway.mjs`, `policy.mjs`, `providers.mjs`, `stripe-billing.mjs`, and `identity.mjs`. The former `store.mjs`, `test.mjs`, and `.data/demo.sqlite` are retained from the first prototype and are not used by the server or current test suite. The new ledger starts separately; old demo balances and keys are not migrated into paid accounts.

Modes have different databases and key prefixes. A database cannot be reopened under another mode.

- `demo`, the default: fake top-ups and synthetic providers only. No provider credentials are loaded. Keys start with `s2t_demo_`.
- `test`: only verified Stripe sandbox payments can add funds. Provider operations remain synthetic. Demo credit endpoints are disabled.
- `live`: verified identity and dedicated capped provider accounts are required. Missing configuration prevents startup. Real spending requires explicit enablement. This mode has not been exercised against real services.

Store data on a persistent local volume. `S2T_BILLING_DATA_DIR` overrides `.data`. Back up the entire database consistently using SQLite backup tooling, together with the result encryption key. Do not copy a database file alone while WAL writes are active. A restore requires independent Stripe/provider reconciliation before reopening spending; a stale backup is not an authoritative spend record.

## API

User-account endpoints use the local browser cookie in demo/test mode, or a verified OIDC bearer token in live mode. The browser UI is a local demo client; the browser now supports Clerk sign-in and recovery through Clerk account controls. Configure the `s2t` JWT template and publishable key as described in SETUP.md.

- `GET /api/account`: account balance, reservations, keys, and recent requests.
- `POST /api/keys`: issue a key once. `POST /api/keys/revoke` with `{ "id": "key-id" }` revokes it.
- `POST /api/checkout`: test/live with configured Stripe secrets. Accepts `{ "cents": 500 }` and a stable `Idempotency-Key`, then creates an account-bound Checkout Session for that exact amount. A stored purchase cannot change its amount or payment session.
- `POST /api/stripe/webhook`: signed Stripe events. Never use the browser success page as proof of payment.

Provider endpoints require `Authorization: Bearer <S2T-key>`:

- `GET /api/v1/balance`
- `POST /api/v1/requests`, plus a stable `Idempotency-Key` header.
- `GET /api/v1/requests/<id>`
- `POST /api/v1/requests/<id>/cancel`

Cleanup request body:

```json
{"provider":"openrouter","operation":"cleanup","text":"A sentence to edit."}
```

Transcription request body:

```json
{"provider":"assemblyai","operation":"transcription","audio":"<base64 mono 16-bit PCM WAV>"}
```

The current reviewed route shapes are OpenRouter cleanup through `openai/gpt-oss-120b` on `cerebras/fp16`, AssemblyAI Sync, and ElevenLabs Scribe v2. Audio is limited to two minutes. Other models, long batch transcription, OpenRouter audio/image requests, are not enabled. Native Mac integration supports these reviewed routes through Settings → Models → S2T credits. No silent provider fallback occurs.

## Operation and recovery

From this directory:

```sh
npm run admin -- status
npm run admin -- pause
npm run admin -- reconcile /path/to/provider-report.json
npm run admin -- review-pricing
npm run admin -- resume
```

These are local operator commands, not public HTTP endpoints. They use the selected mode and database. Do not grant customers filesystem or shell access. `resume` refuses unresolved requests/incidents. `review-pricing` requires a changed pricing version after an absorbed overrun. Restart the service with that reviewed policy before resuming live requests.

A reconciliation report contains independently obtained provider usage, not a report generated from this ledger:

```json
{
  "source": "Provider account export or authenticated reporting API",
  "generatedAt": "2026-09-14T12:00:00Z",
  "receipts": [{"requestId":"request-uuid","providerId":"provider-receipt-id","costMicros":90}],
  "totals": [{"provider":"openrouter","through":1789387200000,"totalCostMicros":90}]
}
```

Totals are cumulative inference charges for the dedicated provider account since its zero-usage start, through the stated cutoff. Funding fees are tracked separately in service expenses. Pending jobs must be resolved before a report covers their period. The importer records the report hash and detects mismatches. The hash establishes which evidence was used, not whether the operator supplied truthful evidence. Provider report collection is not automated yet; import before the 24-hour deadline.

## Live setup and remaining release work

A public Stripe link alone cannot configure fulfillment or reveal server secrets. No real credentials were inspected or used for tests.

Live mode requires these environment settings, read only on the server:

- `S2T_BILLING_MODE=live`, `S2T_ENABLE_LIVE_SPENDING=explicitly-enabled`
- `S2T_PUBLIC_ORIGIN`, an exact HTTPS origin
- `S2T_OIDC_ISSUER`, `S2T_OIDC_AUDIENCE`, `S2T_OIDC_JWKS_URL`
- `STRIPE_SECRET_KEY`, a restricted live key with Checkout Session creation and the read permissions needed for payment, refund, and dispute verification; `STRIPE_WEBHOOK_SECRET`; `CLERK_PUBLISHABLE_KEY`
- `S2T_PRICING_FILE`, a reviewed policy matching `policy.mjs`, with an expiry no more than 24 hours away
- `S2T_PROVIDER_LIMITS_FILE`, operator evidence of dedicated provider limits reviewed within 24 hours
- `S2T_RESULT_KEY`, 32 random bytes encoded as 64 hex characters, stored in a secret manager
- Keys only for enabled providers: `OPENROUTER_API_KEY`, `ASSEMBLYAI_API_KEY`, `ELEVENLABS_API_KEY`

External-limit evidence must contain `reviewedAt` and a `providers` object. Each enabled provider needs `autoRecharge: false`, `overdraftDisabled: true`, a positive `hardCapUsd`, and an `evidence` description. Initial combined external caps cannot exceed $20. This is operator-supplied evidence, not an automatic check or configuration of the provider's limits. If a provider cannot enforce a suitable cap, keep it disabled. A warning email or budget alert is not a spending cap.

Before taking customer money: exercise configured Clerk sign-in/recovery and Stripe checkout, confirm tax treatment, verify dedicated provider limits, replace fixture prices with reviewed contracted rates and billing rounding, run spending-capped staging calls, automate provider report collection, configure monitoring and consistent backups, implement result retention, and obtain an independent security review. Unsupported taxes, discounts, and shipping are rejected rather than silently granting the wrong amount; resolve that business policy before enabling checkout.

This server intentionally refuses live mode on Vercel. SQLite on a function's temporary filesystem cannot be the financial authority. Keep the website on Vercel; either deploy this service on one persistent host or port the transaction layer to managed PostgreSQL and retest concurrency and recovery before deploying Vercel functions.

## Verification

`npm test` exercises the actual ledger and HTTP application with isolated temporary databases, synthetic WAV, signed fake Stripe events, real JWT signatures, mock provider transports, concurrent SQLite connections, and forced process termination. `npm run test:browser` verifies the running local dashboard through DOM interactions. Neither command uses real credentials, microphones, user clipboard contents, or screen capture.
