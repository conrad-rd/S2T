# Native behind-window backdrop

S2T 1.0.1, build 10, built 2026-09-12T20:40:47Z.

The user reported that text stayed sharp beneath the glow and supplied an image showing that failure. The previous checks established filter attachment and input-map progression, not visible blur over another app.

A metadata comparison against an ordinary active NSVisualEffectView found that the custom ProgressiveBackdropView was absent from NSWindow's registered backdrop views. Its layer also allowed group blending, unlike the native behind-window sampler. Both windows hosted layers in WindowServer. Merely enabling window hosting did not make their backdrop setups equivalent.

ProgressiveBackdropView now subclasses NSVisualEffectView with active state and behind-window blending. AppKit creates and registers the sampler. S2T replaces that sampler's material filters with variableBlur and hides the native material tint layers. Deferred updates follow AppKit's material creation and appearance changes. The existing radius map, 36-point maximum, speech response, color animation, and zero blur in silence remain unchanged. Unsupported variableBlur runtimes hide the effect view and retain the separate color animation.

AppKit's [NSVisualEffectView documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview) describes behind-window blending. Its normal layer lifecycle remains intact; S2T does not override updateLayer or drawRect.

## Evidence

- Added a registered-backdrop regression assertion before replacing the renderer. The old implementation failed it. Log: `build/verification/native-backdrop-baseline.log`.
- All 45 service/domain tests passed. Log: `build/verification/native-backdrop-tests.log`.
- `bash scripts/build-app.sh` packaged and signed build 10. Log: `build/verification/native-backdrop-package.log`.
- Packaged `--verify-build` confirms matching executable, bundle, and menu metadata without opening a menu. Log: `build/verification/native-backdrop-identity.log`.
- Packaged `--verify-glow` passed on the 2x and 1x displays. It checks native backdrop registration, actual WindowServer hosting, active behind-window mode, a single variable filter, hidden tint layers, no group blending, generated radius inputs, silence and 0.3/0.55/1.0 meter levels, light/dark changes, layer replacement, idle and hide/show persistence, and focus preservation. Log: `build/verification/native-backdrop-glow.log`.
- Quit the previous S2T process normally and opened the packaged app in the background.

No screenshots, screen recording, screen pixel readback, or Raycast interaction were used. The supplied user image was the visual failure report. These checks establish the corrected native rendering configuration; the live visual result still needs user confirmation. No microphone capture or provider calls were used by verification.
