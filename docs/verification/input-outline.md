# Around Input appearance

Verified S2T 1.0.1, build 45, on September 13, 2026.

Around Input follows the focused accessible text field during dictation and processing. A thin gradient outline responds to speech; a moving white highlight indicates processing. The window never takes focus or intercepts clicks. Reduce Motion stops movement, and Reduce Transparency removes the soft halo. Missing permission, unavailable geometry, secure fields, and unsupported focused objects use Bottom with an explanation in Appearance.

The reader requests roles, editability, enabled state, position, size, and parents. It never requests text values, selections, or child trees. Accessibility reads run on a separate actor with per-request timeouts and bounded parent traversal. Mode changes and hiding invalidate pending results. Returned geometry is checked against the current foreground process and connected displays. Electron's documented AXManualAccessibility hook exposes editors when needed.

Verification passed:

- `bash scripts/test.sh`: 76 tests, zero failures, including field eligibility, negative and vertically offset display coordinates, invalid geometry, and outline padding.
- `--verify-input-outline`: injected Accessibility responses, parent traversal, secure and non-input rejection, absence of text reads, Appearance actions and persistence, hidden click-through windows, display changes, resizing, and phase reuse.
- `--verify-menu-highlights`: existing hover and saved-checkmark behavior.
- `--verify-notch`: hidden window and placement regression checks on both connected displays.
- `--verify-glow build/verification`: existing Bottom backdrop, meter response, visibility transitions, Reduce Transparency, and native hosting on both displays.
- `--verify-build`: compiled identity, bundle metadata, and menu label agree.

Logs are in `build/input-outline-tests.log`, `build/input-outline-build.log`, and `build/input-outline-verification.log`.

The live foreground check found After Effects with Accessibility permission granted and no usable focused text field. No apps were activated for live testing. ChatGPT, WhatsApp, Discord, and T3 Code field boundaries and visible appearance remain unverified in their live interfaces. No screenshots, screen recordings, screen pixel reads, microphone capture, or live provider calls were used. Raycast was not inspected.

## Composer boundary correction, build 47

The supplied screenshot showed that build 45 outlined T3 Code's inner editable area and excluded the composer toolbar. Live Accessibility metadata in the Helium browser confirmed the editable field at `(2114, 836, 605, 64)` and the complete composer at `(2099, 821, 635, 130)`.

The reader now climbs to the nearest compact group with accessory controls outside the editor. It skips text descendants and inspects at most 32 accessory nodes across bounded child lists. Parent depth, message timeouts, and the overall traversal deadline remain bounded. Page-sized containers are rejected. Plain fields without a composer retain their own bounds.

The outline now follows the outside border with a half-point offset. Its line is thinner, its halo is softer, and processing uses one moving highlight instead of repeated dashes.

Build 47 passed all 78 tests, the packaged `--verify-input-outline`, `--verify-menu-highlights`, and `--verify-build` checks. The new regression fixture uses the observed T3 hierarchy and tests direct and nested footer controls, editor growth, page rejection, and plain-field fallback. The packaged live detector returned the correct `(2099, 821, 635, 130)` composer bounds. Logs are in `build/input-composer-tests.log`, `build/input-composer-build.log`, and `build/input-composer-verification.log`.

S2T reported a completed dictation before a normal quit and background relaunch. The relaunch used macOS's background launch option. Live visual appearance after the change has not been independently captured or verified. The other named chat apps remain unverified live.
