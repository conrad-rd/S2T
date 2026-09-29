# Routing recovery and model selection

September 18, 2026.

The live ledger showed one `provider_incomplete` incident and a global pause. A cleanup request reached OpenRouter, then hit incomplete output under the old 512-token ceiling. The service treated that result as an unknown charge and paused subsequent speech requests. This explains why a later dictation could fail before transcription.

The provider adapter now separates a known, billed incomplete completion from an unknown outcome. It validates the returned cost and receipt, settles that charge once, stores an encrypted error, and lets the native client deliver the original transcript. It never delivers a partial completion. The live cleanup output ceiling is now 2048 tokens, within the existing request budget. Definitive provider rejection statuses release their hold and retain a bounded, sanitized error. Missing receipts, invalid costs, timeouts and charge overruns still fail closed. Rejections do not disable unrelated requests.

The native client retries one interrupted transport request with its original idempotency key. A submitted request is polled by its server ID; it is not resubmitted under a fresh payment identity. Definitively rejected requests can be retried explicitly. Recordings remain in app memory after failure. Successful transcription still reaches original-text delivery when cleanup fails.

S2T speech settings now offer AssemblyAI and OpenRouter separately from personal providers. OpenRouter offers Whisper V3 Turbo, Whisper V3 and Whisper 1. The service uses the same `/api/v1/audio/transcriptions` payload as personal OpenRouter requests and settles the returned `usage.cost` against its `X-Generation-Id` receipt. Two-minute input and existing spending limits remain. Routing controls and per-request privacy restrictions are not supported by OpenRouter's speech endpoint; the implementation does not pretend otherwise.

## Connection measurement

Ten read-only requests per variant against the production public health endpoint, on the same machine and URL:

| Client | Reported median |
| --- | ---: |
| New ephemeral URLSession per request | 52.4 ms |
| Reused ephemeral URLSession | 14.4 ms |

The benchmark reports the upper middle sample of ten values. Raw samples and script are in `build/routing-repair`. This measures HTTPS connection overhead, not inference, audio uploads or complete dictation latency. Credits now reuse their session and warm its connection while recording. Redirects remain disabled and credentials remain scoped to their intended service.

Direct S2T-key inference and exact latency parity are unfinished. OpenRouter supports management-key provisioning of individual limited keys, but the current service has no such lifecycle or delegated accounting. AssemblyAI Sync documentation uses an account API key, without a documented scoped Sync token. Exposing shared provider keys in the desktop app would defeat account isolation. No shared provider key was moved into the app, and no direct-routing claim should be made.

## Interface

OpenRouter cleanup, speech and vision use three Liquid Glass suggestion buttons beneath their model fields. Applying one hides that task/provider's suggestions until its model changes. X persists dismissal separately for each task/provider. Model fields save on Return or focus loss. Vision retains asynchronous image-capability validation and rejects stale validation after draft edits; its independent Host field never inherits cleanup hosting. Reasoning and speed share one row.

Writing keeps only a model-name button beside AI writing. It navigates to a separate screen containing provider, model, host and options. Back preserves both document drafts. Native multiline editors retain local save, conflict protection and reviewed AI suggestions.

## Deployment and recovery

The user explicitly approved the production deployment and recovery. Worker version `97565150-4a2e-4e3b-a7a7-12938f028dee` contains only the scoped routing/policy/provider changes and the rejected-request ledger transition. The source readback matches SHA-256 `506f7c10b77e68cf2360598e4fc00c248653072268176a53a366914797cc29f4`. Existing assets, secrets, allowlist, key limits and unpublished privacy changes were preserved. The exact artifact and diff are in `build/routing-repair`.

The one failed request was resolved through the existing audited writeoff action. S2T absorbed the reserved maximum of less than USD 0.02; the customer hold was released. The existing ledger safety checks then allowed resume. Live health confirmed `paused: false`, no pending requests and no open incidents. No new paid inference, recording, screenshot or customer transcript read was used for these checks.

Verification includes Swift domain/service tests, billing tests with a reproduction of truncated output, the exact deployed artifact in an isolated Cloudflare runtime, and packaged hidden controls. Live provider model access and end-to-end latency have not been tested.

References consulted:

- https://openrouter.ai/blog/tutorials/transcription-on-openrouter/
- https://openrouter.ai/api/v1/models?output_modalities=transcription
- https://openrouter.ai/docs/guides/overview/auth/management-api-keys
- https://github.com/AssemblyAI/assemblyai-skill/blob/main/skills/assemblyai/SKILL.md

## Final verification

Canonical S2T 1.0.1 Build 606 passed `--verify-credits`, `--verify-models-window`, `--verify-writing`, `--verify-models`, `--verify-api-keys`, `--verify-local-models`, `--verify-settings-sidebar`, `--verify-prompt-mode` and `--verify-build`. The packaged native HTTP contract also passed against an isolated ledger.

All 66 billing tests passed. The final Swift run passed 326 tests, including interrupted request recovery, original-text delivery, host isolation and existing domain checks. The full `bash scripts/test.sh` run stalled in the pre-existing `TransportTests.testProcessTimeoutAndCancellation` benchmark test, waiting for an already-exited child. Only that test process was stopped; the final suite excluded that one unrelated test. Its sample is retained in `build/routing-repair/test-stall.sample.txt`. That benchmark hang remains unfixed.

The running user app was not quit or activated. Reopen the canonical app to load Build 606. No physical microphone, user text field, real provider inference or screen capture was used for final verification.
