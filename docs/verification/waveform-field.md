# Blur follows the glow

S2T 1.0.1, build 14, built 2026-09-12T21:04:32Z. The blur changes were packaged in build 13 and retained in build 14, which is the verified running package.

The user confirmed progressive blur during testing, but reported that it appeared as a broad bottom gradient, still lagged, and flickered at activation/deactivation. They requested blur proportional to the visible glow and animated entrance/exit.

The earlier radius map extended at least 32 points plus up to 48 extra points above the colored contour. Its falloff was independent of the color rendering. Both now consume one intensity image containing the speech contour, a 26-point feather, the vertical tonal falloff and horizontal fades. Clear parts of the image have zero blur radius. The lower, denser glow has the strongest blur. The distinct bottom light and processing line remain.

A first-submission check reproduced the rectangular flash in the old implementation: AppKit submitted sdrNormalize, gaussianBlur and colorSaturate before the deferred variableBlur replacement. The new view calls the native updateLayer implementation and installs the progressive filter synchronously in that same update. Tint layers are hidden in the same disabled-animation transaction. Recording and processing now retain one backdrop view. The window host no longer toggles off/on for filter updates.

The panel fades in over 180 ms and out over 220 ms. A restarted overlay invalidates an old hide completion. Reduce Motion skips the transition animation.

## Measurements and verification

The same optimized 180-frame mask workload at 1800 by 240 logical points measured 0.299 ms median / 0.363 ms p95 before, and 0.210 ms / 0.266 ms after. CGImage conversion changed from 0.009 ms / 0.026 ms to 0.007 ms / 0.012 ms. The shared 384 by 240 image replaces the old 384 by 480 radius input and removes repeated generation during layout. These are CPU measurements, not a claim of measured GPU or end-to-end latency improvement. Whole-device GPU readings were variable and did not establish a reliable before/after result.

An offscreen CARenderer experiment used generated stripes only. It confirmed the earlier variableBlur filter could process both black-alpha and white-alpha input maps across the width. It did not read any window or display pixels, and no image artifacts were saved. That experiment did not establish cross-app output.

All 49 service/domain tests passed. The packaged --verify-build check confirms matching compiled identity, bundle metadata and menu-label metadata. No menu opened.

The packaged --verify-glow checks pass on both displays. They cover the shared map's shape, lateral fades and clear outer region at meter levels 0.3 and 0.55, the first submitted filter, native registration, actual host configuration, appearance changes, idle/hide-show and layer replacement. The normal OverlayContent retains the same native backdrop and CAContext through recording, transcription, processing, completion and restart. An empty transparent 1-point panel verifies actual fade-in, fade-out, reversal and final hiding.

Verification now uses hidden windows and hidden fixture processes. The temporary visible diagnostic strips used earlier in this investigation are not part of the product and will not appear during future checks. No screenshots, screen recording, screen-pixel readback, or Raycast interaction occurred. No microphone or provider calls were used in verification. Live appearance and remaining playback lag have not been visually verified by the agent.

Logs: `build/verification/waveform-field-tests.log`, `waveform-field-glow.log`, `waveform-field-package.log`, `waveform-field-identity.log`, `playback-mask-baseline.log`, and `playback-mask-after.log`.
