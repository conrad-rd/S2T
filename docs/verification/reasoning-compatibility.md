# GPT-OSS reasoning compatibility, September 19

The native app allowed Reasoning None and Minimal for `openai/gpt-oss-120b`. The account's credit cleanup settings contained None, and its direct OpenRouter cleanup settings contained Minimal, both with the `cerebras/fp16` host. These choices are incompatible with that model's supported Low, Medium and High levels. OpenRouter's read-only model metadata also marks reasoning mandatory for GPT-OSS 120B and 20B. [Cerebras documents the supported levels](https://inference-docs.cerebras.ai/capabilities/reasoning).

The reported message came from a shared backend error handler that described rejected cleanup requests as speech-model or recording errors. The original provider response body was discarded, so this investigation cannot prove the historical provider rejection's precise cause. A deterministic provider fixture rejecting unsupported reasoning levels reproduced the same misleading error before the repair.

## Behavior

For those two GPT-OSS models, including OpenRouter suffix variants, None and Minimal now use Low; Extra high and Maximum use High. Model default stays omitted, and supported explicit levels remain unchanged. Other models retain their settings. The app applies compatibility to direct OpenRouter requests and saved settings in Models and Writing, and only offers supported GPT-OSS levels. This does not require a model-catalog network request during dictation.

The backend also normalizes at provider dispatch to protect older running apps. It preserves the prepared request and its original idempotency fingerprint. Model, explicit host, fallback prohibition, privacy settings and credit budgets remain unchanged. Definitively rejected requests identify their actual operation and HTTP status. They expose no raw provider body, release only their own hold and replay without calling the provider again. Native cleanup recovery messages refer to the preserved transcription instead of claiming a recording needs retrying.

## Verification and deployment

- `bash scripts/test.sh`: 392 tests passed.
- Billing suite: 156 tests passed, including the new independent rejection fixture and compatibility cases.
- Canonical packaged `--verify-models-window` and `--verify-writing`: passed with isolated settings and hidden controls.
- `npm run test:release -- /Users/conradbaulig/Desktop/Code/S2T\ App/build/reasoning-repair/worker.js`: passed against the exact uploaded Worker and canonical executable, including 37 exact-Worker regression cases, pricing/refund/withdrawal checks, twelve dictation cycles, three cancellations and deliberately lost successful responses.
- `--verify-build`: compiled identity, bundle metadata and menu label agree.

Canonical app: S2T 1.0.1 Build 673, compiled `2026-09-19T21:10:37Z`, at `build/S2T.app`. Executable SHA-256: `a60e64864d1f16470a4c32926acfda31ac2ac79fbc052b15ec7ae9a881e94216`.

Worker version `53eafcb6-e237-476c-a7fc-2376833426a1` serves 100 percent of traffic. Published source readback matches tested SHA-256 `7dcabefb737c9d3dee5259d2ffde5e90d67d016ac012bf4eb9c68b4dceb96731`. Deployment changed only reasoning compatibility and rejection messages relative to the fresh production bundle. Existing bindings, secrets, sales allowlist, pricing, withdrawal handling and rate limits were preserved. The upload refused to proceed if production settings or deployment changed after preparation.

Production health at `2026-09-19T21:16:27.522Z` returned HTTP 200, `paused:false`, no incidents and no pending requests. This is a point-in-time observation.

Evidence is under `build/reasoning-repair`, including the scoped diff, verification record and logs. Provider responses and payments were simulated. No real inference, purchase, microphone recording, user clipboard, Keychain credential access or screen capture was used in verification. The model metadata lookup and production health/source checks were read-only live calls. These tests establish the covered behavior, not future provider availability or universal model compatibility.
