# Compact Appearance window

S2T 1.0.1, Build 199 replaces the Appearance submenu with a native window action. The window is 432 points wide with 562 points of content height, reduced to 354 for Bezel. It opens only when selected. Native controls save immediately.

The window retains mode, theme, Bezel side, intensity, width, quiet amount and loud amount. It adds:

| Control | Range | Default | Effect |
| --- | --- | --- | --- |
| Background blur | 0–200% | 100% | Multiplies the bounded native radius, independently of color. |
| Glow softness | 0–12 pt | 0 pt | Softens the diffuse color while retaining the crisp edge. |
| Falloff | 0.5–2 | 1 | Changes color and radius-map decay together. Higher fades faster. |
| Edge brightness | 0–200% | 100% | Changes the anchored edge without changing native blur. |

These controls share the existing glow settings across Bottom, Notch and Input. Width appears only for Bottom and Notch. Bezel retains its existing rendering and side choice. Defaults preserve the approved Brighter edge appearance. The longer falloff has a smooth terminal fade inside the reserved field, without resizing overlay panels.

The embedded preview draws an authored sample background. It reuses ChromaFrameRenderer, ChromaFrameCanvas and the production native progressive filter on that local image. It never samples desktop pixels, audio, focused fields or clipboard contents. Quiet, speaking and processing states are isolated from dictation. Processing uses the existing Bottom/Notch indicators and shared Input processing drawing. The preview owns one asynchronous frame renderer and cancels it directly in the window-close handler.

Verification passed:

- 197 service and domain tests, including tuning persistence, bounded values and terminal falloff.
- `--verify-appearance-window`: native menu dispatch, compact hidden layout, all eight sliders, four modes, side/theme persistence, phase isolation, native filter rendering, independent effects, accessibility and close cancellation. The close lifecycle is injected for the never-shown fixture window.
- `--verify-brighter-edge`, `--verify-appearance-sliders` and `--verify-appearance-performance`.
- `--verify-notch-fit`, `--verify-notch`, `--verify-input-outline`, `--verify-glow build/glow-verification` and `--verify-bezel`.
- `--verify-menu-highlights` and `--verify-build`.

During the packaged slider check, the largest measured native action took 5.277 ms. Final preview, performance, menu and identity checks were repeated after adding direct close cancellation. Generated preview images are in `build/appearance-window-fixtures`. Native rendering changed 62,029, 110,042 and 49,562 generated color channels for Bottom, Notch and Input when background blur was enabled. Source color fields remain identical when only background blur changes; the two native rasterizers can round final output channels by up to 2/255.

No screen capture or interactive visual inspection of another app was used. These checks verify authored previews and hidden interface geometry, not live cross-app pixel equivalence. Existing concurrent provider changes were preserved in the canonical app.
