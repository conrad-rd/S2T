# General input boundary detection

S2T 1.0.1, build 48, September 13, 2026.

The production detector is shared by every app. It has no platform names, website selectors, presets, or saved layout measurements. `FocusedInputReader` reads a bounded Accessibility snapshot. `ComposerTargeting` resolves the input boundary from that snapshot, independently of the app or browser.

The resolver starts with the focused editor. If focus is on a containing widget, it accepts a single unambiguous editable descendant. It clips native text documents to their scroll viewport, follows transparent and frameless wrappers, and compares enclosing groups. Controls form a connected group based on their dimensions and distance from the editor. An outer group can replace an inner one when it adds connected controls. Unrelated inputs, document content, remote controls, incomplete snapshots, and empty outer padding do not justify expansion. Invisible helper inputs do not count as independent editors. Standalone inputs retain their own bounds or a modest enclosing border.

The adapter bounds ancestor depth, child counts, node counts, and elapsed time. It skips the editor's content descendants and never requests text values. A final focus check rejects stale results. System-wide focus is a fallback only when its owner matches the requested application. The existing Raycast exclusion remains in place.

The mechanism relies on the roles, parent/child relationships, and frames exposed by the [macOS Accessibility API](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes). Web editors expose textboxes and related control groups through [WAI-ARIA semantics](https://www.w3.org/TR/wai-aria-1.2/). These interfaces do not guarantee that every visual border is represented by an accessible container. Missing usable geometry therefore uses Bottom. This implementation does not claim exact visual segmentation of every possible application.

## Verification

- `bash scripts/test.sh`: 89 tests, zero failures.
- Structural cases include controls on either side and in footers, nested toolbars, overlapping control bounds, frameless wrappers, deep nesting, forms, scaled geometry, native scroll viewports, hidden helper inputs, independent fields, document containers, cycles, and incomplete snapshots.
- Recorded role/geometry fixtures are regression inputs for the same detector. They are not application-specific code paths.
- `--verify-input-outline`: packaged native adapter, focused containers, stale-focus rejection, bounded metadata reads, hidden passive windows, menu actions, display movement, phase reuse, and persistence passed.
- `--verify-menu-highlights` and `--verify-build` passed.
- The packaged live reader returned the current input container's bounds without reading text or capturing pixels.
- S2T confirmed a completed dictation, quit normally, and relaunched with the background launch option.

Logs are in `build/general-composer-tests.log`, `build/general-composer-build.log`, and `build/general-composer-verification.log`. No new screenshots, screen recordings, microphone capture, or provider calls were used. Live visual appearance across every application has not been established by these checks.
