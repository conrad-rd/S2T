# S2T route latency investigation

The public `/health` connection benchmark in routing-recovery.md does not measure transcription or cleanup performance. It cannot establish parity with personal provider keys.

## Confirmed differences

- S2T uploads base64 WAV inside JSON to one central Durable Object. That object reserves credits and then submits the provider request. Personal AssemblyAI sends multipart WAV directly to the global Sync endpoint.
- The personal AssemblyAI client calls the provider's `/warm` endpoint during recording. S2T warms only its own public health endpoint. That does not warm the billing object or its connection to AssemblyAI.
- Saved cleanup options currently differ even for the same GPT-OSS 120B model and Cerebras host. Personal OpenRouter uses minimal reasoning; the S2T setting uses low reasoning. Preserve explicit preferences. This difference must be controlled during comparison and does not explain speech latency.
- The S2T cleanup adapter imposes a priced output limit and requires supported parameters. The personal request currently has no output limit. Compare identical capped requests when measuring routing, and identify this controlled difference in the report.

No end-to-end speed improvement or direct routing has been demonstrated.

## Duration instrumentation deployed

`gateway.mjs` measures reservation, durable confirmation, provider execution and settlement per request. The Worker adds upload and total ledger durations, and the front Worker adds its round-trip duration. These are `Server-Timing` headers only, with no audio, text, credentials, account identifiers or durable diagnostic storage. Replayed requests have no provider duration because they do not execute again. Provider rejection and uncertain outcomes retain their existing billing behavior.

The scoped artifact in `build/routing-latency/worker.js` is based on the current deployed source, with no pricing, credential, routing, allowlist or asset changes. SHA-256: `dcbfc2ef05e1031048ae58a0ab7b9dcc6f6300a3bb6d0a133d059e2e6a8bf7bc`.

Twelve focused gateway and recovery tests passed. The exact artifact passed the isolated Cloudflare runtime check with fake external services, including concurrent replay, one provider execution, timing headers, account isolation, durable storage, key expiry and credit limits.

The user explicitly approved the duration-only deployment after automatic review requested separate approval. Worker version `fbfd5406-8630-482e-b347-65f00ad8da0e` is active, and source readback matches the artifact hash above. All 63 billing unit tests passed. Final production health has `paused: false`, no pending holds and no open incidents.

## Authorized live measurements

The user authorized at most USD 0.20 total, superseding the proposed USD 0.25 limit. The standalone comparison uses the compiled production Swift request builders, synthesized 4.677-second mono WAV and a fixed authored cleanup prompt. Saved credentials were read noninteractively into memory only. No microphone, screen, clipboard, user transcript or user system-prompt file was read. Reports omit input/output text and credentials.

The direct baseline failed. AssemblyAI returned HTTP 404, and the saved personal OpenRouter key returned HTTP 401. Unauthenticated checks of AssemblyAI's old and versioned warm/transcribe paths also returned 404 from this machine. This is not proof those endpoints are universally unavailable: the hosted speech path succeeded. Do not label failed direct calls as fast successful inference or silently compare them with successful S2T calls. A working personal-provider configuration is needed for parity measurement.

Two successful S2T speech calls and eight cleanup calls completed. Cleanup used GPT-OSS 120B pinned to `cerebras/fp16`, with five minimal-reasoning samples and three low-reasoning samples. The six follow-up samples counterbalanced reasoning order. Direct cleanup was prepared with the same 2048-token output bound and pricing controls as S2T; no direct cleanup succeeded.

| Stage | Samples | Wall time | Provider-call duration |
| --- | ---: | ---: | ---: |
| Speech | 2 | 401–479 ms | 313–349 ms |
| Cleanup | 8 | 344–10684 ms | 284–10644 ms |

Cleanup median was 615 ms across the mixed reasoning samples. The slowest cleanup spent 10644 ms inside the provider call and approximately 40 ms elsewhere. Durable reservation took 8–11 ms. The provider duration includes its network round trip and response handling, so this does not distinguish provider queuing from model inference or network delay. The follow-up cleanup calls ranged from 344 to 2114 ms. This small sample does not demonstrate that low reasoning is slower than minimal. No user preferences were changed.

Confirmed S2T charges correspond to USD 0.00697333 of purchased credits, under one cent. The persistent budget conservatively commits maximum possible cost before dispatch, including failed direct attempts, output limits, fees and the 9000-microUSD credit funding conversion. Its cumulative bound is USD 0.1316787, below the USD 0.20 authorization. No paid retries or new tests should be run without retaining that budget state. Existing JSON reports use `chargedUSD` for purchased-credit dollar equivalent, not raw upstream cost.

The speed repair is unfinished. The measurements establish real provider-call variability and smaller S2T overhead. They do not establish direct-route parity, nor justify changing the selected model, reducing quality, or exposing shared provider secrets. The user chose to continue with S2T timings only. Personal-provider testing is no longer pending and was not retried.

The canonical app remains S2T 1.0.1 Build 606. This step changed service instrumentation only; it did not rebuild or restart the app.

## S2T-only continuation

At the user's request, three further speech/cleanup pairs used S2T only, the same synthetic fixtures, GPT-OSS 120B on Cerebras, and the saved low reasoning setting. All six requests succeeded. Speech took 484–536 ms; cleanup took 441–793 ms. Time outside the provider call was 145–157 ms for speech and 74–96 ms for cleanup. This includes client network time, upload, central routing and durable accounting, not just billing CPU time. No setting or inference route was changed.

Across all 16 successful S2T requests, confirmed charges correspond to USD 0.01113556 of purchased credits, approximately 1.11 cents. The cumulative conservative pre-dispatch bound is USD 0.17706832, still below the original USD 0.20 authorization. The cap was not reset for this continuation. Successful response and content checks passed, and final balance checks confirmed no pause or pending hold.

Full-study medians are 484 ms for speech and 699 ms for cleanup. The 10.68-second cleanup outlier remains in the report. The additional samples are characterization, not a before/after performance improvement. Direct routing and speed parity remain unfinished; no quality-reducing model change, parallel paid retry or premature cleanup cancellation was introduced to hide the latency.

## September 24 credit route repair

The settings model menu could collapse GPT-OSS 120B's automatic and Cerebras entries into one model choice, then overwrite the selected Cerebras host with Automatic. The model choice now prefers the configured Cerebras endpoint, and the inline picker offers published host names in a native dropdown. A hidden packaged check covers a catalog with Automatic listed before Cerebras and confirms the selected model and host remain paired.

For a nonconfigured pinned host, the credit service used to fetch the full OpenRouter model catalog and then that model's endpoint record before reserving credits. It now validates the model, task, selected host and price from the endpoint record alone. Configured routes still bypass metadata fetches. The regression check fails against the old sequence when the full catalog is unavailable, and passes against the new sequence. The current public GPT-OSS 120B endpoint record lists Cerebras `cerebras/fp16` with status 0; its price stays within the service's bounded quote.

One unauthenticated read from this Mac took 257 ms for the 928 KB full catalog and 110 ms for the 22 KB GPT-OSS endpoint record. These are single public metadata reads, not credit inference timings or a production before/after sample. For a nonconfigured pinned host, the change removes the first read from the sequential route. It does not affect the configured Cerebras route, which already skipped metadata.

During recording, the native app now warms the authenticated credit Durable Object through a lightweight `/api/v1/warm` read instead of warming only the public front Worker. This overlaps object startup with recording and sends no audio, transcript or provider request. The earlier real measurements found roughly 74–96 ms outside the provider call for cleanup and a 10.64-second provider-call outlier. No new paid inference or working direct-key comparison was run, so an end-to-end speed gain and parity with a direct key remain unproven.

All 175 billing tests passed. The exact dry-run Worker bundle passed the isolated Cloudflare runtime check with fake external services, including the authenticated warm route. Canonical S2T 1.0.1 Build 840 passed packaged `--verify-credits`, `--verify-models-window`, `--verify-recording-startup --require-nonblocking` and `--verify-build` with hidden synthetic fixtures. The recording fixture checked that personal AssemblyAI speech and S2T cleanup warm independently. `bash scripts/test.sh` could not run its Swift tests because the existing `DictionaryTests.swift` calls `DictionaryObservation` with a removed `insertionSelection` argument.

The Worker bundle SHA-256 is `f5e717e9e0214a56fbd7ccf0810970e6256fc2f4815ed07608dfbcf05c2c0466`. A diff against the previously deployed bundle `d003ff9f156e92fd5969b9c8a909cb8149788b6c99396631f0f6a635c0fc0b9a` contains only pinned-host metadata validation and the warm route. Cloudflare uploaded no changed static assets, and version readback showed identical bindings and runtime settings. Worker version `dfdd56ca-f58d-414f-88e0-d77c7fb39986` now serves 100% of traffic. Production health returned HTTP 200 with durable SQLite and live mode. No paid provider request was made after deployment.
