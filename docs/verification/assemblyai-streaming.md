> Historical direct-streaming notes. Direct credit token issuance and its native recording path are retired. Normal dictation uses early batch transcription, verified by `--verify-early-transcription`. Existing saved audio remains recoverable. Legacy receipt metadata is preserved for service confirmation; retired completion endpoints are never retried automatically.

# Direct AssemblyAI streaming trial

## Acceptance criteria

For a new dictation with S2T credits and AssemblyAI selected, the app receives a one-use token from the existing credits Worker, sends PCM directly to AssemblyAI, and receives the transcript directly. The credits endpoints accept only bounded metadata. The app never receives the shared AssemblyAI key. Recording recovery remains local and encrypted. Stream failure must never trigger an audio upload to S2T.

This change concerns speech transcription. Paid text cleanup still uses the existing S2T cleanup route and therefore sends transcript text to that service. Verbatim mode skips cleanup. Do not describe this change as removing all customer content from S2T servers.

## Work sequence

- [x] Read operating principles and verify the temporary-token contract and current streaming pricing.
- [x] Choose a private-beta accounting policy without changing the customer purchase model.
- [x] Implement and test token issuance, durable authorization, account isolation, idempotency and metadata-only completion.
- [x] Implement and test the native WebSocket state machine with fake transport.
- [x] Integrate microphone streaming, saved-audio replay and durable completion retries.
- [x] Run isolated service and Cloudflare checks, Swift tests and packaged capture-free probes.
- [x] Review the implementation and publish only the scoped Worker changes, then update and verify build/S2T.app.

## Trial accounting

The private beta uses the app's reported AssemblyAI session duration to calculate customer charges at 125 microUSD per second, the published $0.45/hour rate for Universal-3.5 Pro Realtime as checked September 18, 2026. Reports are explicitly client-reported, not independent provider receipts. Missing reports remain unresolved; do not invent customer charges.

Token issuance reserves a conservative full-session allowance before calling AssemblyAI. Provider exposure is retained even after a short reported session. The original cumulative $1 trial counter was removed in the September 19 reliability update. Existing account, provider and global budgets still count conservative authorization exposure, regardless of the reported duration. Daily limits renew at UTC boundaries; the existing global lifetime limit remains. Existing account/key limits and the existing live email allowlist remain active. These are private-beta controls, not a claim of fraud-proof public customer billing.

The provisional exposure estimate is 300 microUSD per second, $1.08/hour. This exceeds the documented combined $0.99/hour for the streaming base model plus listed STT add-ons. It is not a proven total spending bound: streaming also documents client-selected LLM Gateway options, and temporary-token restrictions on those options are undocumented. Temporary tokens do not document a model/add-on allowlist. Recheck pricing and token scope before broader access. Provider funding remains prepaid with auto-recharge disabled.

## Provider references

- https://www.assemblyai.com/docs/streaming/authenticate-with-a-temporary-token
- https://www.assemblyai.com/docs/streaming/api-spec/generate-streaming-token
- https://www.assemblyai.com/docs/streaming/api-spec
- https://www.assemblyai.com/pricing/

Tokens are single-use. The 60-second redemption window is separate from the bounded session duration. Streaming billing measures connection duration, including silence. Keep the local recording when a connection fails; replay must use a fresh authorization and paced direct streaming rather than the S2T audio endpoint.

## Verification evidence

345 Swift tests and 87 backend tests passed. The isolated Cloudflare integration passed against the exact staged Worker bundle, using fake token issuance and Durable Object SQL storage. It covers restart durability, encrypted single issuance, account isolation, metadata-only payloads and idempotent accounting. Review caught and removed the legacy AssemblyAI audio-proxy fallback when the streaming capability is missing.

Deployed Worker version `fd52d15a-9b98-4399-92ba-309cfd0f57ee` at 100%. Readback matches SHA256 `d335de268f0a202463969d4163aa2d02d9153a841862abfcee35d3a37be49541`. Existing bindings and secrets were preserved; only the private streaming flag was added. The live health endpoint reports healthy durable SQLite storage. GPT-5.6-Sol reviewed the final changes and found no remaining runtime blocker. Canonical `build/S2T.app` is version 1.0.1, Build 623, built 2026-09-18T22:04:38Z. Packaged `--verify-assembly-streaming`, `--verify-credits` and `--verify-build` passed. The credits probe explicitly rejects the missing-capability AssemblyAI path without posting audio, and checks encrypted recording recovery with fake credentials. The build log is `/tmp/s2t-streaming-package.log`. No live microphone or real customer recording is permitted in automated verification. Synthetic PCM and mocked provider transports cover protocol behavior; they do not establish real transcription quality.

## Latency and duration correction, September 19

The two-minute AssemblyAI credit label was stale. The direct streaming implementation already caps microphone capture at 600 seconds and requests a 630-second token window for finalization. The settings label now says ten minutes. AssemblyAI documents a maximum token session duration of 10,800 seconds, but S2T still has a ten-minute local recording bound. No provider limits or financial exposure limits were raised.

The last available real app timing sample was 1.133 seconds for transcription finalization and 0.504 seconds for cleanup. This is one observation, not a controlled personal-key comparison. Personal-key Fast transcription uses Sync; the credits implementation uses streaming. Cleanup through credits still uses the Worker. Those differences prevent a claim of exact latency parity.

Removed the separate balance request before token issuance. The token endpoint already checks feature availability, account status, balance and limits atomically before issuing access. A rejected authorization still stops before microphone capture and never enables audio proxy fallback.

Removed the awaited billing completion request from the delivery path. The receipt and transcript are saved first. The existing post-pipeline credit refresh reports durable receipts and clears them only on success. Failed reports remain available after restart. This can briefly leave the credit hold visible after text arrives.

`--verify-streaming-latency` runs the production streaming finish, persistence and delivery path with a fake WebSocket and a one-second billing response. Before: 1.025 seconds until delivery, billing already completed. After: 0.014 seconds until delivery, billing not yet completed. The exact transcript arrived, and the persisted receipt settled and cleared afterward. This demonstrates removal of the billing wait, not real-world provider speed. Logs: `/tmp/s2t-stream-latency-before.log` and `/tmp/s2t-stream-latency-after.log`. `--require-nonblocking` enforces delivery before the delayed billing response.

331 S2TCore tests passed. The full test command stalled in the unrelated S2TBench TransportTests suite; only that isolated test process was stopped. No real inference, customer recording, microphone, screen capture or real credentials were used in the synthetic checks. Canonical S2T 1.0.1 Build 624 passed packaged `--verify-streaming-latency --require-nonblocking`, `--verify-assembly-streaming`, `--verify-credits` and `--verify-build`. Packaged synthetic finish-to-delivery was 0.013 seconds with the same one-second billing delay. The debug-only credits UI probe lacked bundled typography; the packaged credits probe passed with its actual resources. The user app was not interrupted or restarted.


## User-controlled spending, September 19

The user requested removal of all automatic spending caps. Default per-request, account-daily, provider-daily, global-daily and lifetime amounts are now null. Available balance and explicit key budgets remain enforced. Completed streaming sessions no longer consume the recent-session concurrency count.

Streaming reserves 125 micro-USD per authorized second, up to 78,750 micro-USD or 8.75 credits for 630 seconds, instead of the previous 21-credit hold. The authorization shrinks to the available balance and remaining user key budget. The Mac honors the returned recordingMaxSeconds. AssemblyAI requires at least 60 authorized seconds, so very small balances receive a shorter app recording window; customer charges never exceed their hold. S2T absorbs any reported duration cost above that hold. This remains private client-reported billing, not an independently verified provider receipt.

If a recording hold prevents cleanup, the app submits its durable streaming receipt and retries cleanup once using the same request ID. Normal delivery still does not wait for the receipt. Tests use fake credentials and synthetic audio only. No additional live provider test was run under the earlier single-test approval.

Verification: 95 backend tests and 345 Swift tests passed. The exact staged Worker passed isolated Cloudflare SQL tests, including 12 completed authorizations in one minute with all five monetary defaults null, restart durability and account isolation.

At the Build 632 checkpoint, automatic approval review had blocked removing the external OpenRouter $5 cap without separate approval. The user subsequently granted approval during the failure-path assurance work below, and the cap was removed.

Final app is S2T 1.0.1 Build 632. Packaged credits, build identity, synthetic streaming and low-balance cleanup retry checks passed. The no-hold-block latency remained 0.015 seconds with a simulated one-second receipt call; the low-balance path took 1.028 seconds and retried cleanup exactly once after settlement. Final backend count is 96 passing tests. Deployed version is 69ca8ba6-b289-4528-a493-d5a4c0325e59 at 100 percent. Readback SHA256 is 80ea343aa06f513315981229f74d42fd3c128a41a7b25abab806e601658c52db. All existing bindings are unchanged.

## Interrupted-session lockout repair, September 19

The live error was `Too many pending requests`. Operator health showed two AssemblyAI rows still submitted, each holding 8.75 credits, with no service pause or monetary cap. Cancellation and failed websocket paths discarded the Mac session without closing its billing authorization. The server only purged encrypted tokens and never expired submitted rows.

The failing-before test retained 17.5 credits after both session windows expired. Expired authorizations now release their holds and request slots automatically, preserving the conservative provider expense as a writeoff without fabricating a receipt. A customer-key-authenticated abandonment endpoint handles cancellation immediately. A delayed receipt remains idempotent and records usage metadata without charging after the hold was released. New authorization expires old rows before reservation, so cleanup does not depend solely on the scheduled alarm. Normal active authorizations and balance checks remain enforced.

The Mac abandons authorizations after cancellation, short recordings, microphone/start failure, websocket failure and failed saved-recording replay. Cancellation callback runs once. Unknown mint responses or failed abandonment delivery still expire after the bounded authorization window.

Verification: both new regression cases failed before the implementation. All 98 backend tests, 345 Swift tests, and the exact Worker Cloudflare SQL checks passed. Packaged build, credits, synthetic streaming latency, cancellation and audio checks passed. No live provider inference, microphone, screen capture or real customer key was used for verification. Worker version 866077b1-6f6a-4ab0-bd01-b93ff92e1d0f has source SHA256 af3075608c96ed76324bb1daf531fb04c283036f32673699974ab7660e1f7721. All bindings remained unchanged. Live health confirmed zero pending requests, no incidents and spending active. Canonical S2T 1.0.1 Build 633 was restarted normally in the background after confirming no pending live recording.

## Failure-path assurance, September 19

A further audit reproduced three gaps with failing-before tests. A lost token response did not retry its existing authorization. Non-streaming provider calls whose receipt was unknown still occupied active execution slots after the calls had ended. Slow durability confirmation could also make token expiry occur too early relative to actual issuance.

Streaming authorization, cancellation and receipt submission now retry one transient transport failure with identical metadata and request identity. The server retains uncertain billing holds but counts only executing requests toward concurrency. Streaming expiry extends from the token issuance request after durability confirmation, with buffer for the bounded provider call. This does not change balances, explicit key limits, external provider caps, or the private access policy.

The new `--verify-streaming-lifecycle-http` fixture runs the packaged AppState pipeline against the exact staged Worker in Miniflare over real localhost HTTP. Provider sockets and inference are synthetic. It checks three complete dictation and paid-cleanup cycles, exact delivered words, three immediate cancellations, durable receipt clearing, final zero holds and exact once-only charges. Its HTTP bridge deliberately destroys the first successful authorization, cancellation and completion responses. The cancellation-response case failed against the prior packaged app before retry support was added.

Tests use a newly generated test-mode ledger key supplied only to the isolated fixture process, never a real account or Keychain credential. These checks establish app-to-server behavior for the exercised cases, not a promise that third-party services or every possible failure will work forever. The user subsequently approved removing the shared OpenRouter $5 cap. The mutation ran with credentials kept inside the Worker, and current-key readback confirmed limit=null. The temporary administrative action is removed after verification.

Streaming metadata attempts now use a 25-second timeout and one same-identity retry, keeping the normal response-recovery budget below the 60-second temporary-token redemption window.

Run native preview fixtures sequentially. Both the existing credits probe and lifecycle probe isolate themselves from user preferences through the same preview suite. Parallel runs can overwrite that shared test suite. Final verification takes build/.package.lock and runs Swift tests, packaged probes and the HTTP lifecycle in sequence so another package cannot replace BuildIdentity or the executable during the checks.

Final assurance outcome: 100 backend tests and 348 Swift tests passed. Canonical Build 638 passed the build, credits, streaming latency, cancellation and synthetic audio probes, followed sequentially by the full app-to-Worker HTTP fault test. The fixture deliberately lost successful authorization, cancellation and completion responses, recovered all three, and checked exact once-only charges and zero holds. GPT-5.6-Sol independently reviewed the billing changes and reported no remaining billing blocker. Newer concurrent Writing/Appearance work was preserved. Build 638 was restarted normally in the background after live health showed zero pending requests, no incidents and spending active.

The approved OpenRouter key change was confirmed by current-key readback reporting limit=null. The temporary administrative route was then removed. Final Worker version 7f2e4910-f1a3-4e5d-b46a-769a0aab5774 matches SHA256 1b0cf3b5e03d25e34758fc9ebf9a1694a5baacc4beeb96487bd76738fec8b1f5. Its provider funding metadata records prepaid OpenRouter without a hard key cap; every other binding is unchanged. Evidence is under build/credits-assurance/provider-cap-removal. No provider inference was run for this assurance work; the separate key-limit administration was explicitly approved by the user.

Saved legacy receipt metadata remains encrypted for service confirmation; the native app does not call the retired completion endpoint or clear a financial obligation after a 404. A local receipt does not prove that its hold remains unreconciled. Recording settings and the Last dictation menu show a support confirmation notice.
