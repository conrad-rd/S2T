# Prompt resource and attachment repair

September 21, 2026. Follow-up to the repeated report of Prompt lag with Bottom. The running app was Build 742, so this was not attributed to an old executable. A five-second passive stack sample caught idle S2T, with most main-thread samples waiting for events. It does not establish the active WindowServer or local speech-recognition bottleneck. No screen, microphone, real input field or user clipboard was read during verification.

## Changes

Bottom previously read a window's geometry twice and returned nil whenever the two rectangles differed. During a drag, a valid moving window therefore became a screen-bottom fallback. Alternating successful and rejected reads repeatedly changed the native panel size and glow geometry. The reader now uses the newer rectangle, then retains its existing focused-window identity and minimized/closed checks. Actual unavailable windows still use the existing fallback. This also fixes ordinary dictation with Bottom.

Prompt recording now requests full-range 4:2:0 buffers instead of BGRA. Full-display scope, four samples per second, JPEG quality, reference timing and original-sized selected PNGs remain. Chroma uses 2×2 sampling; luminance retains full resolution. Odd display dimensions round up by at most one pixel, and both complete and idle frames use the encoded image size for pointer coordinates. Apple lists this format as supported in [SCStreamConfiguration.pixelFormat](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/pixelformat).

The frame history now shares an immutable encoded image between complete and subsequent idle samples. Its byte budget charges that image once. Previously every idle timestamp spent the full image size again, even though the Data storage was shared. This could stop capture early. The existing 2400-frame and 256-MiB limits still apply, and clear/take release both frames and identities.

Screenshot feedback windows have fully clear native backgrounds. They have no backdrop sampler and do not need the 0.001-opacity background used by glow windows. The stationary selection window previously placed that background across the entire desktop union. Border layers, click-through behavior, WindowServer hosting, fixed window geometry, rounded thumbnails, flight and collapse remain. The existing coalesced pointer handling and protection against an old screenshot flashing over a new selection remain in place.

An accessibility Paste action that explicitly returns actionUnsupported or notImplemented now falls back to one targeted keyboard paste, after rechecking cancellation, destination, menu and clipboard ownership. A working native action no longer requires event-posting access. Ambiguous cannotComplete responses remain unrepeated, with unconfirmed images retained. These checks preserve the field selected at Finish.

## Measurements

A generated moving-window workload alternates motion between two geometry reads with stable reads. It uses the production reader and Bottom window controller, with hidden native panels. Across 120 reads, the old code fell back to the screen bottom 60 times and changed the panel's backing size 119 times. The fix produces zero fallbacks and zero size changes. Native placement median changed from 0.408 ms to 0.260 ms. These checks establish removal of geometry and backing-size churn, not displayed frame rate or total GPU load.

Identical generated 2560×1440 input was converted outside the timed section and then passed through the same JPEG encoder, alternating the old and new formats within each process.

| Measure | BGRA | Full-range 4:2:0 |
| --- | ---: | ---: |
| One capture buffer | 14,745,600 bytes | 5,535,360 bytes |
| Two-image encoding median, first run | 8.655 ms | 9.783 ms |
| Two-image encoding median, second run | 9.335 ms | 8.805 ms |

Per-buffer memory falls by 62.46%. The encoder timings do not establish a consistent CPU improvement. This is not a 63% reduction in total application memory or a measurement of live screen-capture bandwidth.

The generated JPEG comparison sampled 34,428 channels. Mean channel difference was 0.69 of 255, with a maximum of 55.46 at a color boundary. Full-range 4:2:0 retains full luminance resolution but changes chroma sampling. Generated desktop edges and distinct light/dark window regions are checked through the actual new buffer format, encoder and PNG extraction.

For one unchanged 512-KiB image, the previous byte accounting stopped after 512 timestamps, or 128 seconds at four per second. The corrected history accepts 2400 timestamps, reaching its existing ten-minute count limit, while retaining one image allocation.

Before this follow-up, 1000 ordinary unposted drag events took 0.003 ms. Generated 60/120-Hz selector event-to-layer medians were 0.070/0.060 ms. These already-fast paths were retained. They do not prove displayed pointer latency.

## Verification

The image and frame-history failure checks were written and run before their fixes. The first failed because unsupported native Paste dropped the images. After fixing paste, the second failed because shared idle images exhausted the memory budget. Both then passed. Additional checks cover native-only paste, a destination change before keyboard fallback, ambiguous native delivery, immutable reused capture buffers and odd-size pointer scaling.

The package check runs domain tests, packages the canonical app, then verifies Prompt, generated resource and completion workloads, selector scheduling, Bottom geometry, glow, hold-Escape onboarding and BuildIdentity. It retains the executable hash before and after those checks. Logs, before-source copies and the alternating-format comparison are in build/prompt-resource-fix.

Live screen capture, displayed dragging smoothness and attachment acceptance in the user's browser remain unverified. The current app process is preserved. Reopening the canonical app is required to load the new code.

## Verified package

Canonical build/S2T.app is S2T 1.0.1 Build 745, built 2026-09-21T16:13:14Z. Executable SHA-256 is 759ac3abb5379f3cb3bbe0a753366e55bdb19ca001feb0cf132ca0e6234187ac. The verifier held the package lock and confirmed the executable hash stayed unchanged through all packaged checks.

All 430 domain/service tests passed. The first full run passed; a later repeat stalled in XCTest and was stopped. A clean rerun passed all 430 in 9.53 seconds. No product code was changed for that test-runner stall. The packaged Prompt, Bottom movement, glow, onboarding, BuildIdentity, generated resource, completion and selection checks all passed.

Build 745 retained zero screen-bottom fallbacks and zero backing-size changes in the 120-read movement workload. Its two-display encoding median was 7.190 ms, compared with 8.404 ms in the earlier packaged baseline, but the alternating-format measurements above are a better guide to CPU variation. Selector event-to-layer medians were 0.074 ms at 60 Hz and 0.063 ms at 120 Hz. The native selector window covered 22,118,400 pixels; its border-layer bounds covered 0.60% of that area and its background alpha was zero. This is geometry and layer-state evidence, not a GPU timing measurement.
