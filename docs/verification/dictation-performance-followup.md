# Within Input rendering follow-up

September 18, 2026. The user reported lag again with Within Input active. A read-only sample confirmed that the running app was Build 598, which already contained the earlier radius-map optimization. A five-second stack sample and a bounded 55-second CPU observation caught idle time only. The sample reported an 883.9 MB physical footprint and a 1.5 GB peak. Neither the screenshot-tool stall nor a memory leak was established by those observations.

## Measured change

The generated production workload showed that color preparation remained expensive with the saved high-softness settings. A stack sample identified Core Image importing a `CGImage` into a Metal texture even though the image already owned the completed Metal expansion output.

`ChromaExpansion.filterImage` now exposes that existing RGBA8 texture to Core Image, with the original sRGB color interpretation and the matching vertical orientation. Other pixel formats retain the original image-import path. The Gaussian blur, output format, source resolution, image bounds, and Canvas composition remain unchanged. The function adds no texture cache or retained working set.

| 1900 by 1800 generated Within Input fixture | Before median | After median |
| --- | ---: | ---: |
| Expanded color and softness | 9.49 ms | 6.96 ms |
| Total color and native-map preparation | 14.45 ms | 11.81 ms |

All generated body, edge and native-map bytes matched the baseline at both 1000 by 700 and 1900 by 1800 points. These measurements are preparation timings, not displayed FPS or screenshot latency. Machine load affects the numbers.

## Complete composition measurement

`--benchmark-glow --dictation --composition` runs the production Canvas at 2x with generated inputs and forces its output pixels to materialize inside the timed interval. Creating `ImageRenderer.cgImage` alone is lazy and was insufficient to measure completed drawing. The early `composition-before.log` times omit that work and must not be used as completed-render timings.

The complete 1900 by 1800 bitmap workload measured 28.09 ms before direct texture reuse and 27.76 ms afterward. The composed pixel hashes matched. This workload includes outputting a full Retina bitmap, which normal on-screen drawing does not do, and excludes live WindowServer composition. It cannot establish the user's displayed FPS. The optimization improves image preparation; this measurement does not show a material improvement to Canvas composition itself.

A prototype that restricted Canvas drawing to the source images' occupied rows changed generated output pixels and was discarded. It is not included in the app. Its source and measurements remain under the build evidence directory.

## Verification

`ChromaFilterProbe` compares the direct-texture filter with an independent implementation of the original `CIImage(cgImage:)` route. It covers asymmetric translucent color bands, fractional dimensions, shrinking and expanding images, an unchanged original-image fallback, and blur radii of 0.5, 4 and 12 points. It runs through `--verify-appearance-performance`.

Evidence is under `build/dictation-performance-followup`, with the idle process sample at `build/dictation-lag-followup-sample.txt`. All rendering fixtures are generated. No screen capture, microphone capture, field-content read, or provider request was used.

Canonical `build/S2T.app`, version 1.0.1 Build 600, passed `--verify-appearance-performance`, including both independent pixel comparisons, `--verify-within-input`, `--verify-glow`, and `--verify-build`. The packaged benchmark produced the final timings in the table and the original generated pixel hashes. The earlier development run measured 10.39 ms total preparation; the final packaged run measured 11.81 ms, illustrating timing variation. `bash scripts/test.sh` passed all 324 tests.

The running user app was left undisturbed. Quit and reopen the canonical app to load Build 600. Live screenshot latency and displayed frame rate remain unmeasured.
