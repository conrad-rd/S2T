# Optional Jev cleanup

Settings → Models → Text cleanup → Jev cleanup has three choices. Off is the default.

- Before normal cleanup asks Jev to approve local dictionary matches and hesitation removals, then sends the edited text to the selected cleanup model.
- Finish simple transcripts can omit that second request when every proposed edit is decisively accepted or rejected and Jev judges the limited edits sufficient. This shortcut requires Clean up mode, the default instructions, no Prompt session, and clipboard context off. Email, Notes and custom prompts retain the selected model. Verbatim never calls Jev.

Choose TypeSafe, OpenRouter Jev 1.13, or OpenRouter Jev latest under Connection and model. OpenRouter reuses the saved OpenRouter key. Direct TypeSafe needs a separate TypeSafe key in Settings → API keys. It uses the existing credentials vault and an authenticated read-only GET /v1/models check. No TypeSafe key is sent to another provider. Jev requests reject redirects on both connections. Provider charges are separate from S2T credits.

The app sends the transcript, writing instructions and matching candidate spellings. The fast-path question also receives the parsed preferred dictionary spellings so it can flag potential corrections the local matcher missed. The raw dictionary document and clipboard history are not sent to Jev. Dictionary candidates come from explicit Replaces records, preferred spellings matched across up to three words, and single-character spelling differences in terms of at least five characters. Ambiguous overlapping matches are left to normal cleanup. Dictionary notes the parser cannot represent disable dictionary edits and the shortcut, leaving them to the normal cleanup model.

Jev returns yes/no probabilities for exact candidate edits. Code applies only approvals of at least 0.98. Values above 0.02 and below 0.98 retain the original span and prevent the shortcut. These are conservative experimental thresholds, not measured error guarantees. Quoted text, code, URLs, email addresses and opaque placeholders are excluded from candidates. Hesitation removal must retain correction cues, meaningful reactions and German words such as um. Repeated meaningful words are not deletion candidates.

Direct requests use jev-1.13.0. OpenRouter uses typesafe/jev-1.13 or ~typesafe/jev-latest through its Decisions API. Requests allow at most 48 candidates and 12 KB of transcript text. The shortcut is limited to 3 KB. Jev requests have a three-second deadline and no automatic retry. Missing keys, service failures and invalid decisions fall back to normal cleanup of the original transcript. If that cleanup fails, the original transcription remains the delivery fallback. An empty hesitation-only result is not inserted or copied. Last dictation shows the edit count, request time and whether the normal model was skipped.

S2T credit requests save their prepared cleanup text in the encrypted recovery record before submission and reuse it for the same payment request on retry. Legacy transcript retries bypass Jev rather than change a potentially submitted request. Successful delivery removes this text with the other recording content from the completion record.

## Verification

Run `bash scripts/test.sh`, then `bash scripts/build-app.sh`. Check the canonical packaged executable with `--verify-jev`, `--verify-api-keys`, `--verify-models-window` and `--verify-build`.

Core tests cover dictionary matching, Unicode spans, hesitation deletion, protected text, uncertainty, conflicting edits, malformed responses, bounds, request credentials, cancellation, formatting guards and recovery encoding. The hidden Jev probe drives actual persisted controls and the dictation pipeline with fake transports and an isolated pasteboard. It checks Off, preliminary cleanup, model bypass, uncertain/auth/missing-key fallback, Email/clipboard/Verbatim behavior, failed normal cleanup, empty output and cancellation.

These tests do not establish real Jev accuracy, German accuracy, provider access, or production latency. No live model requests, real credentials, microphone capture, field reads or screen capture are used.

API contract: https://docs.typesafe.ai/api
Model details: https://docs.typesafe.ai/models

## Verified September 19, 2026

S2T 1.0.1, Build 645 passed the packaged Jev, API-key, Models, credits/recovery and build-identity checks, plus signature verification, while holding the package lock. All 371 compiled tests passed, including 16 Jev tests. The final test bundle was run through Xcode's XCTest runner after concurrent source edits interrupted the application compilation in scripts/test.sh. The canonical build includes the final dictionary-coverage safeguard. Live TypeSafe accuracy, account access and latency remain untested.

Jev cleanup also offers OpenRouter Jev 1.13 and Jev latest. These use the saved OpenRouter key and POST `/api/alpha/decisions`, with models `typesafe/jev-1.13` and `~typesafe/jev-latest`. Keep this route separate from normal cleanup host and reasoning settings. Preserve direct TypeSafe as the existing default. Verify all three routes, persistence, missing keys and account-specific failures with `--verify-jev`.

OpenRouter contract: https://openrouter.ai/docs/cookbook/building-agents/gate-tool-calls-with-jev

OpenRouter addition verified in S2T 1.0.1 Build 648. Packaged Jev, API-key, Models and build checks plus signature verification passed. All 374 selected tests passed, including 17 Jev tests. The required full script stalled in the unrelated S2TBenchTests.TransportTests.testProcessTimeoutAndCancellation test; the separate run excluded that suite. No live provider request was made.

## S2T credit connection

Choose S2T credits · Jev 1.13 in Connection and model to use the existing saved S2T key. No TypeSafe or OpenRouter customer key is required. This is independent of the normal cleanup model's connection. The pinned model is typesafe/jev-1.13; latest remains available only through direct OpenRouter. The feature remains off by default.

The native credit request uses operation decisions and a deterministic JSON body digest in its recording request ID. Retries retrieve the encrypted result without issuing another provider request. The server permits only bounded Noul questions and the pinned model, uses the existing hosted OpenRouter key, and forwards no normal-cleanup host or reasoning settings. It reserves a conservative byte-derived token bound at the published USD 0.042 per million input tokens, then settles the actual reported cost through the existing fee and credit calculation. Invalid answers with a valid receipt settle as an error before normal cleanup resumes. Missing receipts or costs retain the affected hold under the existing recovery rules.

Worker 3c769a36-c898-4fc1-aeaa-1d4e274b6b66 is live. Exact scoped source readback SHA-256 is 054de519ddb2565fb0169e1e3bb257d7e61e1c30de7df7e49fe6802cbb5ed02c. Deployment preserved live secrets, existing routes and all other bindings. Artifacts are in build/jev-credits. Read-only operator health confirmed paused=false and no open incidents after deployment; one user request was pending at that moment.

S2T 1.0.1 Build 655 passed hidden Jev, credits, Models and build checks plus signature validation. All 18 Jev core tests and three Jev billing tests passed. The exact scoped Worker passed the isolated Cloudflare runtime check for routing, billing, encryption, replay and account isolation. The full Swift run had unrelated AssemblyAI endpoint/fallback expectation failures; the full billing run had failures in concurrently added billing-audit tests. No real inference, payments, recordings or screen capture were used for verification. Live model access, accuracy and latency remain untested.
