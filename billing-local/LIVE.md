# Live S2T credits

## September 29 security release

Worker `6e3f3992-384d-4aa0-bd10-9203a2b3788e` serves 100% of traffic after the 23:22 UTC September 28 deployment (September 29 in Berlin). The scoped release removes historical client-reported streaming settlement, unreviewed catalog speech, the removed vision route, and the two token-priced GPT-4o transcription routes without an enforceable upstream ceiling. Nineteen reviewed OpenRouter speech choices remain. Whisper V3 and V3 Turbo reserve the ten-second upstream minimum but charge actual receipts. Authentication precedes durable rate writes, rejected rate attempts cause no further writes, concurrent provider-readiness checks share one request, stalled uploads time out, and paid replay bypasses catalog work.

Exact source readback SHA-256: `3fa10fc3dc7083bde2b1fae63b3212235d97b80a78ec9c9ee61927677c5ec87c`. All 180 local tests and eight exact-artifact scripts passed; the new security check demonstrates ten before/after cases. Public health/config and wallet pages returned 200, invalid app keys returned 401, and bindings and wallet assets were preserved. No live payment or billable inference was used.

The full working tree remains a separate candidate: funding/reconciliation gates and the guest credential migration still need their documented operational prerequisites. Do not publish it with a blanket deploy. Current live Stripe event subscriptions could not be verified because both the connector and available browser require authentication. See [the audit report](../docs/verification/credits-security-2026-09-29.md) for exact evidence, scope, and remaining work. Earlier entries below describe their dated releases and may be superseded by this one.

## September 20 OpenRouter account replacement

The user subsequently clarified that the intended replacement was the management credential. The new account's `S2T backend management` key is now saved as `OPENROUTER_MANAGEMENT_KEY`, deployed in Worker version `ab0ad39c-cfc6-4c6c-a919-800a3c06c8c8` at 21:40 UTC. OpenRouter shows it Active, expiring October 20 at 23:38 Europe/Berlin. Code, runtime and binding metadata remained unchanged, and production health returned HTTP 200. The separate inference key below remains necessary for the current shared-request backend. Per-user OpenRouter key provisioning and limit synchronization are not implemented by this credential replacement. See `docs/verification/openrouter-management-key.md` for verification and limits.

At 21:13 UTC, the user requested replacing the shared S2T credits OpenRouter account. The production `OPENROUTER_API_KEY` secret was replaced through Wrangler. Cloudflare deployed version `83b82098-ba6c-4cf4-b2f7-98f8cbedd3d1` at 100%, with trigger `secret`, retaining the published Worker code. Local source was not deployed. The Mac app's personal key and the separate management secret were not changed.

The replacement authenticated successfully against OpenRouter's read-only current-key endpoint. It is an inference key, not a management key, and reports a configured spending limit. This supersedes the previous account's uncapped-key evidence below. The remaining key allowance does not establish the provider account's funded balance or auto-top-up settings. No billable inference was run. After the change, production `/health` and `/api/config` both returned HTTP 200 with live mode and real providers enabled. The new secret was passed through hidden terminal input and an in-memory pipe, with Wrangler logging directed to `/dev/null`; it was not written to source or a credential file.

The production wallet is https://credits.s2t.app. Vercel serves static assets and proxies `/api/*` to the Cloudflare Worker. The Worker owns all balances in its live Durable Object and stores the Stripe and provider credentials as encrypted secrets. The macOS app's existing Worker address remains valid; browser visits redirect to the wallet.

The signed-in dashboard remains restricted to the configured verified operator email. Public guest purchases at `/prepaid.html` use separate browser sessions, one prepaid key and saved recovery codes, without access to account key-management tools. `S2T_GUEST_CHECKOUT=enabled` opens those sales. Email recovery remains disabled until a mail sender is configured. The production Clerk instance is invite-only, with immutable email addresses and email-code sign-in. Its `s2t` JWT template includes `aud`, `email`, and `email_verified`.

Live Stripe account and webhook identifiers are held in private deployment records. The webhook endpoint is the Worker's `/api/stripe/webhook`. `STRIPE_LIVE_SECRET_KEY` and `STRIPE_LIVE_WEBHOOK_SECRET` are distinct from the retained sandbox secrets. Mode-specific Durable Objects keep sandbox money separate. Never copy sandbox balances into the live ledger.

AssemblyAI Sync uses Universal 3.5 Pro, up to 120 seconds, at $0.45 per hour rounded to whole billed seconds. OpenRouter cleanup uses GPT-OSS 120B on Cerebras without host fallback, bills returned usage cost, and sends price ceilings of $1 per million input tokens and $2 per million output tokens. Its funding fee allowance is 5.5%. The user approved removing the dedicated hosted key's earlier $5 cap. OpenRouter current-key readback confirmed limit=null on September 19. The provider account remains prepaid with autopay off. AssemblyAI is prepaid with autopay off. Provider accounts need funds independently of Stripe purchases; customer payments do not automatically refill them.

Requests reserve credits before contacting providers. There are no automatic per-request, account-daily, global-daily, provider-daily or lifetime spending caps. Available balance and user-selected API key limits govern customer spending. Technical concurrency and request-rate controls remain. Historical streaming holds were based on the STT rate and capped by available balance or the user's remaining key budget. New streaming issuance is retired; issued-token holds now remain reserved until independent reconciliation or audited writeoff. Unknown outcomes retain only the affected hold; integrity failures can still pause spending for reconciliation. Operator reconciliation requires S2T_OPERATOR_KEY, never a customer app key. Writeoffs release the customer hold without inventing a provider receipt.

The production pricing policy has no calendar expiration. Update it when provider rates or models change. OpenRouter request price ceilings fail closed on higher rates. AssemblyAI's configured per-second rate should be reviewed against https://www.assemblyai.com/blog/speech-recognition-cost when its pricing changes.

Operator-only balance adjustments use `set_balance` with an existing account ID, a whole `targetCredits` amount, a unique `id`, and a recorded `reason`. The operation appends an adjustment instead of changing purchases or usage, rejects frozen accounts and pending holds, and does not call Stripe. Reusing the same ID never restores credits spent after that adjustment. Use the operator `account` action to read back the balance.

Deploy the Worker with `npm run deploy:cloudflare` from `billing-local`. Deploy current wallet assets with `node billing-local/frontend/deploy.mjs` from the repository root. Vercel's `s2t-credits` project has no provider secrets or persistent database. Do not deploy the separate website's old PostgreSQL billing service as the live wallet.

Verify with `npm test` and `npm run test:cloudflare` in `billing-local`, then inspect `/health` and `/api/config` on the deployed Worker. A checkout return never grants credits; only a verified Stripe webhook does. A real paid top-up and subsequent app request are required to verify settlement end to end.

## Verified production result

On September 16, the account paid $1 through live Stripe Checkout and received exactly 100 credits through the signed webhook. A 4.68-second synthetic speech clip was transcribed by AssemblyAI and cleaned up by GPT-OSS 120B on Cerebras. Both requests settled, leaving 99.91633333333333 credits with zero holds and spending unpaused. The first setup transcription used an incorrect receipt field and was written off at S2T's expense. Sync receipts now use `session_id`. Cloudflare outbound requests use manual redirects and reject non-success responses, so credentials never follow a redirected provider URL.

On September 17, the wallet showed 99.8469 credits after two additional settled transcription requests. A later no-text setup request was written off at S2T's expense. Spending is unpaused with no pending holds or unresolved incidents. Completed AssemblyAI responses with an empty text string and a valid receipt now settle normally, retaining the actual configured usage charge; the app reports "No speech was detected" instead of suggesting that funds remain reserved. Missing text fields or receipts still fail closed.

Four settled receipts still await independent provider reconciliation. The earlier operator check incorrectly hashed the ledger rows themselves as evidence. Their reconciliation flags were reopened with an audit correction, preserving settlement, charges and balances. Successful provider responses establish the tested functionality, not an independent invoice audit.

The silence fix is deployed in Worker version `50324d3d-351c-4cc2-b3af-a5ed8229f54d`. Verification passed 44 billing tests, the Cloudflare runtime integration checks with mocked external services, and 305 Swift tests. The canonical macOS app was packaged as S2T 1.0.1, Build 548.

The live service test used a dedicated S2T app key and generated speech, without microphone capture or real Keychain access. Real foreground typing and microphone dictation were not tested. Native app automation timed out when accessing its settings, so saving the user's current S2T key and selecting S2T credits in the running app remain unverified. The unused key created during the interrupted setup was revoked. The existing active key was preserved.

## September 18 provider settings update

Worker version `91de94ba-7586-4945-996b-5dbf3c95443e` adds configured model choices to the authenticated balance response and accepts the selected model, host, reasoning and routing options. The cleanup suggestions are GPT-OSS 120B on Cerebras, Muse Spark 1.3 Contributor, and GPT-OSS 20B. The latter two use automatic hosting within the existing $1/$2 per-million-token price ceilings; billing still settles returned provider cost. Contributor requires explicit request-level consent before reservation. Ordinary routes keep data collection disabled.

This deployment was based on active version `d6c6710a-50c5-4442-9435-741a5e5588c3`, with only the policy/provider modules and authenticated balance response changed. It preserves the existing assets, secrets, namespace bindings, account allowlist, limits and ledger implementation. Unpublished expiry/privacy maintenance and draft website policies remain unpublished. A full `wrangler deploy` of the current working tree would include those separate changes and must be reviewed independently.

The exact deployed artifact is `build/s2t-provider-worker.js`, with its reviewed diff in `build/s2t-provider-worker.diff` and SHA-256 `c2ddb7dff6441ecbb347d152a410c5805cbcccec8367d9d96c9794eb5f8b2fb7`. `node provider-deployment-check.mjs` from billing-local tests that retained artifact with synthetic accounts and configured model choices. The deployed source was read back and matched byte-for-byte; public health/config endpoints returned HTTP 200 in live mode. No real account records, payments or provider inference were used for verification.

Canonical S2T 1.0.1 Build 593 shares model controls between S2T and OpenRouter, persists independent per-model options and Contributor consent, and displays available credits beside the S2T key. Verification passed 317 Swift tests, 57 billing tests, Cloudflare runtime checks, packaged model/key/credits/build checks and the packaged native HTTP contract test. The new models' live provider access, output quality and latency remain untested.

## September 18 key limits update

Worker version `00ff32ad-b8b1-4813-b709-19cad0e7e66d` adds per-key credit caps, UTC reset periods and permanent expiry. Existing keys retain their expiry and have no additional cap unless configured. Pending holds and settled ledger debits count toward the cap. Wallet credits never refill when a key allowance resets. Only authenticated account owners can configure key limits. The native app receives calling-key allowance metadata separately from wallet balance.

The exact live source is `build/s2t-limits-worker.js`, SHA-256 `8d2126049fb9fc607c107ed392a020211cd15d966c234b2239f051cfc580ff80`. Its scoped diff and deployment record are beside it. All existing bindings, assets, allowlist and pricing were preserved, and source readback matched. Unrelated unpublished privacy maintenance remains excluded. The exact artifact passed `node limits-deployment-check.mjs` with fake accounts and mocked external services. No real payments or provider requests were made.

Canonical S2T 1.0.1 Build 595 displays credits above Policies in the bundled Bitcount Prop Single font. The app, 319 Swift tests, 63 billing tests, exact Worker fixture and browser limit controls passed verification.

The website limit controls are live in Vercel deployment `dpl_AGc8nWAoLhGBy5G5irT4MJwu2h6F`. Publishing from an isolated directory with the existing project binding and authenticated account resolved the earlier author-metadata deployment failure without changing any identity or access checks. All 15 production assets matched the tested release, and the complete browser limit-editing flow passed against the public site with an isolated local ledger. The existing site layout, copy and policy pages were retained. Worker configuration, budgets, real balances and pause state were unchanged. See `docs/verification/key-limits.md`. Do not publish unrelated pending frontend/privacy changes with the broad deploy helper.

## September 18 routing recovery

Worker `97565150-4a2e-4e3b-a7a7-12938f028dee` fixes the service-wide pause caused by valid but truncated cleanup completions. It settles valid receipts before returning a cleanup error, releases definitively rejected provider requests, and adds three priced OpenRouter transcription choices. Cleanup output capacity is 2048 tokens within existing budgets. Exact scoped source and readback SHA-256: `506f7c10b77e68cf2360598e4fc00c248653072268176a53a366914797cc29f4`, under `build/routing-repair`.

The user approved deployment and recovery. One incomplete-cleanup incident was resolved through the existing audited writeoff, with S2T absorbing under USD 0.02 and releasing the customer hold. Normal resume checks passed. Health then showed no pause, pending request or open incident. Existing secrets, assets, allowlist and key limits were preserved. No real inference or payment was used to verify the repair. See `docs/verification/routing-recovery.md` for limits and measurements.

## September 18 dashboard publication

The complete credits dashboard is live in Vercel deployment `dpl_HhtuGXcS5DBeyNmZW1pqmeE7NBN5`. It shows balance, last use/device and a 7/30/90-day UTC usage chart, moves Add credits into a dialog, and collapses activity, top-ups, keys and pricing. All credit usage values use four decimal places. Existing key-limit controls, policies, authentication and checkout remain available. All 15 production assets matched the tested stage. Billing, retained Worker, mock checkout and public-site browser checks passed with isolated data. No service configuration or real account values changed. See `docs/verification/credits-dashboard.md`.

## September 18 S2T brand refinement

Credits frontend deployment `dpl_Dz9UkdjGZgmb2yf4D9HdvEHpzerp` adds the original-logo stroke chart, bundled Bitcount numerals, an asymmetric balance layout and plain period controls. It removes credit-button arrows, amount spinners and the gradient chart card. All 17 live assets matched the tested release. Arrow, proportional-chart, typography, mobile, account, limits and mock checkout checks passed. No Worker, payment configuration or real account values changed. See `docs/verification/credits-dashboard.md`.

## September 19 margin and refunds

New purchases now fund 80% provider usage, retaining a 20% margin before fees. One displayed credit represents $0.008; the price stays $1 per 100 credits. Existing provider-dollar balances are preserved, and refunds use each purchase's original conversion. Worker version `096a9868-d3fa-4593-b2ae-436502f99af3` was verified by exact source readback and isolated runtime checks.

The operator `funding` action reports the requested 70/30 OpenRouter/AssemblyAI split and usage-earned $5 batches. It does not move money or authorize a payout. Automated provider refills remain unimplemented. Refund terms allow refunds of unused paid credit based on actual usage, without a $5 forfeiture. Statutory rights remain intact. See docs/verification/provider-funding.md for the accounting behavior and remaining funding work.

The matching pricing/refund pages are published on credits deployment `dpl_5doi6DFrGzACwGe5skkoQM445Wsy` and main-site deployment `dpl_GM13w3nPpYhhAEiZhmXRt8JfZYWc`, preserving their prior assets and privacy wording. Post-deployment DOM checks passed on both domains. Canonical S2T 1.0.1 Build 640 includes the matching offline terms and refund pages.

## September 19 profitable pricing

New purchases require $5–$100 and fund $0.005 per credit, with 100 credits per dollar. Half of gross receipts funds provider usage; the other half covers tax, fees and S2T. This supersedes the earlier 20% margin plan. Existing provider-dollar balances and checkout quotes retain their original value. Refunds use each original purchase grant and actual unused credit.

Worker `1e6ddc0b-e2a7-45c1-b998-98c47df1e81a`, credits `dpl_7o96ggbvyWBVNvDMKGqg3bfjwNdi`, and main site `dpl_Fz2ms3EYf26zPq89Gb7suWQMkQok` are published. Canonical S2T 1.0.1 Build 650 bundles matching policy pages. Exact Worker readback, isolated runtime checks, live site DOM and simulated dashboard billing passed. Tax collection and automatic provider refills remain unconfigured. See docs/verification/profitable-pricing.md.

## September 19 provider cost recovery

Worker `65270a59-74c3-42a7-9322-e0a9a552c3bb` accepts bounded precise decimal and scientific provider costs. Malformed costs retain only the affected hold and no longer pause all usage. Existing ledger integrity checks remain. The single live invalid_cost incident was resolved by audited S2T writeoff; health confirmed no pause, pending holds or open incidents. All 125 billing tests and exact Worker runtime checks passed. See docs/verification/provider-cost-recovery.md.

Optional Jev decisions are live in Worker 3c769a36-c898-4fc1-aeaa-1d4e274b6b66. The openrouter:decisions route accepts pinned typesafe/jev-1.13 and uses existing account/key limits, reservations, actual-cost settlement and encrypted replay. Scoped artifacts and source readback are in build/jev-credits. Exact Worker fixture checks passed; no real inference or payments were used. Live health was unpaused with no open incidents. See docs/verification/jev-cleanup.md.


## September 19 billing audit and AssemblyAI recovery

Worker `d15274e0-7af0-4e7c-af17-6354c91cd9eb` fixes dispute restoration, partial reversals, stale freezes, unused holds after storage failure, provider error isolation, receipt retention, streaming exposure limits and retryable writeoffs. AssemblyAI Sync 404 falls back to the reviewed batch route. Operator pricing recovery and provider-report reconciliation are available. Exact source readback matched the tested artifact. All 143 billing tests, 15 exact-artifact cases and complete isolated payment/usage flows passed. The app is S2T 1.0.1 Build 658 with 389 passing Swift tests. See `docs/verification/billing-audit.md`.

Live spending is unpaused. One interrupted OpenRouter hold was written off at S2T's expense; an active AssemblyAI authorization was preserved. Stripe still needs the updated, closed and funds-reinstated dispute events enabled after connector reconnection. Hosted xAI is not configured. Provider auto-refills and independently verified public streaming billing remain unfinished.

## September 20 storage quota recovery

Worker `5cc9cca5-6690-4c6c-b27b-9fb901acef05` stops repeated historical token-clearing writes and makes public health reach the real database. The former cleanup rewrote 144,000 rows per idle day with 100 completed sessions. The repaired workload writes zero historical rows. Exact upload/readback and the full release gate passed. S2T 1.0.1 Build 684 also repairs the blank default GPT-OSS 120B host that was incompatible with the deployed fixed catalog. Current native settings and legacy recordings remain supported.

The user purchased the approved Workers Paid plan. Cloudflare initially continued rejecting writes under its old free-tier quota. At `2026-09-20T11:02:28.630Z`, live operator health returned HTTP 200, spending unpaused, no incidents and no pending requests. Public database-backed health also returned 200. No support case or runtime reset was required. See `docs/verification/storage-quota-recovery.md` for exact verification evidence and the delayed activation. Existing statements above describe their dated checks, not continuous availability. Provider refill automation, continuous external outage/balance alerts and missing Stripe dispute subscriptions remain separate unfinished work.


## September 19 pending streaming recovery

Worker `933e55b4-b2cc-4acc-8f5e-bb9f426ddd1d` separates streaming capacity from normal request slots, frees completed-session capacity, accepts cancellation by the original request identity and schedules expiry every minute. Production readback matched the exact tested source. Live health returned no pause, incidents or pending requests. S2T 1.0.1 Build 664 includes cancellation recovery. Tests reproduced the user's two-slot block and covered 12 completed recordings in one minute, reordered cancellation, alarm cleanup and the packaged app over localhost with deliberately dropped responses. See docs/verification/streaming-pending-recovery.md.

## Guest prepaid purchases, September 21

Public guest checkout is live at https://credits.s2t.app/prepaid.html. Buyers receive one key after confirmed payment and can recover the same key with their browser session or downloaded recovery code. The user chose recovery codes for launch. Optional email recovery is implemented but disabled without a configured sender. Worker `a7c87e00-6388-4e24-a8fd-86ce65eb3810`, Vercel `dpl_97QqSW6gak3PSLAA4vaUCc57A8Cw`. See `../docs/verification/guest-prepaid-keys.md` for the 171-test suite, isolated Cloudflare/browser verification and production readback.

## S2T credits model parity, September 23

Worker `904995e3-247d-4c9e-9e02-5f2a1ba2a08b` serves 100% of traffic. It adds billed vision and OpenRouter catalog model and host selection for speech, cleanup, and vision, including the Cerebras cleanup host. The pricing change adds `openrouter:vision`; other routes, the live allowlist, secrets, bindings, and the Durable Object migration remain the same. S2T 1.0.1 Build 815 is the matching app at `build/S2T.app`.

The exact Worker bundle SHA-256 is `d003ff9f156e92fd5969b9c8a909cb8149788b6c99396631f0f6a635c0fc0b9a`; the app executable SHA-256 is `1a7e721c7f39ee98508169d80dcc5d851b29c0fb4550a613f6644d74e0140d0e`. The release gate used synthetic provider and payment requests. Production health returned HTTP 200 after deployment. No real inference or payment was used to verify this release.

## Credit route repair, September 24

Worker `dfdd56ca-f58d-414f-88e0-d77c7fb39986` serves 100% of traffic. Its code validates a pinned OpenRouter host from that model's endpoint record without loading the full model catalog first, and adds an authenticated read-only warm route for the native app to call during recording. The uploaded bundle SHA-256 is `f5e717e9e0214a56fbd7ccf0810970e6256fc2f4815ed07608dfbcf05c2c0466`. The compiled diff against the previous deployed bundle contains only those two changes. Wrangler reported no static asset uploads; readback confirmed unchanged bindings and runtime settings. Live health returned HTTP 200. The matching canonical app is S2T 1.0.1 Build 840 at `build/S2T.app`. No paid inference or payment was used for this release check. See `../docs/verification/routing-latency.md` for the limits of the speed measurement.

## September 27 remediation candidate — not deployed

Direct streaming token issuance and client-reported streaming charges are removed from the current source. Paid early speech uses ordinary uploaded requests. Historical issued-token holds require independent provider reconciliation or audited writeoff; historical zero-settled tokens can receive verified provider expense without changing their customer debit. Dynamic OpenRouter speech models are withheld unless explicitly priced in policy. New paid requests stop when the 24-hour funding review or independent receipt/provider-total reconciliation is overdue, while exact idempotent retries remain available. Existing guest credentials require a separate credential key and a completed version-1 migration before the result key can rotate. No live provider, payment, credential, deployment, or real account was changed by this candidate. The historical funding evidence in private deployment configuration is stale and requires an actual operator review, not a date-only edit.
