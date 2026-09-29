> Historical direct-streaming notes. Direct credit token issuance and its native recording path are retired. Normal dictation uses early batch transcription, verified by `--verify-early-transcription`. Existing saved audio remains recoverable. Legacy receipt metadata is preserved for service confirmation; retired completion endpoints are never retried automatically.

# Streaming pending-request repair, September 19

The user's error was real after the previous audit. Two submitted AssemblyAI streaming authorizations occupied both slots in the generic HTTP request limit. A cancelled authorization could lose its HTTP response before the native client learned the server request ID, so the existing ID-based cancellation could not release it. Completed streaming sessions also remained counted against the separate eight-token guard until their maximum window ended. Production had no scheduled streaming-expiry alarm; the local source's privacy cleanup had not been part of its scoped deployments.

## Repair

- Streaming authorizations use their own capacity check and do not consume either of the two normal HTTP processing slots. Both paths retain balance, key limits, rate and expense checks.
- Completed streaming reports close their capacity slot immediately. Unknown and abandoned tokens still count while they might remain usable. This preserves the existing private-beta trust model for client-reported session termination and duration; it does not establish provider-verified public billing.
- Authenticated `/api/v1/streaming/cancel` uses the original idempotency key, scoped to account and app key. A durable cancellation record handles cancellation arriving before authorization, while token issuance is in flight, or after a lost response. It never cancels another account or key's request and never issues a replacement token.
- If authorization fails or the task is cancelled, CreditsAPI sends cancellation in an independent bounded task, even when the response ID never arrived. Completed or cancelled requests remain idempotent. If the app or network disappears before cancellation can arrive, expiry remains the fallback.
- The deployed Durable Object now expires streaming authorizations on startup and every minute. Local source already invokes streaming expiry through its existing alarm. No unrelated privacy purge was deployed.

## Verification and release

Five failing server regression cases reproduced the capacity and cancellation failures before the fix. All 147 billing tests then passed, plus 391 Swift tests. The exact Worker passed 33 regression cases and the isolated checkout, refund, usage and restart checks. Its HTTP fixture verified alarm expiry and 12 completed recordings in one minute without advancing the clock.

The packaged app completed three streaming-plus-cleanup cycles against the exact isolated Worker over localhost. The fixture cancelled an authorization before its delayed response arrived, then dropped successful authorization, cancellation and completion responses. All holds cleared, original request identities prevented duplicate submissions, each completed operation charged once, and recovered text was delivered to an injected test receiver. Audio, provider sockets, credentials, storage and insertion were synthetic. No real inference, microphone, user clipboard or screen capture was used.

Worker version `933e55b4-b2cc-4acc-8f5e-bb9f426ddd1d` is deployed. Exact source readback SHA-256 is `09b9d6890f73dc6113f1e2f0afb1c7cece0cb2b88cdd45d1654b519f4a176a3d`. Production health at 2026-09-19T17:54:54Z returned `paused:false`, no incidents and no pending requests. Expired holds cleared through the new recovery path, without a manual balance adjustment or fabricated provider receipt.

Canonical `build/S2T.app` is S2T 1.0.1 Build 664, compiled 2026-09-19T17:53:49Z. Packaged build identity and credit/recovery probes passed. Evidence is in `build/streaming-pending-repair`.

Commands:

```sh
cd billing-local
npm test
S2T_STREAMING_AUDIT=1 S2T_DEPLOYMENT_ARTIFACT=../build/streaming-pending-repair/worker.js node billing-audit-deployment-check.mjs
S2T_STREAMING_BUNDLE=../build/streaming-pending-repair/worker.js S2T_NATIVE_LIFECYCLE=1 node assembly-streaming-cloudflare-check.mjs
S2T_STREAMING_BUNDLE=../build/streaming-pending-repair/worker.js S2T_NO_CAPS_CHECK=1 S2T_PENDING_CHECK=1 S2T_RELIABILITY_CHECK=1 node assembly-streaming-cloudflare-check.mjs
```
