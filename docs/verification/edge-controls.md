# Separate edge controls

Fine-tuning has an Edge group for Bottom, Around Notch and Around Input. It contains Blur, Glow, Brightness, Height and Opacity. Bezel's controls and renderer are unchanged.

Blur softens the rim from 0 to 12 points. Glow adds a wider colored halo from 0 to 200 percent. Brightness changes the rim's color intensity from 0 to 200 percent, while Opacity controls the visibility of the complete rim and halo from 0 to 100 percent. Height changes its outward thickness from 25 to 400 percent without moving the input/notch boundary. The defaults are 0-point blur, no additional halo, and 100-percent brightness, height and opacity.

The additional color filters run in the existing Canvas composition. Height resampling runs on the existing Chroma frame queue with Metal and retains the same geometry. The base glow pixels and native backdrop radius map do not depend on edge settings. The exterior clip keeps input and notch interiors clear, and opacity zero removes both the edge and its added halo.

GlowTuning decodes missing edge fields with defaults, preserving every existing saved appearance value. The domain checks include migration from the previous four-key JSON, independent round-trip persistence, range normalization and stable panel padding. Default rendering remains checked against the frozen Brighter edge reference images.

## Verification

Packaged S2T 1.0.1, Build 217, in the canonical build/S2T.app. The compiled identity, bundle version and native menu label agree.

- 201 service and domain tests passed, including preference migration and edge persistence.
- The packaged Appearance check passed all five native controls, rendered independence, brightness versus opacity, zero-opacity halo removal, increasing outward coverage, clear input/notch interiors and mounted preview updates. Generated layouts show the five edge rows together while the forest preview remains fixed.
- Five simulated edge-height slider actions with maximum edge blur and glow took at most 1.717 ms for Bottom, 1.556 ms for Notch and 3.227 ms for Input on the main thread. Each final value reached the mounted preview. This measures native action handling, not physical mouse latency or display frame rate.
- Frozen approved reference comparisons passed at default settings, with maximum Canvas color differences of 1.14 out of 255 or less and native-map differences of 1 out of 255 or less.
- Appearance performance, existing sliders, blur response, notch fitting and placement, input outline, Bezel, menu highlights, build identity and structural glow checks passed.

Verification used generated scenes, never-shown AppKit view trees and native layer checks. It did not capture the desktop, record the microphone or call providers. Cross-app visual blur was not measured.

Logs are in build/edge-controls-*.log. Authored layout renders are in build/edge-controls-fixtures/.
