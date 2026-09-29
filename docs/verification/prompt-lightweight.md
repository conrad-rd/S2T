# Prompt responsiveness and screenshot delivery

September 21, 2026. The user reported severe window-drag lag with Bottom, an unstable screenshot selection rectangle, and missing image attachments. The screenshot thumbnail preview is preserved.

The global shortcut event tap previously ran on the main run loop. Every ordinary mouse drag had to wait behind S2T layout and drawing, and PromptRegionCapture queried native display geometry even when no capture gesture was active. The single event tap now has its own run loop. Ordinary mouse events pass through immediately. Command-click still asks the existing gesture handler whether to consume the gesture. Captured drag updates retain only the newest pending position, and release delivers the actual final coordinates. Keyboard handling and the single Fn owner remain unchanged. Display geometry is sampled once per screenshot gesture.

A completing screenshot could also flash its old rectangle over a newer selection. Completed captures now leave an active selection alone, and drawing a new border clears the previous flash animation. The original thumbnail deck, spring flight, collapse and Reduce Motion behavior remain. Moving Bottom without resizing its window moves only the native panel origin, without forcing a content layout and display pass.

## Measurements

The generated drag workload used identical source fixtures before and after. No input was posted and no screen was captured.

| Workload | Before | Changed implementation |
| --- | ---: | ---: |
| 1,000 ordinary drag events through the capture handler | 31.838 ms | 0.002 ms |
| One ordinary drag while the main thread is occupied for 80 ms | 81.855 ms through former routing | 0.004 ms through current routing |

The second check measures queue blocking directly, using the old main-thread dispatch path and the actual new router. These timings establish input independence from S2T's main thread. They are not displayed frame rates or a measurement of live ScreenCaptureKit performance.

A separate synthetic two-display recording workload measured an 8.436 ms median for the existing encoder. A direct ImageIO prototype measured 10.140 ms in the first comparison, so it was dropped. Recording resolution, four samples per second, timestamps and history limits remain unchanged. The first process sample caught idle S2T and cannot establish the user's active GPU bottleneck.

## Image handoff

The old image paste waited 750 ms, then prompt text delivery overwrote the clipboard. An app that had not read the image payload yet could receive text instead. The new payload supplies ordered PNG bytes and saved file URLs on demand. Waiting ends after data requests, with a 1.5-second bound for an unresponsive reader. A clipboard reader is not treated as proof of receiving-app attachment acceptance.

Prompt text follows through Unicode events without replacing pending images. That path preserves graphemes and uses Shift for line breaks. Confirmed attachments allow the completed text to replace the clipboard. Unconfirmed attachments remain available on the clipboard, with the prompt available in Last dictation. A sent but unconfirmed batch is not automatically pasted again. An unsent batch may still retry after text delivery. Existing focus, menu, cancellation, changed-field and clipboard-change guards remain.

The native ordered-file fixture also follows Chromium's documented implementation, which reads the file URL from each pasteboard item: https://chromium.googlesource.com/chromium/src/+/refs/heads/main/ui/base/clipboard/clipboard_util_mac.mm

## Verification

`--verify-prompt-mode` includes a blocked-main-thread drag, a burst of 1,000 captured positions, the final release rectangle, shutdown, a completing capture during a new selection, delayed and partial image reads, native file-list reads, generated Unicode delivery, no duplicate image retry and the existing timeline, renderer and delivery checks. The mock speech endpoint now matches the production `/v1/transcribe` path; its old `/transcribe` path made the existing end-to-end fixture fail before delivery.

`bash scripts/test.sh` passed 414 tests. Raw logs and source snapshots are under `build/prompt-lightweight`. The older batch-paste fixture now sets its failed-recording phase before invoking Retry, matching the recovery guard.

No live recording, user clipboard, receiving-app fields, real provider calls or screen captures were used. Real receiving-app attachment acceptance and visible drag smoothness remain unmeasured. The running user app is preserved.

## Packaged result

The canonical app is S2T 1.0.1 Build 708. Its compiled identity, bundle metadata and menu label agree. Prompt, onboarding, Bottom window placement, glow, batch paste, menu highlights and the Prompt benchmark all pass on this exact package. The first glow run noticed a foreground-app change; the final run passed the focus check. All final checks ran sequentially while holding the package lock.

The packaged selection update and native commit measured 0.003 ms median and 0.007 ms p95. The unchanged recording encoder measured 6.967 ms median for the generated two-display fixture. These are controlled timings, not visible FPS. The attachment benchmark intentionally never reads its clipboard and therefore exercises the 1.5-second timeout.

Verified executable SHA-256: `9cea906051c90f602305af8f5703eb2e6e0eb6d2374cc0b3026e99dfbde62490`.
