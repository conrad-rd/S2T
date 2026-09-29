# Reasoning choices from model capabilities

The previous repair restricted GPT-OSS but still returned every reasoning level for other OpenRouter models. This allowed options that the selected model could not accept. The picker now uses each model's `reasoning.supported_efforts`, and excludes None when `reasoning.mandatory` is true. Unknown or missing effort lists result in Model default only. A model advertising a reasoning token budget without explicit effort levels also uses its default; S2T does not invent a list of effort values.

`Sources/S2TCore/Resources/OpenRouterReasoning.json` contains public metadata for 447 models retrieved from [OpenRouter's model API](https://openrouter.ai/docs/api/api-reference/models/get-models) on September 19, 2026. It includes model IDs, canonical aliases and reasoning metadata only. The shared catalog refreshes selected models from the public single-model endpoint without credentials, transcripts or prompts. Checks have a ten-second timeout, a one-megabyte response limit, a one-hour success cache and a one-minute retry interval after failure. Refreshed entries are limited to 256. The bundled snapshot remains available offline.

Cleanup, vision and Writing use the same data. Models without confirmed adjustable levels show a disabled Model default choice. Model switching updates choices and the effective saved selection. Background updates replace only the reasoning control in Models, preserving an active model or host text editor. Writing model edits have a 300-ms debounce. A failed check does not block dictation. Codex continues to use its own local catalog; Writing now also normalizes its displayed saved Codex choice.

The request builder independently normalizes options for direct OpenRouter and credit-funded cleanup. Supported values remain unchanged. Legacy GPT-OSS mappings remain Low for None/Minimal and High for Extra high/Maximum. Other unsupported saved values use Model default and omit explicit provider reasoning. This does not change the model, host, privacy setting or fast-routing choice. Existing backend compatibility remains deployed; this change does not publish another Worker.

Tests cover required and optional reasoning, missing or unknown metadata, unknown future effort strings, duplicates, refresh and cached requests, saved unsupported values, outgoing direct/credit requests and independence of model options. Packaged Models and Writing probes check different advertised effort lists and disabled default-only controls across model switches, including credit-funded cleanup and vision. All inference, payments, credentials and preferences used in verification are mocked or isolated; no screen capture is used.

Build and final verification evidence is recorded under `build/reasoning-catalog`.

## Verified result

S2T 1.0.1 Build 675, compiled `2026-09-19T21:29:11Z`, is packaged at `build/S2T.app`. The final native suite passed 396 tests. Packaged `--verify-models-window`, `--verify-writing` and `--verify-build` passed. The initial packaged check caught the SwiftPM resource path mismatch; the corrected loader uses the application resource bundle and the final checks exercised its bundled model data successfully.

The exact-artifact billing release check passed with 156 billing tests, 37 Worker regression cases, twelve completed native dictations, three cancellations and deliberately dropped successful responses. Provider inference and payments were simulated. The Worker is the unchanged production artifact from the preceding repair. No Worker deployment was required.

Executable SHA-256: `2607cb673c7128e3da1acec38ee13335f251cc8141959646296ea7cd9a023e17`. Worker SHA-256: `7dcabefb737c9d3dee5259d2ffde5e90d67d016ac012bf4eb9c68b4dceb96731`. Release verification finished at `2026-09-19T21:31:25.749Z`.
