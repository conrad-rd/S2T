# Attached input bars

Enabled app/site presets now retain a main field and compact attached header/footer bars as one `InputContour`. The union of their paths removes the interior join and keeps the narrower bar's stepped boundary. The main corner radius remains independent of the added height. T3 Code uses a 20-point main radius at nominal scale, based on the supplied reference.

The preset checks up to three nearby ancestor groups for adjoining controls, including bars that overlap behind the main field. It rejects detached controls, other editors, incomplete groups and document landmarks. Bars retain their own width and exposed corner radius. Source rectangles are checked again before presentation. Switching focus, removing a bar, disabling a preset or returning to a plain input discards the old contour. Terminal and Claude Code keep the existing cursor-row target.

The same contour reaches the immediate vector edge, completed color field, native blur mask, palette cycle and processing trails. Panel coordinates remain fractional and the input interior stays clear. Other apps retain automatic detection.

`bash scripts/test.sh` passed 225 domain/service tests. New cases cover inset footers across all composer presets at 75–200 percent scale, attached headers, overlapping bars, direct-editor presets, detached bars, unrelated editors, incomplete children and outlying controls.

`--verify-input-contour` checks the production reader with injected Accessibility objects, including moved and removed bars and disabled presets. Generated paths and native maps verify a single closed boundary, no internal seam, clear interiors and glow beside the inset footer. Hidden production panels verify coordinates and replacing the compound input with a plain one. Generated dark/light and processing fixtures live under `build/input-contour-fixtures` when exported with `S2T_GENERATED_GLOW_FIXTURE_DIR`.

These checks use no screen capture and do not prove every live app exposes its complete border through Accessibility. A read-only foreground check found Finder without an eligible input; it did not establish live T3 compatibility.

Version 1.0.1, Build 311 is packaged at the canonical `build/S2T.app`. All 225 service/domain tests passed. The packaged input-contour, input-outline, input-latency, appearance-performance and build-identity checks passed. Gradient-cycle and glow-clarity passed in Build 310 before the final allocation cleanup. Generated dark and processing fixtures were inspected; their glow follows the footer and has no internal divider.

The final same-workload startup check measured 0.49–6.99 ms for initial edges, with no presentation fade. Full field preparation remains asynchronous: 77 ms for the rounded web fixture, 365 ms for the native continuous fixture and 80 ms for the capsule. Removing temporary geometry arrays reduced the five-slider Around Input completion from 1460 to 980 ms in these runs; this is a background-render measurement, not key-to-display latency. Native continuous preparation did not improve in the smaller fixture. No visual or timing claim is based on screen capture.

## T3 browser regression

The user's next screenshot still showed a rectangle. Live inspection found T3 running in Helium at a localhost origin, which the native-only preset never recognized. Its actual hierarchy also has four extra wrappers between the main field and shared shell. The footer itself sits inside a full-width wrapper. The original synthetic fixture represented none of those differences.

`Tests/Fixtures/Composers/t3-browser.json` records only the real layout's roles, geometry, hierarchy and two fixed composer class markers. The regression failed before the fix: it returned the 691 by 130 main box without the footer. The production reader also exposed incomplete equal-size wrappers on the editor path, which caused preset resolution to fall back to automatic detection.

Browser recognition now uses the two static T3 composer markers exposed through Accessibility. It does not depend on a hostname or port, fetch pages, execute browser JavaScript, read window titles or inspect field contents. Desktop matching remains supported. The reader samples transparent editor ancestors while skipping the editor content itself, reaches the enclosing shell across bounded wrappers, and selects the narrower accessory container. Site origins and identity markers are rechecked before display.

A capture-free inspection of the real T3 tab selected its existing editor object for the diagnostic without activating the browser or changing focus. The production reader returned main bounds 691 by 130 with a footer offset 19,130, sized 652 by 28. The combined bounds are 691 by 158. Main radius is 19.9375, based on the installed T3 source's 22-pixel radius and 32-pixel primary control. The live geometry read took 6.95 ms. This measures metadata lookup, not physical key-to-display time.

`--verify-input-browser Tests/Fixtures/Composers/t3-browser.json` checks that recorded hierarchy through Helium, Chrome, Safari and desktop routes at three scales. It also checks disabled presets, unrelated localhost pages, removed markers and changing ports. Browser/desktop combinations beyond the live Helium inspection use injected objects.

Build 314, version 1.0.1, passed 226 service/domain tests and the packaged input-browser, input-contour, input-outline, input-latency and build-identity checks. First-frame edge rendering measured 0.37–5.48 ms in the generated latency fixtures. Packaging retried after concurrent TextInsertion edits and preserved those changes. The canonical app is `build/S2T.app`; a running older process needs to quit and reopen to load this build.

## Codex extended header

Live Codex initially exposed only its native wrappers, then exposed the web editor on a subsequent read. Once available, S2T outlined the 736 by 98 main field but omitted its adjoining header. The header shares a 1508-point-wide layout shell with the main field, beyond the previous 1.2-times-body-width search limit.

The reader now accepts compact enclosing shells up to the active window's width, while preserving the height, depth, node-count and document limits. Candidate attachment geometry and control checks still select the actual inset bar. The live reader returned combined bounds 670,1009,736,136, with the main field at local 0,38,736,98 and the exposed header at 13,0,710,38. No app activation, field-content reads or screen capture were used.

`Tests/Fixtures/Composers/codex-extended.json` retains only the relevant recorded roles and rectangles. The regression failed before the fix and passes through the production reader at three scales. It also checks moved and removed headers and disabled presets. `--verify-input-contour` checks the header's single closed boundary and clear native-blur interior, alongside the existing full-renderer attachment checks.

Version 1.0.1, Build 320 passed the recorded Codex reader and generated contour checks. All 231 service/domain tests passed. Input-outline and input-latency checks passed in Build 319 with identical production code. Build 320 corrected the new diagnostic's interior-distance assertion, since the native map treats zero distance as excluded interior at the join. The packaged live inspection confirmed the complete 736 by 136 target while Codex remained focused. These are geometry and generated-render checks, not a screenshot-based visual comparison.


## Attached-bar join correction, Build 340

The user confirmed Build 334's live rendering improvement, then reported gaps where T3's footer meets the main composer. Targeting had discarded the footer's overlap with the main rectangle. That leaves uncovered wedges where the rectangle's lower corners curve upward. Attachment rectangles now retain their measured overlap, while their radius still comes from the exposed height. The overall target bounds, main corner radius, and rendering mechanism remain unchanged. The recorded T3 footer retains its 15-point overlap and the Codex header retains its four-point overlap.

The regression test failed on the previous trimmed rectangle and passes with the complete attachment. The generated compound-contour probe checks both connected corner interiors against the color path and native blur mask. All 231 service/domain tests, recorded T3 and Codex targeting probes, input-outline checks and packaged build identity pass. The unchanged full-size four-second workload completes 198 default frames and 205 thin-edge frames, about 49.5 and 51.2 generated FPS, with maximum gaps of 21.3 and 20.2 ms. These checks do not capture the screen or establish live pixel-level appearance.
