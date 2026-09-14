# Native root backdrop

S2T 1.0.1, build 25, built 2026-09-12T21:40:53Z.

The user reported that the Glur trial still showed no progressive blur. The preceding implementation put Glur's sampler several layers inside NSHostingView. Its WindowServer-aware flag was enabled, but the layer had no group name, and the window was configured during view attachment. Earlier checks did not require a native root or configuration before content attachment.

The new root-placement regression failed on that implementation. ProgressiveBackdropView now owns the window contentView and hosts the existing SwiftUI drawing above the Glur sampler. GlowBackdropBridge forwards the same 60 Hz profile and radius map from SwiftUI. The window is deferred and configured before layer-backed content is attached, and the root also disables automatic flattening. The sampler has a stable group name. No host off/on toggles are used.

The window/layer setup follows the native-root constraint discussed in https://gist.github.com/torarnv/8b915957196d1a88e6e2fa81c67be8cb. This is a rendering-configuration correction and an investigation of the reported failure, not pixel-level proof that cross-app blur is now visible.

The listening Canvas drawing, colors, waveform profile, radius map and panel fades are retained. Backing-layer replacement now restores both the sampler and the color host in order. Removing the SwiftUI bridge disables the native sampler, including the Reduce Transparency path. A test override exercises that path without changing the user's accessibility preferences.

All 60 service/domain tests passed. Packaged checks cover native root placement, early host configuration, the sampler's actual CAContext identity, stable layer attachment and ordering, first-frame filter, meter 0/0.3/0.55/1, both displays, phase changes, backing replacement, appearance, hide/show, fade reversal and the transparency path. Model-menu and build-identity checks are also included. The checks use hidden windows and independent hidden fixtures. No screen capture, screen-pixel readback, visible diagnostic strips, Raycast interaction, microphone capture or provider calls.

The actual appearance over Helium and video-playback performance remain unverified. The layer-state checks do not establish either result.

Logs are in build/verification/glow-root-baseline.log, glow-root-layer-order.log, glow-root-tests.log, glow-root-package.log, glow-root-packaged-check.log, glow-root-models.log and glow-root-identity.log.
