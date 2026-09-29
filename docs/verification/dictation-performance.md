# Within Input dictation rendering performance

September 18, 2026. The user reported screenshot-tool lag during dictation with Within Input active. A read-only five-second sample of the running Build 581 caught idle time only. It reported a 1 GB physical footprint and a 2 GB peak. That sample does not establish the cause of the screenshot delay or identify a memory leak.

## Reproduced bottleneck

`--benchmark-glow --dictation --tuned` runs the production color expansion and native radius-map methods with a fixed fixture matching the relevant saved appearance controls. It uses 24 changing speech frames after four warm-up frames, at 1000 by 700 and 1900 by 1800 points. It never reads the screen, microphone, clipboard, focused field, or real credentials.

A stack sample of the generated workload identified CPU image resampling and linear-gradient shading in `ContourMask.transformed`. Within Input's map contains large transparent margins, and its illumination multiplier is uniformly one. The old code resampled the empty rows and shaded the constant gradient on every speech frame.

| Generated workload | Before median | After median |
| --- | ---: | ---: |
| 1000 by 700, native map | 4.03 ms | 1.33 ms |
| 1000 by 700, total field preparation | 7.10 ms | 4.09 ms |
| 1900 by 1800, native map | 22.40 ms | 4.50 ms |
| 1900 by 1800, total field preparation | 33.62 ms | 13.69 ms |

These are field-preparation timings, not displayed FPS or screenshot latency. The production renderer already runs this work off the main thread. Reducing it lowers competing rendering work, but cannot prove that the user's original screenshot delay is resolved. Timing varies with machine load. The large fixture is a stress workload, not a measurement of the user's focused field dimensions.

## Change

For uniformly zero or one illumination, the radius-map renderer scans the generated image's alpha channel to bound its nontransparent rows. It keeps four source pixels of transparent interpolation padding and an outward-rounded transformed clip. The original image, resolution, interpolation, contour exclusion, and full-size output remain intact. Unsupported image layouts use the original complete drawing area.

A solid destination-in fill replaces gradient shading in those cases. It preserves the original second application of the antialiased contour clip. Fractional constants and varying gradients retain the original complete drawing operation because the independent fixture detected different rounding when optimizing fractional coverage.

The change does not alter appearance settings, microphone capture, screenshot capture, frame scheduling, or the native blur filter. It adds no retained image cache. The live app's memory footprint has not been remeasured after restarting, and this work makes no claim of fixing the observed memory peak.

## Evidence

All four benchmark combinations, default and tuned at both dimensions, produced identical SHA-256 digests of eight changing frames' generated body, edge, and native-map bytes before and after the change.

`ContourMaskProbe` independently renders the original gradient operation and compares every output byte for transparent, opaque, fractional, and varying illumination. Fixtures include fractional image bounds, affine transforms, colored source pixels, large transparent margins, and antialiased input exclusion. The probe runs as part of `--verify-appearance-performance`.

Raw timings, the generated-workload stack sample, original source snapshots, build logs, and packaged checks are in `build/dictation-performance`. The read-only live idle sample is `build/dictation-lag-sample.txt`.

## Packaged result

Canonical `build/S2T.app`, version 1.0.1 Build 583, passed `--verify-appearance-performance`, including the independent byte comparisons, `--verify-within-input`, `--verify-input-outline`, `--verify-glow`, and `--verify-build`. The packaged tuned benchmark produced the final timings above and the same generated pixel hashes as the baseline. `bash scripts/test.sh` passed all 309 service and domain tests.

The initial input-outline run failed a fixed-delay speech-settling assertion. A subsequent run passed the rendering and lifecycle assertions but detected a foreground application change during the check. The final repeat passed every assertion without changes to that probe or production animation timing, as recorded in `input-outline-final-recheck.log`. The real user app was not restarted or activated by these checks. Quitting it and reopening the canonical app loads the new build.
