# S2T provider settings

Choose S2T in the existing Speech to text or Text cleanup provider menu. Cleanup shares its model controls with OpenRouter. Model ID and Host stay visible and save on Return or leaving the field. Reasoning and Speed share one row, without an Advanced disclosure, preset action or Save buttons. Three dismissible Liquid Glass bubbles suggest GPT-OSS 120B on Cerebras, Muse Spark Contributor, and GPT-OSS 20B. Applying one hides the bubbles until the model changes; X persists dismissal. S2T speech offers AssemblyAI or OpenRouter, with Parakeet TDT 0.6B v3, Whisper V3 Turbo, Whisper V3 and Whisper 1 available through the service catalog. Speech retains the two-minute limit. See routing-recovery.md for the production outage repair and remaining direct-routing limitation.

S2T saves its model, host and per-model options separately from personal OpenRouter settings. A single S2T key serves both tasks. The API keys row shows available credits with pending reservations separately. Saving a key and opening settings refreshes account information through the authenticated read-only balance endpoint. Editing or replacing a key cannot retain another key's displayed balance.

The balance response includes the configured model catalog. Pricing policy alternatives carry model, optional host, title, ceilings and the optional Contributor consent requirement. Requests select only a configured model/host pair. Reasoning, speed and consent participate in retry identity; legacy requests retain their old fingerprints. Provider requests preserve price ceilings, exact returned-cost billing, existing budgets, privacy defaults and account isolation.

Muse Spark Contributor uses `meta/muse-spark-1.3-contributor`. Its unchecked native checkbox allows Meta to use prompts and responses to improve its products. The native client rejects unconsented requests before networking, and the billing service enforces consent before reserving credits. This permission persists only for that model and task/provider. All other models keep `data_collection: deny`, even if passed an options object containing Contributor consent.

Run `bash scripts/test.sh`, then `bash scripts/build-app.sh`. On the canonical packaged app run `--verify-credits`, `--verify-models-window`, `--verify-api-keys`, `--verify-models` and `--verify-build` sequentially because they use the same isolated preview preference suite. The credits probe tests all four S2T/personal routes, selected request options, per-model consent, key replacement, stale validation, hidden balance geometry and original-transcript delivery after a billing failure.

From billing-local run `npm test`, `npm run test:cloudflare`, and `npm run test:native`. These use synthetic inputs, fake keys and isolated ledgers. No real payments, microphone capture, screen capture, Keychain credentials or real text fields are used. Mocked provider success is not a live model-quality or latency measurement.

Model references reviewed September 18, 2026:

- https://openrouter.ai/openai/gpt-oss-120b
- https://openrouter.ai/openai/gpt-oss-20b
- https://openrouter.ai/meta/muse-spark-1.3-contributor

The September 18 live deployment used the retained scoped bundle in `build/s2t-provider-worker.js` because the working tree also contained unpublished privacy maintenance. `node provider-deployment-check.mjs` exercises that exact artifact, including three catalog entries and rejection of unconsented Contributor requests before any reservation. See billing-local/LIVE.md for the deployed version and source hash.


Parakeet repair, September 18: OpenRouter lists `nvidia/parakeet-tdt-0.6b-v3`, but the S2T service catalog and policy validator omitted it. Both now allow that exact model, retaining the two-minute clip limit, existing conservative reservation and actual provider-cost settlement. Reopen the Models pane to refresh its key-linked catalog. The Model ID editor and picker save the same choice.

Worker version `39b7557b-9d46-4a9e-9e2f-3006b3f60fd3` deployed only the allowlist entry and catalog addition. Source readback SHA-256 is `741079e2e2757e8ddbe5cf2e12a3bea9358ef42e2c961c208bfcb3e0ffc0360e`. All other live bindings and pricing matched the pre-deployment snapshot. Evidence is in `build/parakeet-repair`.

Verification passed 78 billing tests, 334 Swift tests, an isolated Cloudflare transcription/settlement through the exact deployed artifact, and packaged `--verify-credits` and `--verify-build` on S2T 1.0.1 Build 622. The packaged credits probe checks Parakeet picker selection, direct Model ID edits, persistence and outgoing model identity. No real audio, paid provider inference, user clipboard, or screen capture was used. Live provider inference remains untested.
