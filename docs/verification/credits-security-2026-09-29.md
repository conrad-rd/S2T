# S2T credits security and performance audit — September 29, 2026

The reviewed release closes ten demonstrated security, availability, and retry-efficiency gaps in the previously deployed Worker. It preserves the current wallet, credentials, account access rules, and payment conversion. No real payment or billable provider inference was used for this audit.

Deployed at **2026-09-28 23:22:39 UTC** (September 29 in Berlin). Worker version `6e3f3992-384d-4aa0-bd10-9203a2b3788e` serves **100% of traffic**. Source readback matched the reviewed bundle exactly. Bindings and runtime compatibility settings matched; health/config and both public wallet pages returned HTTP 200, invalid app-key access returned 401, and wallet page hashes were unchanged. Evidence: `.audit/credits-security-2026-09-29/deployment-readback.json` and `deployed-settings.json`.

## Findings and changes

| Finding | Result |
| --- | --- |
| Historical direct-streaming tokens could lose their credit hold through client-reported zero duration, cancellation, or expiry. New issuance was already disabled in production. | Removed direct-streaming routes. Issued historical tokens retain an uncertain hold until independent reconciliation or an audited writeoff. Never trust a client to report its billable usage. |
| Public OpenRouter catalog entries could create new speech routes without reviewed duration pricing. | Paid speech is restricted to explicit pricing policy. Catalog appearance alone no longer authorizes spending. |
| Two GPT-4o transcription choices reserved $0.02 despite token billing without an enforceable output limit. | Withheld `openai/gpt-4o-transcribe` and `openai/gpt-4o-mini-transcribe` from S2T credits. Nineteen duration-priced speech choices remain. Personal OpenRouter keys are unaffected. Exact retries of already-paid results remain available. |
| A one-second Whisper V3 clip reserved 125 microdollars, below the documented ten-second minimum of about 309 microdollars. | Reserve at least ten seconds for Whisper V3 and V3 Turbo. Settlement still charges actual reported usage, never the full hold merely because it was reserved. |
| The old vision billing path remained live after its removal from current app source. Its image cost was not safely bounded by the text-based reservation. | Removed the paid vision route, catalog advertisement, and provider dispatch branch. Stale clients fail before dispatch. |
| Every denied rate-limit attempt still wrote to durable SQLite. | Atomic rate counters stop writing once exhausted. The exact runtime fixture falls from 1,000 writes per 1,000 rejected attempts to zero. |
| Invalid app credentials consumed rate-counter writes before authentication. | Authenticate app keys before durable rate accounting. Ten invalid-key requests now produce ten 401 responses with zero database writes. |
| Concurrent readiness calls duplicated provider-key lookups. | Share the in-flight check, then cache success. Sixteen simultaneous callers issue one lookup; a failed check can be retried. |
| A stalled request body could occupy one of four shared upload slots indefinitely. | A 45-second deadline cancels the reader and releases the slot. Size limits still apply. |
| Retrying paid work unnecessarily consulted the model catalog and current pricing. | Retrieve matching paid results before policy resolution; the replay fixture performs one provider call and one policy resolution across two identical requests. |

The alternative Node HTTP server also rejected every real-provider request because it referenced a removed configuration field. That gate is repaired locally; the ledger remains responsible for funding and reconciliation checks. This defect did not affect the deployed Cloudflare server.

The audit also reviewed credit reservation/settlement, idempotency, ambiguous provider failures, account isolation, key limits, guest access, signed Stripe events, duplicate payments, refunds, and dispute handling. Existing safety checks in those paths passed the relevant suites. This is evidence for the tested cases, not a guarantee that no future abuse is possible.

## Verification

- Initial source baseline: 177 tests passed. Final source: **180 passed, zero failures or skips**.
- Eight scripts passed against the exact release bundle: Cloudflare integration, billing audit, OpenRouter catalog, profitable pricing, volume pricing, streaming retirement, storage maintenance, and the new security deployment check.
- The security script runs ten adversarial cases with mocked external services. All ten fail against the saved original live code/settings and pass against the release code/settings.
- Short-clip reproduction: the original becomes `uncertain` and pauses spending on a 309-microdollar receipt. The release settles that same receipt for 0.0618 credits, leaves no hold, and remains unpaused.
- Token-priced speech reproduction uses a synthetic 21,000-microdollar receipt to demonstrate the old hold's exposure. That is an injected cost, not a claim about a measured production request. The release rejects the model before any provider call.
- Payment-flow fixtures exercise signed webhooks, authoritative Stripe retrieval, replay and deduplication, concurrent reservations, persistent storage, key revocation, and cross-account controls. All data and external service responses are synthetic.
- An older September 19 speech harness was tried but excluded: it assumes the historical 20% margin and does not represent current billing. It was left unchanged. Current pricing and speech-contract suites cover those paths.

The faster path is supported by counts of avoided writes and network requests. No production latency percentage or speedup is claimed.

Independent pre-deployment review by **gpt-5.6-sol, high reasoning** returned a ship verdict with no blocking finding. The reviewer called out the intentionally deferred funding/reconciliation gates and historical issued-token holds; both are covered under remaining operational work. The canonical ten-case result is `release-security-deployment-check.log`. The workspace does not expose an `agent-transcripts/` directory; the trail was checked against the active conversation and saved evidence instead.

## Release provenance

Original Worker version: `dfdd56ca-f58d-414f-88e0-d77c7fb39986`.

Original bundle SHA-256: `f5e717e9e0214a56fbd7ccf0810970e6256fc2f4815ed07608dfbcf05c2c0466`.

Release bundle SHA-256: `3fa10fc3dc7083bde2b1fae63b3212235d97b80a78ec9c9ee61927677c5ec87c`.

Reviewed settings SHA-256: `34f46eebd97a2197cfdbc10fabe99efc2ff5ac8c02bcb3350209a6807e65808f`.

The release is assembled from the downloaded production bundle and reviewed module replacements, using `.audit/credits-security-2026-09-29/build-live-patch.py`. This avoids publishing unrelated uncommitted application and website changes. `release-worker.diff`, `release-checks.json`, test logs, public provider pricing snapshots, and `decisions.tsv` are in the same directory. The full local source is a separate, broader candidate.

`deploy-release.mjs` verifies the exact checked artifact and settings, compares current production against the audited version, and preserves secret, asset, and Durable Object bindings. It publishes code plus reviewed pricing changes together, then reads back the source and settings and checks the public service and unchanged wallet assets. It never retrieves secret values or rotates credentials.

## Remaining operational work

1. **Independent provider reconciliation and funding review:** the broader local candidate introduces 24-hour review gates, but the recorded September 19 evidence is stale. Turning those gates on now would stop paid requests. This scoped release preserves the existing live gating behavior; `enforceReconciliation: false` is explicit in the release constructor. It does not invent a fresh review date. Historical provider expenses and issued streaming tokens still need actual external records before their audit can be closed.
2. **Stripe event subscriptions:** local code and mocked signed-event tests cover all dispute transitions. The Stripe connector required authentication and the available browser reached Stripe's login page, so current live subscriptions could not be independently verified or repaired. Prior records say updated, closed, and funds-reinstated dispute events were missing. That historical observation must not be mistaken for a fresh check.
3. **Guest credential migration:** current production uses its existing credential encryption setup. The separate credential-key migration in the broader local candidate is not included; rotating its result key before migrating old guest credentials would be unsafe.
4. **Upstream operations and price changes:** provider balance/refill automation and continuous external alerts remain separate work. Duration-priced speech rates were checked against public endpoints during this audit, but those APIs offer no per-request monetary cap. Future price changes require review. An unexpected overrun still pauses spending and withholds an unaccounted result; in-flight provider expense can still exceed its reserved estimate.

Do not deploy the entire current working tree as a follow-up without handling those prerequisites. Do not roll back to the old vulnerable Worker merely to restore a removed model.

## Primary pricing and deployment references

- [Groq speech-to-text billing and minimum duration](https://console.groq.com/docs/speech-to-text).
- [OpenRouter transcription contract and billing](https://openrouter.ai/blog/tutorials/transcription-on-openrouter/).
- [OpenRouter provider price controls](https://openrouter.ai/docs/guides/routing/provider-selection).
- [Cloudflare multipart metadata and asset preservation](https://developers.cloudflare.com/workers/configuration/multipart-upload-metadata/).
- [Cloudflare upload API and preserved binding types](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/).
