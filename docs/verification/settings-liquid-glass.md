# Settings simplification

Verified September 20, 2026 against canonical `build/S2T.app`, version 1.0.1, build 677.

- Native glass actions and pickers, blue primary actions, and native disabled-state styling.
- Removed gray form cards and routine explanatory paragraphs. Warnings, consent and useful help remain available.
- Codex options, Codex executable and Jev controls are visible. Apple local models start expanded; local task choices are segmented.
- The comparison chart uses a regular switch. Writing AI starts open and has a regular switch to recover editor space.
- Existing model persistence, provider isolation, draft protection and key handling remain intact.

`bash scripts/test.sh` passed 398 tests. The packaged app passed `--verify-models-window`, `--verify-writing`, `--verify-local-models`, `--verify-api-keys`, `--verify-settings-sidebar`, `--verify-models`, `--verify-credits`, `--verify-jev`, `--verify-native-speech` and `--verify-build`. Code signing verification passed.

The checks exercised hidden native controls, actions, dimensions, keyboard editing, theme inheritance, model persistence, isolated file saves and mocked provider requests. Writing retains at least 400 points of document space with AI visible and at least 500 with it collapsed. Key rows fit at 420 and 600 points wide.

No screenshots, screen pixels, live provider inference or real credentials were used. This establishes structural and behavioral verification, not visual approval of the glass rendering.

Executable SHA-256: `bf368079155291a9b07e396b62e7a4a3aa0d6a1fe5a49b25030b1aba79bc73d8`.

## Follow-up, build 683

Version 1.0.1 build 683 adds 32-point native glass choices for Models and local tasks, with blue selection and left/right keyboard navigation. Model shortcuts remain visible after selection in Models and Writing. Local model Details and Repair actions are visible beside Install or Use. The API key storage caption moved to help text.

The service/domain suite passed 400 tests. All ten packaged checks listed above passed again, including native header bounds, complete labels, blue selection, arrow-key activation, persistent model shortcuts and visible local-model actions. Code signing verification passed. These remain hidden structural and behavioral checks, without screenshots, live inference or real credentials.

Executable SHA-256: `60cc89e3b038e1e2c67d79161b0cac380f2f9b729248b542b9bbece432613b9d`.

## Overall settings design, build 689

Version 1.0.1 build 689 replaces the fixed dark outlined sidebar tiles with an adaptive native glass rail and one blue glass selection. The rail retains its 88-point width, cached reflected background, accessible names and native keyboard navigation. Decorative selection controls do not intercept clicks or keyboard focus.

Models, API keys and Writing share the system window background and 22-point headings. Actions use native glass capsules, fields have softer corners, account groups use spacing instead of rules, and Writing documents sit inside an inset rounded editor. This preserves the later Models hierarchy, including neutral quick picks and the optional Advanced controls.

The service/domain suite passed 400 tests. All ten packaged checks listed above passed on build 689, and strict code signing verification passed. The sidebar probe checks native glass content ownership, light/dark inheritance, one 44-point blue selection, hover bounds, keyboard traversal and background cache reuse. An initial build failed the separate credits recovery probe; rebuilding with the latest billing source resolved it. No billing code was edited in this settings pass.

No screenshots, screen pixels, real credentials or live provider inference were used. These results establish structural and behavioral correctness, not visual approval of the rendering.

Executable SHA-256: `7e394c0fb92e9a7b964f31289e830995ee3d0588a244d96bcb3d25377f11b73f`.


## Safari-style native controls, build 779

Version 1.0.1 build 779 uses untinted native glass capsules for secondary settings actions and dropdowns. AppKit controls inherit the window appearance; secondary attributed titles leave foreground color to the system. SwiftUI uses the standard glass button style for secondary actions. Primary actions remain blue, with explicit white AppKit titles. Selection changes clear stale prominence, tint and title overrides. Existing 28/32-point dimensions, actions and keyboard behavior remain. Older systems use bordered/rounded native controls.

The service/domain suite passed 447 tests. The packaged app passed `--verify-models-window`, `--verify-local-models`, `--verify-api-keys`, `--verify-writing`, `--verify-settings-sidebar`, `--verify-meetings` and `--verify-build`. The model check covers light/dark/system theme inheritance, primary-to-secondary changes, native dropdowns, pressed capsule shape and title updates. Packaging passed strict code-signature verification.

The broader `--verify-appearance-window` check failed its wallpaper-continuity assertion. The wallpaper implementation and its assertion were not modified in this change; this run does not establish whether that failure predates the button changes. Appearance verification therefore remains incomplete. No screen capture, real credentials, live provider requests or restart of the running app were used. The passing checks establish structural and behavioral results, not visual parity with Safari.

Executable SHA-256: `7664d689dcf495bcff812ac8da25cbf5c9a707c04595eca04d699e88f2d13dfe`.


## Appearance icon groups, build 780

Version 1.0.1 build 780 replaces the two Appearance segmented controls with individual native NSButton accessory-bar toggles. Each group retains one NSGlassEffectView, its existing position and its 228/195-by-42-point bounds. AppKit draws hover, pressed and selected states. There is no custom button drawing, divider drawing, nested segmented control or glass effect on each button. Selection cannot be cleared by clicking the active button. Native focus and Space activation remain, with left/right arrows activating adjacent buttons. Disabled sections reject activation.

All 447 service/domain tests passed. Packaged `--verify-appearance-selection`, `--verify-settings-sidebar`, `--verify-models-window` and `--verify-build` passed. The Appearance check verifies actual NSButton cells and actions, one glass background per group, accessible labels, synthetic unposted arrow keys, exclusive selection, disabled activation, preview/live-setting isolation, page navigation and stable geometry across all 25 mode transitions. Packaging and strict signature verification passed.

These checks use hidden windows without screen capture, live microphone input or real credentials. The running app was preserved. Visual parity with Safari is not asserted. The broader wallpaper-continuity failure recorded for build 779 was not addressed by this control replacement.

Executable SHA-256: `b6053196cd91e817161f7cb983e5666c055c094008b778128c5ec8f02483dbb8`.

## Shared glass selection, build 919

September 27, 2026: inline choice bars now share a SwiftUI `GlassEffectContainer` with an interactive capsule and a stable `glassEffectID` for the selected option. Appearance mode, section, phase, theme and placement controls, Writing mode and review controls, local task choices and model comparison use the shared implementation. Existing native toolbar groups remain in place. Systems before macOS 26 use the standard segmented picker.

The previous inline `NSSegmentedControl` replacement did not produce the toolbar's glass selection. Live computer-use screenshots of build 918 showed the new glass capsule on both Appearance icon bars and the Speech/Cleanup text bar. Clicking changed the selection and content; dragging from Glow to Gradient selected the corresponding pane. Offscreen `cacheDisplay` renders omitted or distorted glass, so they were not accepted as visual evidence.

The live check also found missing accessibility children and missing keyboard focus. Build 919 forwards the hosting view's accessibility children and focuses selected buttons. After restarting the canonical app, the live accessibility tree exposed every option and its selected state. Clicking Bottom and pressing Right selected Around Notch, moved keyboard focus and updated the preview. Appearance was left open with Classic selected for visual review; the active dictation appearance was not applied or changed.

Build 919 passed packaging, strict code signing, `--verify-build` and the existing `--verify-appearance-selection` check covering all 25 mode transitions and preview/persisted-setting isolation. The earlier build 918 also passed the existing Writing behavior check. No new implementation-mirroring tests were added.

## Native tab control correction, build 921

The user rejected build 919: custom SwiftUI glass buttons were the wrong element, and assigning focus on every selection produced an unwanted blue ring. That implementation and its custom gestures, animation, focus state and accessibility forwarding have been removed.

The shared control is now an actual `NSSegmentedControl`. On macOS 27 it uses the public `NSSegmentedControl.Role.tabs` API, which supplies the system tab-selection presentation. The property is assigned through KVC so the existing macOS 26 SDK build remains supported; a diagnostic compiled with the macOS 27 SDK confirmed the resulting native role is `.tabs`. Older macOS versions keep a standard native segmented control. `focusRingType = .none` removes the unwanted blue border without assigning focus on clicks. AppKit owns rendering, selection, tracking and accessibility.

Build 921 passed packaging, strict signing, `--verify-build` and the existing 25-transition Appearance selection check. Live computer use confirmed both Appearance bars expose tab groups and labeled tabs, clicks select the corresponding preview, dragging from Bottom to Classic switches the preview, and clicks no longer produce a blue border. Screenshots show the native glass-backed control at rest; a held-interaction frame was not captured. Appearance was restored to Within Input and left open. The Use appearance action was not invoked.

## Toolbar tabs and hover, build 922

September 27, 2026: Appearance's Still / Speaking / Processing toolbar and Writing's Instructions / Dictionary toolbar now embed the shared native tab control. Each option bar adds a faint adaptive hover highlight for an unselected option; AppKit continues to own selection, glass rendering, tracking and accessibility. The separate Use appearance action is unchanged.

The packaged app passed the existing `--verify-settings-top-bar`, `--verify-writing`, `--verify-build` checks and strict signing verification. Live computer use confirmed native tab groups and named tabs in both toolbars, Processing and Still preview selection, and Instructions / Dictionary switching without a blue focus border. After the user moved the pointer normally, a live screenshot showed the hover highlight on Classic while Within Input remained selected. Automation's coordinate clicks did not reproduce normal hover, so they were not used as hover evidence. Hover was visually confirmed on the shared inline control, not separately on every caller. Appearance was left open on Within Input, Glow, Still preview. No appearance was applied and no document content was edited.
