# Appearance responsiveness

September 14, 2026. S2T 1.0.1, Build 186.

The appearance controls were already AppKit NSSliders. Generated glow fields and synchronous Metal completion waits ran on the main thread through Canvas and the native backdrop bridge. Changing Maximum amount above 200 percent also changed panel geometry, invalidating the field caches.

ChromaFrameRenderer now prepares color images and native blur maps together on a serial background queue. Each view has one render in flight and one replaceable pending request. Canvas receives prepared images; AppKit receives their matching map. Geometry changes reject obsolete frames. Cancellation, processing and Reduce Transparency prevent an old render from restoring a cleared sampler. The live overlay roots do not regenerate masks on the main thread during layout.

Palette columns and input color constants are reused during field generation. Repeated inside/outside calculations and sweep calculations beyond the input perimeter are skipped. The generated field hashes for Bottom, Notch and Input match the pre-change executable exactly. Generated Canvas comparisons also match exactly at whole-point fixture dimensions.

Menus combine pending refreshes, update slider labels only when changed, and avoid redundant minimum/maximum writes. The appearance callback holds its menu weakly.

## Measurements

The same generated 1800 × 1169 display and maximum values 200, 215, 230, 245 and 260 percent were used before and after. These checks use native slider actions, synthetic audio levels, generated images and hidden windows. They never capture the screen, use a microphone, or read real credentials.

| Appearance | Original synchronous field rebuild | Optimized field rebuild, now off the main thread | Maximum native slider action in the packaged app |
| --- | --- | --- | --- |
| Bottom | 148 to 166 ms | 79 to 107 ms | 0.452 ms |
| Around Notch | 198 to 251 ms | 126 to 160 ms | 0.385 ms |
| Around Input | 443 to 676 ms | 320 to 443 ms | 0.532 ms |

In the packaged burst test, the final new geometry was ready after 177, 276 and 820 ms respectively. This includes initial uncached work. Large preview resizes can therefore still take time to render, but do not block the controls or accumulate every intermediate slider value. A 5 ms main-run-loop timer had a maximum observed interval of 8.54 ms. These are controlled local measurements, not end-to-end physical mouse or display latency.

## Reproduction

```sh
bash scripts/test.sh
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --benchmark-appearance
build/S2T.app/Contents/MacOS/S2T --verify-appearance-performance
build/S2T.app/Contents/MacOS/S2T --verify-appearance-sliders
build/S2T.app/Contents/MacOS/S2T --verify-menu-highlights
build/S2T.app/Contents/MacOS/S2T --verify-glow build/slider-glow-fixtures
build/S2T.app/Contents/MacOS/S2T --verify-notch
build/S2T.app/Contents/MacOS/S2T --verify-input-outline
build/S2T.app/Contents/MacOS/S2T --verify-build
```

The performance check verifies final slider persistence, exact generated color and map comparisons, matching native filter gain, cancellation/restart and zero amount. Domain and service verification passed all 182 tests. Packaged checks and measurements are recorded under `build/slider-package-*.log`; the original field hashes and stalls are in `build/slider-baseline-*.log`.
