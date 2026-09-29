# Automatic input contours

All apps use ComposerTargeting for structural boundary selection. The detector considers connected controls, icons, transparent wrappers, scroll viewports and attached header/footer bars. Existing presets may refine corners when their measured contour agrees with the shared detector. No new app names, site selectors or text-content reads are used.

Missing focus triggers a bounded window-tree walk followed by app-scoped hit tests. Explicit focus outranks recent click geometry and dominant-field heuristics. Independent editable siblings stop container expansion. The reader rechecks the focused object, window and source bounds before accepting a target.

## Placement correction after Build 458

Build 458 incorrectly treated uncertain corner geometry as a reason to move a successfully detected field into a flat glow below it. Failed detection used another glow inside the app-window frame. The user rejected both behaviors. Passing fixture tests had validated that policy rather than the intended experience.

The recording path now keeps every valid field at its measured position with a rounded contour. Compact control rows infer circular ends without requiring padded AX text rectangles to fit the circle. Taller inputs keep corners based on content spacing or control size. Matching manual corner calibration remains active. Shape estimates no longer select a separate rendering position.

Only missing or unusable field geometry triggers fallback. After one retry, the reader returns no target and the existing Bottom appearance draws at the display edge. The recording path no longer reads a window as a replacement input or constructs a field-edge strip.

## Evidence

UniversalInputTests covers independent layouts, scales and negative display coordinates, compact search rows, standalone fields, ambiguous/incomplete parents, native text-line offsets and multiline growth. Recorded role/geometry fixtures cover other composers and their attachments without app identity.

The revised --verify-input-window checks service recovery and fallback, then exercises the complete AX-to-AppKit-to-registered-panel path on every connected display. It checks fractional field coordinates at the top, middle and bottom of each display, both short and tall fields, native/color contour agreement and unchanged corner radii. Panels are registered with zero alpha and remain click-through. No screen capture occurs.

--verify-input-outline also checks generated corner/blur fixtures and source geometry validation. --verify-input-browser checks recorded Codex and T3 contours, stale attachments and Chromium accessibility activation. --verify-input-search checks the recorded native address geometry through the shared detector. --inspect-focused-input now reports target kind, corner estimate, selected calibration and hidden rendered bounds, using only the current eligible app.

A read-only live check of the current Helium field returned AX bounds 727,981,691,158. Its converted and hidden rendered bounds both measured 727,30,691,158. This checks coordinate placement, not the website's painted corner radius.

Accessibility rectangles do not establish an exact visual border. Generic corner radii remain estimates, and these checks do not establish universal live compatibility.

## Packaged result

S2T 1.0.1, Build 459 passed 257 domain/service tests and all ten packaged input/build checks. The canonical build/S2T.app was restarted. Verification used injected Accessibility metadata, generated fixtures and invisible panels; it did not capture the screen or read live field text.
