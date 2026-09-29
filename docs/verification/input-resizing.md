# Around Input resizing

The geometry poll previously ran every 200 ms. A growing search composer also inherited capsule corners from its enclosing search landmark, even after it became multiline. The new injected fixture reproduced that failure at the first 24-point height increase.

Geometry now refreshes every 33.3 ms, with at most one off-main-thread Accessibility read running. Permitted metadata is batched in production and reused only within one read. Focus, editor bounds and the selected container are read again before accepting a result. Search ancestry no longer overrides measured shape. Unchanged geometry skips native window layout.

The rendering benchmark found a separate bottleneck. In an isolated comparison executable with height reuse disabled, changing the full padded compound composer at 30 samples per second produced one completed matching frame over five seconds. It arrived only after the four-second resizing workload stopped. Each new height invalidated the expensive field generation before it could publish.

Compatible height changes now reuse one complete source set of color, rim, native blur and expansion-vector fields. A Metal pass preserves the top and bottom corners and any attached bars. It resizes only the straight middle sides. Width, corner radius/style and attachment changes still require fresh assets. The existing final contour clips the input interior. Keeping one source set avoids accumulating interpolation across repeated resizes and adds a bounded retained source set to the current rendered assets.

Verification uses injected Accessibility objects, generated images and hidden windows only. It does not read user text, sample microphones or capture the screen. Timings describe controlled work, not physical typing-to-display latency. Exact border radii still depend on geometry estimates because Accessibility does not expose every app's drawn corner radius.

Commands:

- `bash scripts/test.sh`
- `--verify-input-tracking`
- `--verify-input-latency`
- `--verify-input-outline`
- `--verify-input-contour`
- `--verify-input-browser Tests/Fixtures/Composers/codex-extended.json`
- `--verify-input-browser Tests/Fixtures/Composers/t3-browser.json`
- `--verify-brighter-edge`
- `--verify-menu-highlights`
- `--verify-build`

## Focused-window fallback

When the input cannot be identified, Around Input now outlines the focused window. It rechecks window identity, bounds and focus, follows moves and resizes, and returns to the input once it becomes available. It also uses this fallback when an exposed input fails the display-geometry checks. Secure fields remain excluded. Missing Accessibility access or a missing eligible window retains Bottom with an explanation.

Window fallback uses continuous 12-point corners, or square corners for an exposed fullscreen window. These are native-style estimates, not sampled pixels. Screen-flush edges move 3 points inward to leave a visible border. The panel clips its padding to the connected displays to avoid allocating full offscreen glow fields around a large window. `--verify-input-window` checks injected input loss/recovery, window movement, stale reads, unavailable/minimized/secure targets, large-window geometry and hidden native panel reuse.

Generated source images upload to Metal before they are published to asynchronous Canvas readers. This avoids concurrent mutation of AppKit image representations during geometry and phase changes.

## Packaged verification

S2T 1.0.1, Build 367, built 2026-09-15T18:18:23Z at the canonical `build/S2T.app` path.

- Domain and service suite: 241 tests passed.
- Injected geometry tracking: mean 13.12 ms, maximum 13.45 ms for five growth/shrink reads with a simulated 0.2 ms per metadata call.
- Growing full-size composer: 116 complete matching color/map frames during 4.00 seconds, maximum gap 67.71 ms. The same workload with height reuse disabled completed one frame over 5.00 seconds, maximum gap 4989.92 ms.
- Initial cold preparation in the resizing fixture remained 574.27 ms. This change speeds repeated compatible height updates; it does not remove initial asset preparation.
- Resampled circular/continuous corners, attached bars and native expansion vectors matched independently generated reference fields.
- Input-window, input-outline, contour, recorded Codex/T3 fixture, menu and build-identity checks passed without screen capture. Live typing across arbitrary applications was not visually verified.

Logs are under `build/input-resize-check/window-*.log`; the isolated comparison is in `comparison-baseline.log`.

Final delivery is S2T 1.0.1, Build 370, built 2026-09-15T18:24:36Z. It preserves the concurrent gradient and insertion changes. Under the shared package lock, the canonical app passed input-window, tracking, contour, native-menu and compiled-build checks. Final tracking mean was 13.08 ms, maximum 13.39 ms. The detailed rendering timings above were measured on Build 367 with the same resize implementation. See `delivered-checks.log`.

The final domain/service rerun passed all 241 tests. S2T was relaunched from the canonical app path without changing the foreground app, and its mapped executable was checked against the verified bundle.
