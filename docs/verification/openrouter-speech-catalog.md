# OpenRouter speech catalog

September 19, 2026.

The reported MAI-Transcribe 2 error came from S2T credit model validation, before provider dispatch. The live policy exposed four models and its validator hard-coded those same four IDs. Personal OpenRouter already loaded the public speech catalog and used the documented transcription endpoint.

The S2T policy now includes all 21 transcription models published in OpenRouter's catalog on this date. Configuration remains the allowlist: a syntactically valid but unpriced model is rejected before reservation. AssemblyAI remains restricted to its supported model. New releases still require a catalog/pricing update rather than automatically spending against unreviewed rates.

Duration-priced additions reserve at least 125 microdollars per rounded-up second, or 125% of the highest published endpoint rate if greater. Azure MAI prices are per hour and are converted to seconds. Existing model reservations are unchanged. GPT-4o Transcribe and Mini use token billing, so their temporary reservation is the full existing 20,000-microdollar request ceiling instead of an invented per-second price. Settlement charges the returned actual usage and releases the remainder. Existing overrun/uncertain-charge safeguards remain. No provider-price or successful-inference guarantee follows from catalog acceptance.

Models now offers Reload speech models for S2T, using the existing read-only balance/catalog refresh. The hidden credits probe selects MAI 2 from a mocked service catalog and checks the outgoing model ID with synthetic audio.

Verification: the initial regression reproduced the missing 17 models. All 114 billing tests and 375 Swift tests passed. `node speech-deployment-check.mjs` exercises the exact scoped Worker artifact in Miniflare, passing all 21 models through authenticated balance/catalog, request preparation, reservation and settlement. External calls are mocked. Synthetic request timestamps/counters are adjusted between cases to avoid the production rate limits; live limits are unchanged. No real recordings, credentials, payments or provider inference were used in tests.

Published Worker version `971cad4e-75b8-442b-9cc6-4f6fc483b25e`, source SHA-256 `b9ad0e874b22063cde8628d7b1af7d2085878b22f37a085b20b87024b32b393c`. Deployment rebased from the live artifact, changed only speech policy validation/reservation and its catalog, and preserved all other code, bindings, secrets and assets. Readback confirmed all 21 models and unchanged other bindings. Audit artifacts are under `build/speech-catalog-repair`.

Sources:

- https://openrouter.ai/api/v1/models?output_modalities=transcription
- https://openrouter.ai/docs/api/api-reference/stt/create-transcription
- https://openrouter.ai/microsoft/mai-transcribe-2
- https://openrouter.ai/microsoft/mai-transcribe-1.5
- https://openrouter.ai/openai/gpt-4o-transcribe

Canonical S2T 1.0.1 Build 646 passed packaged `--verify-credits`, `--verify-models-window` and `--verify-build`. The credits check selected MAI 2 and verified its dispatched model ID. The app was not activated or restarted. Concurrent source edits interrupted the first compile/package attempts; the successful package preserved those newer changes.
