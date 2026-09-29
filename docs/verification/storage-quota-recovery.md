# Billing database quota recovery, September 20

## Cause

The operator health request returned HTTP 503. Cloudflare's live Worker tail identified `Exceeded allowed rows written in Durable Objects free tier` while constructing the SQLite ledger. The public `/health` endpoint still returned 200 because it never reached the database.

The scheduled streaming cleanup ran every minute and updated every historical session with an expired token, including records whose encrypted token was already NULL. An independent fixed-clock workload with 100 completed sessions reproduced 144,000 unnecessary row updates in one idle day. That exceeds the free plan's 100,000 daily row-write allowance. It was a backend bug, not evidence of excessive customer usage.

Cloudflare's checkout confirmed the user's approved Workers Paid subscription was active at $5/month after the user completed payment. The paid plan removes this daily free-plan allowance, but does not remove all platform limits, paid usage, payment failures or provider outages. See [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/) and [platform limits](https://developers.cloudflare.com/durable-objects/platform/limits/).

## Repair

Streaming cleanup updates only expired tokens whose ciphertext is still present. The same full-day workload now writes zero historical rows. Live tokens are still cleared once and the normal expiry window still releases their holds. Immutable debits and historical session records are preserved.

Public health now reaches the Durable Object and reads the spending-pause metadata without writing a rate counter. It returns 503 on a spending pause or database failure. Recognized Cloudflare quota failures return a safe `storage_quota` error and log a fixed diagnostic without request content. A successful health response checks database access and pause state; it does not prove provider availability or every future database write.

The exact-Worker release check now includes the full-day maintenance workload, one-time token expiry, hold release, database-backed health, quota failures and other database failures. Five of those checks failed against the previous published artifact. All six pass against the proposed repair.

The packaged lifecycle check also exposed a separate compatibility bug: the current native default selected GPT-OSS 120B with an empty host, while the deployed catalog permits it on `cerebras/fp16`. Restore that default and repair the legacy empty host only when the service advertises the fixed Cerebras route and does not support automatic routing. Preserve explicit hosts, other models and dynamic-catalog routing. This is verified through the actual packaged app against the exact Worker, not by weakening the fixture catalog.

## Remaining operational gaps

- Provider funding allocations are accounting only. Automated provider replenishment remains unimplemented. The last recorded OpenRouter and AssemblyAI settings had autopay off. No current provider balance or automatic refill was verified in this repair.
- Failed recurring payments, provider outages, rate limits, rejected model requests and exhausted prepaid balances can stop processing independently of customer wallet credit.
- Integrity failures may deliberately pause spending. Unknown provider outcomes may retain affected holds until reconciled; they must not be blindly retried or treated as unused credit.
- Missing Stripe dispute-resolution event subscriptions remain unverified. They can prevent correct automatic dispute recovery. Stripe or sign-in outages can interrupt purchases and account management independently of existing app requests.
- Public production remains restricted to the existing allowlist. Hosted xAI is unconfigured, and old direct streaming billing remains private beta.
- No continuously operated external uptime alert or provider-balance alert has been established by these checks. A health endpoint alone does not notify the operator.

Passing fixtures does not establish an uptime guarantee or a defensible numerical probability of recurrence. Live provider inference and real payments are not used as release tests. A one-time healthy read must be reported as a point-in-time result.

Evidence and deployment records are under `build/reservation-recovery`. Release status and exact artifact identifiers are recorded after publication below.

## Published artifacts

Worker `5cc9cca5-6690-4c6c-b27b-9fb901acef05` is deployed to 100 percent of traffic. Published source matches SHA-256 `889882c866ec2e8f4863e0f0a5c50f2f486cd03b2a4b597977f06c1d5f71c8b5` byte for byte. The scoped patch preserves all other live code, secrets, namespace bindings, pricing and account restrictions. Unpublished model-catalog and direct-ledger work is excluded.

Canonical S2T 1.0.1 Build 684, compiled `2026-09-20T10:42:18Z`, is packaged at `build/S2T.app`. Executable SHA-256 is `616638d1a3fc60b7175a2bd469b62f0e9b5b185c143a9894090c947196d13bca`. Verification passed 400 Swift tests, 164 billing tests, 37 existing exact-Worker audit cases, six storage/health cases, isolated purchases/refunds, scheduled expiry and twelve complete packaged streaming-plus-cleanup cycles. Deliberately lost authorization, cancellation and completion responses recovered without duplicate charges or stranded holds. Packaged build, credits, models and the current file-transcription startup checks passed without live inference, payment, microphone or screen capture.

Immediately after deployment, public and operator health still returned HTTP 503 with Cloudflare's free-plan quota rejection despite the active paid subscription. The dashboard showed 105.21k SQL rows written and 1.04 MB stored. This is recorded as a remaining platform activation problem until an actual healthy read succeeds, not as restored service.

## Recovery confirmed

At `2026-09-20T11:02:28.630Z`, the live operator request returned HTTP 200, `paused:false`, no open incidents and no pending requests. Public database-backed health also returned 200. The operator route's existing rate counter requires a database write, so this verifies more than the earlier edge-only health response. It does not constitute live provider inference.

The follow-up operator check at `2026-09-20T11:04:29.311Z`, after further scheduled cleanup cycles, returned the same healthy result.

Paid-plan activation was confirmed before 10:36 UTC, but Cloudflare continued enforcing the previous free-plan write allowance for more than twenty minutes. Both account and script usage models were already `standard`. Reapplying unchanged account settings was refused with HTTP 403 and made no change. A bounded runtime-restart candidate was tested locally and preserved its fixture balance, but production recovered before it was deployed. The candidate is archived under `build/reservation-recovery/runtime-reset`, marked NOT DEPLOYED. Its code and check were removed from the active release path. No runtime reset or new namespace was used; the original ledger stayed in place.

The user declined contacting support. No support message was sent. The prepared draft was not submitted. The deployed Worker remains `5cc9cca5-6690-4c6c-b27b-9fb901acef05` with the published hash above. Automatic provider refills, continuous operational alerts and missing dispute subscriptions remain unresolved as listed above.
