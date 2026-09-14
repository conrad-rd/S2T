# Build 60 verification

S2T 1.0.1, Build 60, compiled 2026-09-13T11:22:41Z.

Around Input now has a 24-point outward backdrop blur and a wider, faint gradient glow. The generated blur band follows the same capsule or continuous-corner path as the outline. Its interior is cleared, so text and controls inside the input remain sharp. The panel reserves room for the fade, remains nonactivating and click-through, and uses the existing native WindowServer-aware sampler. The input mask is cached until its geometry changes.

All appearance modes use a gentler spatial blur transfer, 0.6 times the square root of the original mask coverage. It lowers the maximum effective radius from 8 to 4.8 points and strengthens the faint outer blur while retaining a zero-blur boundary. Speech response and waveform colors are unchanged. The native color layer keeps the original map, while the blur filter receives a separate map. Reduce Transparency disables the sampler and outward halo.

Validation passed:

- bash scripts/test.sh, 104 tests with zero failures.
- bash scripts/build-app.sh, signed packaged app.
- Packaged --verify-build, compiled identity, bundle metadata and menu label match.
- Packaged --verify-input-outline, generated contour masks, clear input interiors, monotonic fades on all four sides, unchanged color maps, submitted image values, native WindowServer hosting on both displays, resizing, phase persistence and Reduce Transparency disable/restore.
- Packaged --verify-glow, generated offscreen filter rendering, native sampler and independent hidden fixture process on both displays, speech levels 0/0.3/0.55/1, phase persistence, fade reversal and transparency.
- Packaged --verify-notch, generated contour rendering, per-display geometry, hidden hosts and mode changes. The first run failed its final foreground-identity check after the foreground app changed. A repeat passed every check, including focus preservation.
- Packaged --verify-menu-highlights.

Logs are in build/outward-blur-verify-*.log. All image checks use generated masks or offscreen fixtures. No screen capture, screen pixel readback or Raycast inspection occurred. These checks establish rendering configuration and generated-map behavior, not a visual match against the user's apps.

The previous idle process quit normally. Build 60 restarted and reported Ready when you are.
