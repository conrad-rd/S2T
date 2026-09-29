# Billing release assurance, September 19

## Current status

The request-rate repair is deployed to 100 percent of traffic as Worker version `be321e8a-45e5-42e8-b778-01d92c3e87ce`, preserving the earlier pending-stream repair. Exact published source readback matches the tested SHA-256 `f7bf665cfdc3d06d88c44f354c34a147c6f656669fab1becee9ef3222ec9d489`. Production health at `2026-09-19T19:10:08.184Z` returned HTTP 200, `paused:false`, no incidents and no pending requests. This is a point-in-time check, not an uptime measurement.

The user explicitly approved both tested rate increases after automatic approval review required that confirmation. Deployment proceeded after refreshing the saved Cloudflare session. The upload checked that the live deployment and settings still matched the prepared base, required the exact successful verification record, and verified published source byte for byte. No provider inference or payment was sent during deployment verification.

## Additional failure reproduced

A fixed-clock ledger test performs twelve completed streaming dictations, twelve cleanup operations and three cancelled starts within one minute. The original per-account limit of twenty new provider operations rejects the ninth cleanup, even though prior operations have completed and the account has sufficient credit. Separately, an extended packaged-client recovery test against the exact live Worker failed with HTTP request throttling. The old sixty-call key limit counts balance checks, cancellation and completion reports as well as new work.

The deployed changes are sixty new provider operations per account per rolling minute and three hundred authenticated API calls per key per minute. Local and Cloudflare routes agree. The three-hundred-call IP limit, two concurrent HTTP operations, eight unconfirmed streaming authorizations, prepaid wallet checks, user-selected key budgets, authentication and private-beta restrictions are unchanged. A compromised authorized key can submit operations faster under these settings; this is not an unlimited-rate change. The live configuration still restricts sign-in to the owner's verified email.

The scoped Worker patch changes only those two constants. Its SHA-256 is `f7bf665cfdc3d06d88c44f354c34a147c6f656669fab1becee9ef3222ec9d489`. It preserves deployed code, assets, bindings and secrets, including the previous streaming-expiry alarm. Unpublished direct-ledger and privacy work is excluded.

## Verification

Run the repeatable check against the actual proposed or deployed artifact:

```sh
cd billing-local
npm run test:release -- ../build/reliability-assurance/worker.js
```

The command passed with 148 billing tests, packaged build and credit checks, 34 exact-Worker regression cases, isolated checkout/refund/usage/restart checks, scheduled streaming expiry, failure isolation and native HTTP recovery. The native client completed twelve streaming-plus-cleanup cycles, three cancellations after authorization and one cancellation before a delayed authorization response arrived. The fixture deliberately discarded successful authorization, cancellation and completion responses. Final text remained correct, every completed operation charged once and no credit holds remained.

This check writes a timestamped `.verified.json` record beside the Worker artifact, with both executable and Worker hashes. It fails if either changes while checks run. The scoped deployment script requires a matching successful Worker record and checks that live source/settings have not changed since preparation. Future billing releases must repeat this check against the exact artifact they intend to upload. The standalone check does not automatically intercept every possible manual deployment command.

The canonical app verified here is S2T 1.0.1 Build 668, compiled `2026-09-19T18:20:18Z`, at `build/S2T.app`. Executable SHA-256 is `b27eea5f69b3d4c378a1633cb002782f8210cfaec80ea6a367e84dfaa35029e8`. This work only extended its isolated lifecycle probe. Existing runtime cancellation recovery was already present in Build 664. No new restart is needed for the deployed server rate change.

Providers, payments, audio, sockets, storage and text insertion were simulated or isolated. No real inference, purchase, microphone, user clipboard, Keychain or screen capture was used. The previously completed 391 Swift tests are supporting evidence from the preceding repair, not a fresh run for this record.

## Confidence and remaining risk

There is no defensible numeric probability of recurrence without a defined usage period and production request/failure counts. An engineering assessment is moderate risk, 3 out of 5, of some service interruption during the next week of normal use. This is a subjective risk category, not a 60-percent probability or an availability guarantee. The reproduced rapid-use workload passes against the exact code now deployed; exceeding the new finite limits can still produce throttling.

The tests give specific evidence for the covered billing and recovery behavior. They do not establish long-run availability or validate current live provider responses. OpenRouter and AssemblyAI outages, network interruption and exhausted prepaid provider funds remain possible. Automatic refills have not been verified as enabled. Streaming still uses client-reported private-beta usage, and repeated unknown or abandoned authorizations can intentionally reach the eight-token guard until their possible lifetime expires. Real ledger-integrity failures can still pause spending. Missing Stripe dispute-resolution webhook subscriptions remain a separate unresolved operational dependency.

Evidence is in `build/reliability-assurance`: before-fix failures, successful release log, artifact diff, artifact hashes and live health. Earlier broad assurances should not be read as proof of zero defects.
