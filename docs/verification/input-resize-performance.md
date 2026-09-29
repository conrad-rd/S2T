# Input appearance resize performance

The September 21 report concerns both input appearances following a changing message bar, especially while processing. Verification uses generated input geometry, generated images and invisible native panels. It never reads field contents or screen pixels, touches the microphone or restarts the user's app.

## Baseline

`--verify-input-resize-performance` was written before the renderer changes. The workload uses a 736-point composer with an attached header, 24 processing samples, and 12 listening sizes through the actual padded `InputOutlineGeometry`.

The isolated release source is under `build/input-resize-evidence/baseline`. It contains the original input renderers plus the new diagnostic. Two unrelated compiler fixes were necessary while other work changed the shared source. They do not affect input rendering.

| Measured work | Baseline mean | Baseline maximum |
| --- | ---: | ---: |
| Processing color during resize | 53.46 ms | 71.88 ms |
| Processing native radius map | 6.24 ms | 50.64 ms |
| Within Input processing panel preparation | 18.46 ms | 27.58 ms |
| Outside Input processing panel preparation | 1.92 ms | 10.05 ms |
| Outside Input listening resize, after first frame | 15.56 ms | 17.48 ms |
| Within Input listening resize, after first frame | 110.29 ms | 120.01 ms |

Cold listening preparation was 737.99 ms outside and 94.66 ms within. These are generated frame preparation times, not physical input-to-display latency or captured display frame rates.

## Changes under verification

Within Input processing prepares color and the matching native map on a bounded background queue. It shares the existing latest-request renderer and publishes only geometry-matched frames. Panel movement no longer synchronously builds radius maps. Listening work cannot hold the processing queue.

The profiler identified per-pixel distance evaluation against the merged rounded boundary as the remaining processing resize bottleneck. Metal evaluates those same flattened boundary segments, retaining the CPU path when Metal is unavailable. Refraction, diffusion, custom colors, the subtle native blur and the clear message-bar interior keep their existing formulas.

Within Input listening fields use Metal for the existing scalar formulas at the same source resolution. Expansion computes the original bilinearly sampled vector field without allocating another complete 2x vector texture on every resize. Independent comparisons retain the CPU formulas and verify fractional coordinates, circular and continuous corners, capsules and multiple falloff settings.

Input geometry refreshes at 60 Hz with the existing single read in flight and latest pending refresh. Bottom keeps its existing refresh rate. Accessibility reads remain off the main thread and retain the existing focus and geometry revalidation.

## Verification

The new check compares accelerated generated assets against the CPU reference with a maximum premultiplied-channel error of 0.009. It also drives 120 changes at 60 requests per second through the processing controller, including position, width and height changes, checks the main-run-loop heartbeat, and verifies the final native map and nonactivating hidden panel.

Final packaged results are recorded in the delivery section below. Earlier measurements and rejected runs are retained to explain the regressions found during repetition.

## Initial release measurements

S2T 1.0.1, Build 709 passed the sustained test. The same release workload measured:

| Measured work | Updated mean | Updated maximum |
| --- | ---: | ---: |
| Processing color during resize | 7.03 ms | 31.24 ms |
| Processing native radius map | 3.50 ms | 6.08 ms |
| Within Input processing panel preparation | 2.46 ms | 18.87 ms |
| Outside Input processing panel preparation | 0.86 ms | 5.35 ms |
| Outside Input listening resize, after first frame | 14.76 ms | 20.96 ms |
| Within Input listening resize, after first frame | 4.01 ms | 4.19 ms |

The preparation rows include initial host/shader work. The separate warmed mounted-panel test produced 118 matching frames before the next resize in 120 position/width/height changes at 60 requests per second. Its maximum main-thread action was 0.91 ms. A five-millisecond main-loop heartbeat had a maximum interval of 7.40 ms. The panel stayed at zero opacity, retained its native host and final matching radius map, and did not change foreground focus.

Two scheduling corrections were necessary beyond faster field generation. A delayed SwiftUI geometry request must not supersede the controller's current bounds. A staged blocked-render fixture checks that exact ordering. During continuous resizing, each controller request already carries fresh animation time; separate timeline requests must not add redundant work ahead of the next geometry frame. Animation-only submissions wait until geometry has been stable for two 60-Hz intervals. Geometry updates remain immediate and continue animating the processing field.

The initial attempt to move work off the main thread alone failed the sustained test. Its result was rejected, despite lower UI-thread cost. The final result requires the GPU boundary calculation and both scheduling corrections. A separate run-loop experiment found that `RunLoop.main.perform` already woke promptly, so no wake-up workaround was added.

Within Input's repeated listening-frame preparation is approximately 27.5 times faster in this generated workload. Outside Input's frame-generation cost is broadly unchanged; it benefits from 60-Hz geometry sampling and authoritative request bounds. Processing color preparation is approximately 7.6 times faster, and continuous processing resizes meet the sub-millisecond main-thread action budget. None of these numbers establishes actual screen-presented FPS or universal cross-application Accessibility latency.

Evidence is in `build/input-resize-evidence/before.log`, `packaged-performance.log`, `processing-sample.txt`, and `verified-*.log`. The earlier failing intermediate measurements are retained alongside them. The service/domain suite passed 414 tests. The running user process was preserved; the updated canonical app takes effect after the user next reopens it.

The focused input suite now checks its native Appearance menu actions, persistence and actual preview picker directly. It no longer invokes the separate general settings-layout sweep, whose old five-row sidebar/logo expectations predate the Dashboard and Meetings work. That broader settings suite was not used as evidence for this fix. The full focused outline check still exercises target discovery, security exclusions, capture-free generated colors/maps, native hosting, display movement, resize, phase reuse and focus preservation. The Within Input settings fixture explicitly navigates to Appearance before checking its controls.

Build 709 additionally passed packaged Within Input, tracking, compound contour, prepared-startup, glow, clarity, identity and sustained input-latency checks. Outside Input's sustained generated workload completed 204 default and 215 thin-edge frames over four seconds. Height-changing compound input produced 118 matched frames over four seconds at 30 requests per second. These retain the prior full-padding workload and are separate from the new 60-Hz processing-resize test.

## Hidden animation regression

Repeating the sustained check exposed a lifecycle problem after the first successful run. An input controller created its hidden view with `GlowAnimationClock.running` initially true. Calling `hide()` before the first show returned without stopping it, because visibility was already false. Hidden processing frames could then compete with the active input on the shared processing queue.

A new assertion reproduced this before the lifecycle correction: `Hidden processing continued submitting animation frames`. The evidence is `hidden-before-fix.log`. Both input controllers now start with their clocks stopped. Their SwiftUI views submit animation requests only while the clock runs. Explicit hidden preparation still submits the requested complete frame. The mounted fixture explicitly enables the real animation clock at zero opacity, then disables it on exit, so the resize test continues to include the active timeline.

The hidden performance fixture also declares a bounded active-work interval to avoid idle-process scheduling. That alone did not fix the failure. The failing repeated runs with active-work scheduling remain in `confirmed-0-input-resize-performance.log` and `confirmed-1-input-resize-performance.log`; they must not be reported as successful results.

## Texture conversion regression

The final full input check exposed intermittent corrupted resized fields. `ChromaExpansion.texture` converted Float pixels to half precision using the same allocation with different row strides for input and output. The parallel Accelerate conversion could overwrite unread input. A standalone generated numeric test reproduced this, with 0 to 7,792 incorrect half values across 20 conversions of the same dimensions. Separate output storage eliminates the overlap.

The performance probe now uploads twelve synthetic 620 by 380 RGBA images through the production texture path and compares every uploaded half value with independent `Float16` premultiplication. The existing full resize check independently compares resized color, rim and native maps with fresh fields and checks native outward vectors. No screen pixels enter either test.

## Delivered build

The canonical `build/S2T.app` is S2T 1.0.1, Build 718, compiled at 2026-09-20T23:23:40Z. Its compiled identity, bundle metadata and menu label agree. Packaging and code-signature verification passed.

Both final performance repetitions passed, with the real processing animation clock enabled on an invisible mounted panel:

| Measurement | First run | Second run |
| --- | ---: | ---: |
| Within Input listening resize, warm mean | 6.34 ms | 5.29 ms |
| Outside Input listening resize, warm mean | 16.25 ms | 16.39 ms |
| Processing color generation, mean | 6.99 ms | 6.97 ms |
| Background processing frame, mean | 9.78 ms | 10.14 ms |
| Frames matched before the next 60-Hz resize | 114 / 120 | 120 / 120 |
| Maximum main-thread placement action | 3.81 ms | 2.13 ms |
| Maximum five-millisecond heartbeat interval | 8.27 ms | 11.49 ms |

Both runs also passed stale-geometry ordering, hidden-animation idleness, exact independent half-float texture comparisons, full-resolution field comparisons and final native-map/host/focus checks. These supersede the initial Build 709 performance results as delivery evidence. Within Input's warm preparation is about 17 to 21 times faster than the 110.29-ms baseline. Processing color generation is about 7.6 times faster. Outside Input's warm preparation cost remains about the same; its geometry sampling now runs at 60 Hz. No zero-cost claim is made.

The complete packaged input-latency suite passed twice after separating conversion storage. Resized circular and continuous color, rim and native maps match fresh fields; native vectors retain the exact compound boundary. The final package also passed Input Outline, Within Input, tracking, compound contours, prepared startup, Glow, clarity and build identity. Logs are `release-*.log`. Earlier Glow attempts ended because the foreground app changed during verification; the final run passed its focus-preservation assertion. The service/domain suite passed 414 tests with no failures.

No screen capture or real microphone/provider use occurred. Generated-frame preparation and hidden-window checks do not measure physical screen presentation or every receiving application's Accessibility latency. The existing user process was not restarted. Quit and reopen the canonical app to use the packaged fixes.
