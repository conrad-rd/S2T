# Paste, response time, and bottom glow

## What was observed

The user's saved settings had automatic paste enabled and Verbatim selected. OpenRouter was therefore absent from the reported dictation delay. The old paste implementation posted back-to-back global Command-V events and did not check the focused field or resulting text. The reported destination was Raycast. Accessibility permission was granted, but Raycast was hidden during the diagnostic check and exposed no focused field. The exact Raycast failure could not be reproduced because computer control failed with `CUA_REPL_ENABLED_SURFACES is required`.

## Changes

Insertion now captures the target app and accessibility element before recording, checks both before inserting, and waits for held modifiers to clear. It tries selected-text insertion first, then selection-preserving value replacement for writable native search fields. Otherwise it posts a marked Command-V pair to the target process. S2T's activation monitor ignores its own paste events. A read-back confirms the expected text where possible. An unconfirmed or skipped insertion leaves the text on the clipboard and displays a hint above the bottom edge for five seconds. No Enter key is sent.

Short dictation now uses AssemblyAI's immediate endpoint with a connection opened during recording. This removes the upload/job/poll sequence from supported clips up to 120 seconds. The batch path remains for longer recordings, unsupported audio formats, and the Extended language support setting. Fast dictation supports the immediate model's 19 languages. OpenRouter model selection is unchanged.

The listening effect now uses low blurred pools of color beneath the screen edge, with a 1.2-point rim. The previous filled wave shapes are gone. The separate two-point loading line remains. Quiet, speaking, and loud previews were rendered against light and dark backgrounds from the packaged executable.

## Measurements

A fixed synthetic English recording was generated with macOS speech synthesis. It contains only a test sentence about moving a meeting. The same WAV was submitted using the saved AssemblyAI key through both paths, with no microphone recording involved. No key or transcript was logged.

| Path | Elapsed after audio was ready |
| --- | --- |
| Original batch run 1 | 3.628 seconds |
| Original batch run 2 | 6.048 seconds |
| Immediate, connection opened beforehand | 0.770 seconds |

Both paths returned 76 characters with identical words. The immediate path's separate connection warm-up took 0.633 seconds. In the app, that work overlaps recording. These are individual network samples, not percentile estimates or a guarantee of future response time. The second comparison was about 7.9 times faster after recording ended. OpenRouter rewriting and insertion time are excluded.

## Verification and limits

All 36 tests passed, including short-clip multipart upload, bounds for duration and sample rate, empty speech, credential-free connection warm-up, selection replacement, invalid ranges, and UTF-16 surrogate boundaries. The app builds and signs successfully. The packaged effect was visually inspected on light and dark backgrounds.

Live Raycast insertion remains unverified. Its field was hidden and the computer-control connection was unavailable. The new insertion diagnostics and visible fallback are intended to make a subsequent failure identifiable rather than silent. No successful Raycast insertion is claimed here.

Sources: [AssemblyAI Sync API](https://www.assemblyai.com/docs/sync-stt/getting-started/transcribe-a-short-audio-file), [audio requirements](https://www.assemblyai.com/docs/sync-stt/audio-requirements), [connection warm-up](https://www.assemblyai.com/docs/sync-stt/connection-pre-warming).

## Follow-up: reproduced insertion failure

The updated running app recorded `pasteSent`, confirming that a paste was attempted but not verified. Another session recorded `noTarget`, covering the separate case where recording started in S2T itself.

A bounded native integration probe opened the destination search field, saved its current text and selection in memory, attempted the fixed phrase `S2T insertion check` through the production insertion code, and read the resulting value. It restored the original field contents and clipboard afterward without executing a command.

The original selected-text path returned Accessibility success while the field stayed unchanged. A writable AXValue update, preserving the original selection, successfully inserted the expected phrase. The production code now prioritizes that path for native text fields. If an acknowledged operation has no visible effect, fallback continues only when focus is unchanged and the original text is intact, preventing duplicate insertion after a partial update. The final direct-insertion check returned `inserted` and read back exactly the expected text.

Start now uses a history of external app activations. When invoked in S2T, it records the previous external app as the destination. At insertion time it returns to that app only if S2T is still foreground, then obtains its current focused field. Fn continues to capture the currently focused field. An unrelated foreground app is never activated over.

The live Start-return integration check was not completed. The user explicitly asked to stop using Raycast, so all further Raycast interaction stopped. Do not run the Raycast probe or inspect the app without renewed explicit authorization. No later end-to-end Start-return success is claimed.
