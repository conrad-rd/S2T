# Progressive background blur

S2T 1.0.1, build 8. Built 2026-09-12T20:27:04Z.

The native variableBlur radius map now uses a smoothstep curve. The background stays clear above the outer contour, becomes progressively more blurred through the light region, and eases into its strongest blur in the lower body. Maximum radius remains 36 and drops to zero in silence. The layer stays fully opaque; the input map controls radius, not blur opacity. Color, speech response, bottom edge, and loading line are unchanged.

The map uses the actual view height and includes both endpoints. Previously it assumed a 240-point view. An independent generated-input check reproduced the sizing error in a 320-point view: at 160 points above a flat 60-point contour, the radius-map alpha was 13 instead of zero. It is now zero. The final adjacent alpha step at the bottom decreased from 2 to 1.

The backdrop sampling scale follows the display scale. The view explicitly uses Core Animation filters and reattaches and registers its backdrop if AppKit replaces its backing layer. The sampling-scale choice follows the original [VariableBlur implementation](https://github.com/nikstar/VariableBlur/blob/main/Sources/VariableBlur/VariableBlur.swift), which distinguishes backdrop sampling scale from contentsScale.

## Verification

- All 42 service and domain tests passed with `bash scripts/test.sh`.
- `bash scripts/build-app.sh` packaged and signed the app.
- Packaged `--verify-build` confirmed compiled identity, bundle metadata, and menu-label metadata agree. No menu was opened.
- Packaged `--verify-glow` passed on the 2x and 1x displays. It checks generated radius-map inputs at 0.3, 0.55, and 1.0 meter levels, monotonic progression, smooth endpoints, speech-shaped variation, and resized logical coordinates.
- The live structural checks cover silence, 0.3, 0.55, and 1.0, window hosting, disabled automatic flattening, display sampling scale, full-width layer attachment, layer replacement, idle persistence, hide/show, click-through behavior, and unchanged foreground focus. Each display uses an independent fixture process.

No screenshots, screen recording, screen pixel readback, or Raycast interaction occurred. These checks verify generated filter inputs and live configuration, not the visual cross-app output. Live microphone and provider checks were not needed or run for this blur change.

Logs are `build/verification/progressive-radius-glow.log`, `progressive-radius-identity.log`, and `progressive-radius-package.log`. Service-test results are in `build/verification/build-7-tests.log`.
