# API key feedback

Saving a key stores it in Keychain and starts a read-only authentication check. The editor shows Checking, then Key accepted or an inline error with Save and retry. A warning marks API keys, the provider submenu, and the affected processing-provider choice. Warnings remain visible when another processing provider is selected. Network or service failures say the key could not be checked, without claiming it is invalid.

Runtime HTTP 401, 402, and 403 errors carry a typed account identifier. Authentication, credit, and permission failures go into that account's key editor. Other failures stay in Status. Processing failure still delivers the original transcript. Key edits invalidate pending checks; runtime results cannot flag a replacement key, and late validation cannot erase a runtime rejection.

Verification uses fake keys and mock transports only. The 45 core tests pass, including endpoint/credential isolation, read-only validation, typed runtime failures, response redaction, and unrelated feed/service errors. `--verify-api-keys` checks the Save control, inline red feedback, warning labels, provider switching, successful correction, delayed runtime failures, stale validation responses, and network uncertainty. `--verify-menu-highlights` checks menu interaction regressions. Neither check opens menus, captures the screen, uses the clipboard, or sends provider requests. Successful authentication with the user's real keys was not tested.

Read-only endpoints follow the provider documentation:

- [AssemblyAI transcript listing](https://support.assemblyai.com/articles/4527311510-can-i-get-a-list-of-all-transcripts-i-have-created), GET /v2/transcript?limit=1. Response content is discarded.
- [OpenRouter current key](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-api-key), GET /api/v1/key.
- [Cerebras authenticated models](https://inference-docs.cerebras.ai/api-reference/models/list-models), GET /v1/models.

An accepted check confirms authentication for that endpoint. Account credit and access to the selected inference model can still fail later; those failures update the same key feedback during dictation.
