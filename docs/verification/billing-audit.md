# Billing and provider audit, September 19

## Released changes

Cloudflare Worker `d15274e0-7af0-4e7c-af17-6354c91cd9eb` serves the billing repairs. Exact source readback SHA-256 is `fe09bfbd76b44bf83da8818f7857990460f3e28ec8f905adb7c4ad0e9f00a1d9`. Deployment started from current production source, preserved its secrets, allowlist, pricing, speech catalog and Jev route, and rejected a stale base before rebasing. No dashboard or policy assets changed.

Canonical app `build/S2T.app` is S2T 1.0.1 Build 658, compiled at 2026-09-19T16:10:12Z. The running app was not interrupted during recording.

- AssemblyAI short dictation uses `/v1/transcribe`. A definitive HTTP 404 falls back once to upload and batch transcription. Timeouts and server errors do not start another potentially charged request. Poll failures retain the submitted batch receipt. Hosted fallback uses Universal 3.5 Pro at the reviewed $0.21/hour batch rate, rounded to whole seconds, within the original higher Sync reservation. Direct personal-key batch keeps its extended-language fallback. Completed silent batch results stop immediately with a no-speech message.
- Partial disputes withdraw only the disputed amount. Won disputes restore the original purchase value once, account for refunds and ignore stale reopening events. Freeze state is recalculated after hold release and settlement. Debt alone does not prevent purchasing credit to cover it; active or lost disputes do.
- Provider model or cost validation failures retain their receipt and request hold without pausing unrelated accounts. Ledger receipt conflicts, confirmed overruns and accounting mismatches retain global safeguards.
- A failed durable reservation barrier releases the unused hold before any provider call. Streaming does the same before token issuance. Abandoned or completed authorizations still count toward the eight-session ceiling while a provider token could remain active.
- Operator writeoffs are idempotent. Their replay reports a settled, uncharged failure so the native client can start a fresh retry. Operator recovery now supports provider-report reconciliation and pricing review against the deployed policy version, never a caller-invented version. Pending health rows include only sanitized diagnostic reasons.
- Legacy quote migration changes the schema and grandfathered prices in one transaction. An interrupted migration can retry without silently losing the original 90% funding rate.
- Prompt vision supports direct xAI with its own key and an image-capability check. Successful cloud vision model checks are cached for five minutes, up to 32 entries. xAI validation is scoped to a hash of the key. Two synthetic descriptions use one metadata lookup and two inference requests, versus a lookup for each description. No claim about real provider inference latency follows from that request-count check.
- Writing supports OpenRouter, xAI, local text endpoints and Codex CLI. Existing saved settings decode without reset. New providers have separate model IDs; local calls have no authorization header, and only OpenRouter receives its host and routing options.
- Hosted provider selectors follow the authenticated service catalog. Unconfigured routes are disabled and stale selection actions are rejected. Direct personal-key routes remain independently selectable.

## Evidence

`npm test` in billing-local passed 143 billing tests. New fixtures reproduced failures before their corresponding repairs. `node billing-audit-deployment-check.mjs` passed 15 regression cases inside the exact deployed Worker.

`S2T_DEPLOYMENT_ARTIFACT=../build/billing-audit/worker.js node profitable-deployment-check.mjs` passed complete isolated HTTP flows for identity, account isolation, checkout deduplication, signed webhooks, concurrent reservations, priced provider dispatch, immutable usage, key limits, revocation, restart persistence, legacy refunds and provider-funding accounting. The fixture uses HTTP for its final legacy-account assertion because the test runtime's direct RPC bridge stalled. No real payment or provider inference was used.

`bash scripts/test.sh` passed 389 Swift tests. The canonical app is packaged through `scripts/build-app.sh`. Capture-free packaged checks cover build identity, local/provider menus, Models, Writing, credits and recording recovery, API key routing and model persistence. Fixtures use synthetic audio, fake keys, isolated storage and hidden windows. Logs and exact artifacts are in `build/billing-audit`.

Live health after deployment confirmed `paused:false` and no unresolved incidents. Request `1b32fb2a-0f32-42b7-b3df-6eadc3e8c9a8` had stopped with an in-flight OpenRouter call and no receipt. An audited S2T writeoff released its 16,184-microdollar reservation without charging the customer or inventing a receipt. A separate active AssemblyAI authorization was left untouched.

## Remaining setup and limits

The Stripe connector is expired. The server accepts dispute created, updated, closed, funds-withdrawn and funds-reinstated events, but the live endpoint still needs `charge.dispute.updated`, `charge.dispute.closed` and `charge.dispute.funds_reinstated` enabled after reconnection. Preserve its existing event list. Endpoint ID is `we_1UGNqXInYrOnzW7hZPrFz9t8`. No payment, refund or dispute was created in Stripe for verification.

There is no hosted `XAI_API_KEY` binding. Direct xAI routes work with the user's own configured key; hosted xAI choices remain unavailable until an operator configures and prices them. Local models and Codex run on the Mac, not through the paid cloud gateway. The Writing local option accepts a configured local text endpoint.

AssemblyAI streaming remains a private, allowlisted beta with client-reported usage. The exposure guard is improved, but this is not independently verified public billing. Unknown provider outcomes still require reconciliation or an audited S2T writeoff. A deployment or upstream outage can interrupt in-flight work; these repairs do not guarantee provider availability.

No paid live inference, microphone dictation or foreground text insertion was performed during this audit. Saved real credentials, recordings and clipboard content were not read for tests. Automatic provider refills remain unconfigured; the 70/30 funding split is accounting only. Tax collection remains unconfigured pending actual registration details.

Current provider references: [AssemblyAI API guidance](https://github.com/AssemblyAI/assemblyai-skill/blob/main/skills/assemblyai/SKILL.md), [AssemblyAI pricing explanation](https://www.assemblyai.com/blog/speech-recognition-cost), [xAI model metadata](https://docs.x.ai/developers/rest-api-reference/inference/models), [Stripe dispute events](https://docs.stripe.com/api/events/types).
