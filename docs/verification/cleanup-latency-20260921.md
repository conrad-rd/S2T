# Cleanup latency investigation

The latest saved successful dictation at 16:33:05 local time had 11 output words. Finish to completion took 3.746 seconds, including 0.697 seconds for transcription, 2.302 seconds for cleanup, and 0.370 seconds for insertion return. These are app-stage durations, not a measurement of when pixels appeared in the receiving editor.

The saved cleanup route was S2T credits, GPT-OSS 120B, Cerebras FP16. The legacy Minimal setting normalizes to Low for this model. Jev was off. The separately saved Codex provider is inactive while cleanup uses credits.

## Live generated-text measurement

The user authorized up to 3 S2T credits. Three identical generated-text requests used the compiled production CreditsAPI, default editing instructions, GPT-OSS 120B, Cerebras FP16 and Low reasoning. This deliberately excludes personal dictation and custom instruction content. All returned the same correct eleven-word edit and identified Cerebras as the response host.

| Request | Client round trip | Provider interval | Remaining overhead |
| --- | ---: | ---: | ---: |
| 1 | 647 ms | 573 ms | 74 ms |
| 2 | 1,282 ms | 1,233 ms | 49 ms |
| 3 | 330 ms | 254 ms | 76 ms |

Provider intervals come from the service's Server-Timing response. They include the OpenRouter/Cerebras request, not solely model token generation. The remainder includes network, S2T routing and accounting. Durable reservation confirmation took 9–11 ms. Three samples show substantial provider variation but do not establish typical or worst-case latency, or explain the earlier 2.302-second cleanup measurement completely.

The requests charged 0.3448 credits total. The final read showed no pending holds and no spending pause. The runner writes its conservative commitment before dispatch, refuses repeated request IDs and refuses a fresh run when its budget file exists. Credentials were read noninteractively and retained only in memory. No settings, model, reasoning effort, prompt files or service deployment changed.

## Native completion change

Ordinary native text insertion waited 250 ms after a successful Paste action. Its completed text remains on the clipboard, and the completion copy already leaves identical S2T text untouched. Remove this wait for ordinary dictation. The separate Prompt destination path retains its 250 ms delay before screenshot attachments can replace the clipboard. Focus, selection, cancellation, Unicode fallback and permission checks are unchanged.

The same production post-action code, extracted and compiled with optimization, measured a median 254.25 ms before and under 0.001 ms after across seven executions each. This measures removal of the fixed completion delay only. It excludes AX dispatch, receiver insertion and provider inference; it does not establish an end-to-end speedup of the same size or faster first-visible text.

The independent queued-paste fixture accepts a native paste, reads the isolated clipboard 100 ms later, and checks that immediate completion preserves the full Unicode text and original surrounding text. Existing checks cover clipboard rollback, unchanged completion writes, focus and cancellation. No real fields, clipboard, microphone or screen capture are used.

Evidence and the bounded live runner are in `build/cleanup-latency-20260921`.

During packaged verification, two Prompt fixtures still expected the older verbose screenshot reference text. Their assertions now check the current `[attached screenshot: [1]]` marker, preserving the numbered-file association and complete-delivery checks. This changes verification only.

## Verified package

Canonical `build/S2T.app`, version 1.0.1 Build 742, passed `--verify-paste-batch`, `--verify-prompt-mode` and `--verify-build`. All 430 service/domain tests passed through `bash scripts/test.sh`. The running user app was preserved; reopening the canonical app loads the change. Live receiving-app insertion and real full-dictation before/after timing remain unmeasured.
