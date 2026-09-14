# Glur backdrop trial

S2T 1.0.1, build 16, built 2026-09-12T21:17:17Z.

The user rejected the prior rendering and asked to try https://github.com/joogps/Glur. Package.swift and Package.resolved pin revision ba4f05d3c9a608ec773b9305f2af6089390de68a. The app links GlurBackdrop, packages its resources and MIT license, and uses its GlurBackdropNSView with a custom waveform radius map. The normal .glur() modifier cannot sample other applications.

A separate hidden trial of upstream Glur found windowServerAware=false and allowsGroupBlending=true. S2T's ProgressiveBackdropView adapter sets windowServerAware=true and allowsGroupBlending=false, disables substitute-color sampling, maintains the layer through backing changes, and keeps the overlay's WindowServer host from flattening. Glur creates only its variableBlur filter. The former NSVisualEffectView material tree and its initial gaussianBlur filter are no longer created. This is a different implementation, not proof that the user's visible cross-app issue is resolved.

The listening Canvas drawing is restored exactly from build/verification/glow-before-lifecycle-fix.swift. The speech history, bottom edge, processing line and panel transitions remain. Color is no longer drawn from the radius bitmap. The bitmap still follows the speech contour, feather and lateral fades, instead of applying a full-width linear gradient. Radius reaches 36 in speech and zero in silence.

All 50 service/domain tests passed. The packaged --verify-glow check uses hidden panels and hidden independent fixtures on both displays. It verifies the filter and its mask, first-frame configuration, actual WindowServer hosting, idle, appearance/backing changes, hide/show and focus preservation. The normal OverlayContent now also receives changing meter values 0, 0.3 and 0.55 without recreating the root view. These checks confirm that actual timeline updates reach the blur and that busy phases clear it while retaining the same backdrop and CAContext. Panel fade reversal is checked separately with an empty transparent 1-point window.

No screen recording, screenshots, screen-pixel readback, microphone capture or live provider requests were used. No visible diagnostic strips or Raycast interaction. Visual appearance over Helium and playback performance remain unverified. There is no end-to-end performance claim.

Logs: build/verification/glur-tests.log, glur-package.log, glur-packaged-glow.log, glur-build-identity.log.
