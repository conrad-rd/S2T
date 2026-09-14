# Softer spatial blur, September 14

Verified S2T 1.0.1 Build 221, compiled 2026-09-14T13:02:58Z, at the canonical build/S2T.app location.

The current app already contained the shared Around Input detector, capsule handling, gradient outline and outward backdrop. The newer Chroma renderer bypassed the earlier soft blur transfer, leaving the helper unused. A check against softened frozen reference maps failed before this change by 101/255 while the original color comparison passed.

Chroma radius assets now apply the bounded 0.6 square-root transfer during cached field generation. This reduces inner/outer blur contrast without changing color or edge assets, speech gain, saved controls, geometry, or Bezel. A smooth tail reaches zero at the existing field limit. The unused main-thread bitmap conversion helper was removed. Reference checks retain the frozen color comparisons and compare native radius maps against the softened reference coverage. A CGFloat-to-Double conversion in the concurrently updated edge probe was corrected to allow verification to compile.

Validation passed:

- bash scripts/test.sh, 204 tests, zero failures after concurrent source updates finished.
- scripts/build-app.sh packaging. Build 221 from the concurrent packaging work contains the final changes and preserves newer appearance work.
- --verify-build, compiled identity and canonical bundle metadata match.
- --verify-brighter-edge, actual generated Canvas colors and softened frozen reference maps for Bottom, Input and Notch.
- --verify-blur-response, generated native-filter lines, clear input interiors, stable panel geometry and slider response.
- --verify-input-outline, shared targeting, native maps, hidden windows, corner shapes, persistence and geometry. A combined run failed a preview-mode state check while another verification process was active. The isolated retry passed.
- --verify-glow and --verify-notch, hidden native sampler lifecycle and generated rendering.
- --verify-appearance-window, saved native controls, mounted authored preview and independent tuning.
- --verify-appearance-performance, bounded slider action time and matching native maps.
- --verify-menu-highlights.

Logs are build/soft-blur-*.log. Some early runs overlapped concurrent changes; the final results and isolated input retry above passed. No screenshots, desktop pixel reads, real field contents or Raycast inspection were used. These results do not establish a visual match in arbitrary third-party apps.

macOS did not trust the external Accessibility reader, so this turn did not force-quit an unverified active dictation. The concurrent update restarted the canonical app. Its normal process started after the verified bundle was packaged.

The canonical bundle advanced to Build 222 during concurrent packaging. Its compiled identity and softened frozen-reference checks also pass. The successful isolated input retry ran after that packaging completed. The normal process had already restarted with the blur fix before Build 222 was packaged.
