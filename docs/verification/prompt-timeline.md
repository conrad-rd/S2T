# Prompt timeline verification

S2T 1.0.1, Build 184 implements temporary local frame history in Prompt mode, final-transcript timestamp matching, batch image analysis and batch attachment delivery. The canonical package is build/S2T.app.

The reported missing references had two concrete limits in the previous session implementation: references within 0.8 seconds were rejected, and each session stopped at eight. Analysis and image delivery also ran serially. Existing stored timing metrics showed transcription at 0.765 seconds and cleanup at 0.727 seconds, but did not contain image-analysis or attachment timing. New runs record those two additional durations without logging prompt contents.

## Controlled comparison

Both measurements used eight references and the same injected transport delays: 40 milliseconds for each public metadata response and 250 milliseconds for each image-model response. Attachment delivery used the production 750 millisecond wait, an isolated clipboard and injected unposted paste events.

| Measurement | Previous path | New path |
| --- | ---: | ---: |
| Image analysis | 2.383 s | 0.305 s |
| Attachment waiting | 6.192 s | 0.760 s |
| Combined measured stages | 8.575 s | 1.065 s |
| Metadata reads | 8 | 1 |
| Image-analysis requests | 8 | 1 |
| Paste events | 8 | 1 |

This comparison measures request and paste serialization overhead. It excludes transcription, cleanup, frame capture, PNG conversion, text insertion and real model behavior. A larger image request may take longer than one image at a live provider. It is not an end-to-end speed claim. Text cleanup and image analysis now start concurrently after transcription.

Baseline source copies and output are in build/prompt-timeline-baseline. The updated benchmark output is build/prompt-timeline-after-timing.log. Run the packaged executable with `--verify-prompt-mode --benchmark` to repeat the controlled workload without a real provider or screen capture.

## Checks

All 182 domain/service tests passed. Timestamp tests cover twelve rapid references, corrected local recognition, missing words, long gaps, audio-origin offsets, stale frames, opt-in AssemblyAI timestamps, milliseconds-to-seconds conversion, local endpoint second timestamps, malformed timestamp entries and ordered batch image requests with separate model settings.

The packaged prompt probe matched twelve distinct generated frames to references 250 milliseconds apart, including the final cue. It checked memory/count limits, history clearing, missing-frame warnings, PNG saving, cancellation and image-model account failure. Synthetic audio checks preserve recording samples and the final Speech buffer on finish. Pipeline fixtures check successful cleanup, original-text fallback and skipping attachments when text delivery fails.

Isolated pasteboard checks cover one batch event, all ordered file URLs, output markers, a single-image PNG fallback, unreadable-file atomicity, focus and permission guards, open menus, cancellation and preserving a newer clipboard copy. Hidden WebKit rich/plain editor fixtures received all 851 expected UTF-16 units with zero submissions using production-generated Unicode events dispatched locally.

The packaged prompt, menu, onboarding, model, API-key and build-identity checks passed. Logs are build/prompt-timeline-tests.log, build/prompt-timeline-build.log and build/prompt-timeline-package-checks.log. The app was restarted gracefully from its canonical location.

## Limits

No screen recording or screen-pixel inspection was used during implementation verification. The checks also avoid real microphone capture, Speech recognition, credentials, provider calls, posted key events, user clipboard and user browser fields. Actual ScreenCaptureKit stream behavior, live pointer/frame synchronization, model latency and whether the receiving browser accepts the pasted file list remain unverified. Hidden WebKit typing checks do not establish attachment acceptance.

The production buffer uses four samples per second and JPEG quality 0.72 to bound memory. Pointer positions and the most recent display frame are sampled together, but a display frame can precede its cursor sample. Rapid motion can select a nearby position. Only selected crops are retained as PNGs and sent externally. At most 64 references are delivered; other unmatched references produce a visible count. Session memory stops growing at 2400 frames or 256 MiB.
