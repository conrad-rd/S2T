# Input movement recovery

The follow-up report came from the current app, not a stale process. The running executable and canonical Build 742 executable had the same inode. The previous renderer-only performance checks did not exercise an input resizing during Accessibility discovery.

## Reproduction

`--verify-input-motion` injects metadata for a text area. Its size changes between discovery and the independent validation pass. Each simulated metadata request takes 0.2 ms. The test drives the production `FocusedInputService`, without reading a real field, opening a window or using the screen.

Before the fix, one resize took 94.32 ms, with 30 metadata calls and five geometry samples. The reader correctly rejected obsolete bounds, but its caller classified every rejected read as an unavailable Accessibility tree and waited 80 ms before retrying. This applies to both input modes and to processing.

## Changes

The reader identifies geometry changing during validation separately from missing data. The service immediately retries a moving rectangle once. It retains the existing 80-ms recovery interval for unavailable Accessibility trees. Validation uses a new batched metadata snapshot, separate from discovery, rather than repeating individual position, size, security and focus queries.

The service returns found, changing or unavailable. Both normal and pinned tracking ignore a still-changing sample and try again at the next refresh, rather than hiding the input panel or switching to Bottom. Neither path publishes unvalidated bounds. Both retain only the newest pending refresh while a read is running. Discovery, secure-field exclusions, window/focus checks, site checks and the one-reader limit remain intact.

## Evidence

The same debug regression recovered the resized rectangle in 8.55 ms with 28 metadata calls and four geometry samples. A rectangle that changed during both attempts finished in 6.99 ms with an explicit changing result and no stale target. These are injected-service timings, not physical screen latency or a measurement of every application's Accessibility implementation.

Evidence is under `build/input-motion-evidence`. `before.log` records the failing regression; `after.log` and `debug-input-motion.log` record recovery. The debug input tracking, window fallback, universal targeting, presets and full hidden outline checks passed. The required service/domain suite passed 430 tests. Final packaged results are recorded below after validation.

## Delivered build

The canonical app is S2T 1.0.1, Build 743, compiled at 2026-09-21T15:50:37Z. The bundle, compiled identity and menu label match, and the package signature check passed. The running user process was preserved.

Two packaged motion checks measured 7.64 and 7.43 ms for a resize during sampling, compared with the 94.32-ms pre-fix regression. Repeatedly changing geometry returned safely in 6.71 and 6.68 ms. Both retain the two-read limit and reject obsolete bounds. The packaged targeting, window fallback, universal detection, presets, full input outline, Within Input, sustained resize performance and input-latency checks all passed.

The existing processing fixture matched 112 of 120 geometry changes before the next 60-Hz request, with maximum main-thread placement work of 1.47 ms and a maximum five-millisecond heartbeat interval of 8.84 ms. Generated color and native map comparisons passed. This is a separate renderer check and must not be described as physical display frame rate. Logs are `packaged-*.log`.

Verification used injected metadata, generated frames and invisible native panels. No real fields, recordings, screen capture, clipboard contents or provider credentials were used.
