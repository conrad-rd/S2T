# Filter updates reaching the renderer

S2T 1.0.1, build 28, built 2026-09-12T22:15:20Z. All 62 service/domain tests, packaged build identity and both-display glow checks passed. The packaged app was restarted normally and confirmed to have finished launching.

The user reported no visible blur in build 25 despite passing layer-state checks. A generated-line rendering test reproduced a specific failure in the filter update path. After Core Animation submitted the initial zero-radius filter, mutating the CAFilter parameters did not invalidate its cached render value. Assigning that same filter object again also failed. Its in-memory radius changed, which explains why the earlier checks passed.

ProgressiveBackdropView now retains Glur's mutable parameter object and publishes a fresh CAFilter copy after each update. The sampler, window context, waveform, colors, radius map and visibility animations are retained. This change does not toggle WindowServer hosting or introduce a material layer.

FilterSubmissionProbe uses only a generated four-pixel black line on a white background and an offscreen Metal texture. It submits the production adapter's filters to CARenderer, changes the meter from 0 to 0.3 to 0.55 and back to 0, and verifies both rendered output and that previously submitted filters remain immutable. It does not create a window or read screen pixels.

With the filter-copy line absent, generated-line luminance at the lower sample remained [0, 0, 0, 0]. With the fix, it became [0, 239, 244, 0]. The line above the glow remained sharp. This catches a renderer failure that inspecting filter properties alone cannot catch. The test is part of --verify-glow.

The native comparison also found different backdrop group names and namespaces between S2T and NSVisualEffectView. Those settings were not changed because the comparison did not establish them as the cause. The filter submission failure was reproduced independently.

Evidence is in build/verification/glow-filter-submission-baseline.log and glow-filter-submission-fixed.log. Packaging and full checks are recorded in glow-filter-package.log, glow-filter-tests.log, glow-filter-identity.log and glow-filter-packaged-check.log.

This verifies rendered filter updates on generated content. Visible cross-app appearance over Helium and video playback performance remain unverified. No screenshots, recordings, screen readback, visible diagnostic windows, or Raycast interaction were used.
