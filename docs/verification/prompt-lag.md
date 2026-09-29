# Prompt screenshot drawing performance

September 17, 2026. The reported lag is strongest while drawing or animating a screenshot.

## Measurement

The baseline and changed implementations ran the same optimized, generated workload on the same machine. No screen capture, microphone, real clipboard, user fields or provider requests were used. The probe sends unposted mouse events, updates hidden native windows and commits their layers.

| Measurement | Before | After |
| --- | ---: | ---: |
| Drag handler median | 0.017 ms | 0.017 ms |
| Selection update and native commit median | 0.008 ms | 0.003 ms |
| Selection update and native commit p95 | 0.013 ms | 0.004 ms |
| Selector drawing-layer area | 22,118,400 pixels | 133,536 pixels |
| Automatic layer flattening | Enabled | Disabled |
| Full generated output raster median | 0.647 ms | 0.651 ms |

The selector drawing-layer area falls by 99.4 percent. These are hidden-window CPU timings and layer dimensions, not displayed FPS or a GPU benchmark. Rasterizing the same complete output bitmap remains effectively unchanged. A five-second read-only process sample did not catch an active screenshot gesture and does not establish the cause of the user's live frame drops.

## Changes

The selector keeps one stationary desktop-sized window. Four thin clipped drawing layers replace its full-area shape backing, with direct WindowServer hosting and automatic flattening disabled. The generated reference checks that the four pieces produce the complete rounded border at normal and Retina scale, including tiny and fractional rectangles. Drag updates coalesce to the display rate, up to 120 Hz.

The screenshot deck uses a 262 by 214 point window. A separate flight window stays at most 401 by 300 points and moves without resizing its backing buffer. The spring scale, rounded image, highlight, shadow, border flash, collapse and Reduce Motion behavior remain. A new capture finishes the previous flight into the deck, bounding active animation work.

A prototype with four moving border windows was discarded because native window changes introduced multi-millisecond spikes. The final border changes only layer geometry.

Attachments still wait until dictation finishes and run before prompt text. This update does not change screenshot sampling, image analysis, or attachment confirmation and retry rules.

## Verification

Generated production-layer pixels match an independent complete rounded outline at 1x and 2x. Hidden native checks assert WindowServer hosting, disabled flattening, stable selector geometry, fixed flight backing size, landing, collapse, restart, cancellation and Reduce Motion. Existing Prompt checks cover gestures, attachments, delivery and capture ordering.

`bash scripts/test.sh` stalled in the unrelated benchmark subprocess timeout/cancellation test. The 294 service/domain tests pass separately. Running the suite with only `TransportTests.testProcessTimeoutAndCancellation` excluded passes 307 tests. That subprocess test remains unresolved by this screenshot-rendering change.

Raw baseline, changed measurements, process sample, package log and packaged verification output live under `build/prompt-lag`. Live screenshot animation smoothness and receiving-app attachment acceptance remain unverified.

## Packaged result

Canonical `build/S2T.app`, version 1.0.1 Build 574, passed `--verify-prompt-mode`, `--verify-prompt-mode --benchmark`, `--verify-onboarding`, `--verify-menu-highlights` and `--verify-build`. The executable, bundle metadata and menu identity agree. Concurrent builds were serialized with the package lock, preserving newer work.

The packaged run measured selection update plus native commit at 0.003 ms median and 0.023 ms p95 across 240 generated updates. Fixed-size flight moves measured 0.044 ms median and 0.064 ms p95. Hidden deck capture work measured 0.20 ms median and 0.60 ms maximum. These timings vary with concurrent machine load and do not establish visible frame rate.

## Follow-up after the reported lag persisted

The user clarified that the reported boxes were selection outlines. The first bounded live timing collector expired without catching the gesture. A later check saw the original process at 272.6 percent CPU, but it exited before sampling. An eight-second sample of the restarted Build 576 captured active rendering. Its appearance-render queue spent a substantial share of samples in `ChromaExpansion.field`, including repeated Within Input lower-edge calculations. This identifies costly shared rendering work, but does not measure the user's selection FPS.

A generated 1900-by-1800-point fixture reproduced cache failure in the actual production method. Its 2x vector texture is 109,440,000 bytes, larger than the 96 MiB NSCache budget. Four identical requests created four different textures. The previous screenshot-only benchmark omitted this competing glow workload.

| Production field request | Before | After |
| --- | ---: | ---: |
| First request | 593.55 ms | 37.77 ms |
| Second request | 581.22 ms | 0.05 ms |
| Third request | 586.50 ms | 0.01 ms |
| Fourth request | 578.97 ms | 0.01 ms |
| Reused textures after first request | 0 of 3 | 3 of 3 |

The current geometry now has one strong texture reference independent of the evictable cache. Within Input computes the lower boundary and its derivative once per column instead of evaluating them repeatedly for every pixel. The output resolution and all downstream shader, palette, native blur and screenshot animation behavior remain unchanged. The memory tradeoff is retaining one current vector texture even when it exceeds NSCache's budget, instead of continually allocating and rebuilding it.

The generated field matches an independent implementation of the original per-pixel finite differences within 0.0001 points for both circular and continuous corners and fractional canvas bounds. The packaged benchmark asserts reuse for the oversized fixture. These figures measure the reproduced field bottleneck, not live screenshot FPS. No automated screen capture, microphone capture or field-content inspection was used.

Artifacts: `build/prompt-input-lag/active-restarted.txt`, `before.log`, `after.log`, `prompt.log`, and the packaged verification logs in the same directory. The source snapshots keep the measured before/after workloads separate from concurrent edits.

Build 577, version 1.0.1, passed the packaged Prompt verification and benchmark, Within Input generated color/blur verification, input-latency and resizing checks, and build identity verification. The full `bash scripts/test.sh` suite passed all 308 tests. The initial snapshot test attempt lacked `docs/references`; copying those source fixtures into the snapshot resolved that test-environment failure. The formerly stalled benchmark subprocess test also passed in this run.

The running user app was not quit or activated during verification. Reopening the canonical app loads Build 577. Live displayed FPS after this fix remains unmeasured.
