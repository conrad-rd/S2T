# Billing reliability work

Acceptance: ordinary upstream failures do not pause unrelated users; valid provider receipts settle before output validation; streaming is not permanently disabled by a cumulative $1 trial counter; existing private allowlist and account/provider/global spending controls remain; direct audio flow and durable recovery remain; a live synthetic speech session produces the expected transcript and exactly one charge.

- [x] Read workflow principles and current provider token/webhook contracts.
- [x] Reproduce and fix provider text/ordinary failure isolation.
- [x] Replace the special one-time issuance cap with existing spending controls, preserving conservative exposure.
- [x] Verify live synthetic streaming and exact charging without microphone capture or private recording content.
- [x] Review and deploy only scoped code, preserve live settings, verify canonical app.

Independent per-session billing proof is not available in the documented direct-client token API. The webhook contains transcript turns, not session duration, and its credentials come through the client. Charging a fixed purchased time allowance would change customer pricing; proxying the audio would violate the requested architecture. This remains a provider limitation, not a solved verification claim.

Additional provider limitation: the documented streaming `llm_gateway` option can invoke paid models. Temporary tokens document no model/feature restriction, so authorization seconds times an STT rate cannot be advertised as a guaranteed total dollar cap. Existing private allowlist and funding configuration remain unchanged.

90 backend tests pass. Exact staged Worker SQL/runtime checks pass for streaming durability, metadata-only completion, duplicate settlement and unrelated-account continuity after an unknown provider result. Definitive token rejection releases the customer hold; uncertain issuance retains it. No ordinary failure is silently charged to a customer.

Canonical S2T 1.0.1 Build 625 passed packaged credit/recovery, nonblocking streaming latency and build identity checks. Service-wide pause text now identifies a billing issue instead of implying the customer key or credit settings caused it.

Deployed Worker `02597ae0-6eb5-400d-9435-3d56c8b55115`, source SHA256 `2f74aaa37d92e3034d030264443128ea2536335c1c59254da815ac84fe118094`. Exact source readback and unchanged bindings verified. Live operator health reports no pause, open incidents or pending requests. GPT-5.6-Sol reviewed the scoped backend update before deployment.

The live synthetic check failed at customer authentication because the old saved test key is invalid. It did not mint a token or incur a provider charge. An explicit exception was requested to the AGENTS.md prohibition on using real credentials/Keychain in verification. No exception has yet been received. A native check is packaged as `--verify-live-streaming-billing --allow-live-billing-check`; do not run it until that approval arrives. It reads only the saved S2T connection with interaction disabled, uses the locally generated 2.4365-second phrase, and compares account balance before/after a receipt and a duplicate receipt.

The gated native check was reviewed again after moving its balance baseline before authorization and persisting each receipt atomically under a unique authorization-bound filename. Final canonical S2T 1.0.1 Build 628 passed the no-authorization rejection check before Keychain access and the packaged build-identity check. Running without the authorization flag refused before credential access, and packaged build identity passed. The live check remains NOT VERIFIED. The broader independent per-session accounting issue remains unsupported by the provider contract and must not be described as solved.

## Approved live check

The user explicitly approved the exception for one synthetic-speech test using the app's saved S2T key. The packaged native probe passed: the expected phrase matched, AssemblyAI reported 3.000 session seconds, and the account was charged 0.041667 credits, corresponding to USD 0.000375. Sending the same completion twice caused no further debit. No microphone capture, screen capture, clipboard use or credential output occurred. The key was not printed or exported. Evidence: `/tmp/s2t-live-billing-approved.log`.

This completes verification of the normal live native streaming and billing flow. It does not change the independently verified duration limitation for an untrusted client. Earlier pending-approval and NOT VERIFIED notes above describe the state before this explicit approval and successful run.

## Fresh approved billing check, September 19

The user explicitly approved one fresh 2.4365-second synthetic recording. Only one new AssemblyAI session was created. AssemblyAI returned a transcript and reported 3 session seconds and 2 audio seconds. The original test failed its balance assertion before checking the exact transcript wording. That text was not persisted, so exact-word agreement is not claimed for this run.

A concurrent authorized margin deployment at 13:22:28 UTC changed the live conversion from 9,000 to 8,000 provider-cost microdollars per credit. The old native live check and localhost lifecycle fixture still assumed 9,000. Both expectations now use the deployed 8,000 conversion. The live probe saves numeric debit evidence and a transcript-match boolean before assertions, without saving keys, tokens or transcript text. The conversion remains an explicit test assumption that must track future pricing changes.

A separate branch of the same gated probe checks an existing synthetic receipt without requesting a token or sending audio. Its runner holds the package lock and refuses binaries that lack the receipt-only branch, preventing an older app from ignoring the flag and starting another recording. Using the already approved session, this branch confirmed state=settled, cost=charged=375 microUSD, equivalent to 0.046875 current credits. Repeating the same completion changed neither the request row nor total account balance. Zero credits remained reserved. Evidence: build/billing-reliability/native-existing-check-576c30af-3423-4d8e-9fe7-272b6edde7dd.json and /tmp/s2t-live-existing-receipt.log.

Canonical S2T 1.0.1 Build 643 passed build identity, authorization-gate rejection, credits/recovery, synthetic streaming and latency checks. All 370 Swift tests passed. The exact current Worker passed the full packaged AppState/HTTP test with three dictation-plus-cleanup cycles, three cancellations, deliberate lost authorization/cancellation/completion responses, exact charges and no stranded holds. Provider inference was mocked for these additional checks. Live health afterward showed no pause, incidents or pending requests.

Concurrent source edits repeatedly interrupted ordinary builds. The successful package used a stable copy of the latest source under the canonical package lock and wrote to build/S2T.app. An initially missing authored Chroma JSON fixture caused one isolated-source test failure; supplying that existing fixture made all 370 tests pass. Newer packaged work was preserved. Logs: /tmp/s2t-live-followup-build-snapshot.log, /tmp/s2t-live-followup-swift-snapshot-final.log, /tmp/s2t-live-followup-packaged.log and /tmp/s2t-live-followup-lifecycle.log.

Current Worker version 096a9868-d3fa-4593-b2ae-436502f99af3, SHA256 44c483c2f9b2d768bfbd42008464aad8ad4ab2a7aedef6b8c5bd61caeb00d036, retains the streaming expiry/slot fixes, no default monetary caps and the prior approved OpenRouter cap removal. This follow-up changed verification code only and made no Worker deployment. GPT-5.6-Sol reviewed the probe and its fail-closed runner.
