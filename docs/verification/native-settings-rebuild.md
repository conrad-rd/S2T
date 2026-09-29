# Native settings rebuild — September 24, 2026

Settings now uses a resizable AppKit window, a standard unified NSToolbar, native window titles, an NSSplitViewController and the restored custom inset Liquid Glass sidebar. Navigation has one destination value and keeps mounted editors alive. Page hosts do not impose intrinsic or maximum window sizes; ordinary content is anchored below the native toolbar through the window content layout guide. AppKit owns traffic-light placement, ordinary settings controls and toolbar overflow. The sidebar retains its original custom white selection and hover treatment.

The seven existing icon destinations, Dashboard logo, credit balance and Policies remain reachable. Home/Dashboard and Appearance content, diagrams, preview controls and live effects are preserved. Appearance artwork remains cached and continues under the sidebar.

Ordinary pages use native grouped forms, group boxes, secure fields, radio choices, dropdowns, switches, lists and document editors. API keys remain masked while editing and save on Return or leaving the field. Escape preserves an unapplied draft. Model IDs still require explicit submission. The Writing assistant keeps dictation, Return submission, review/apply and document conflict protection. Meetings retains recording options, speaker names, original transcripts and all export formats.

Verification uses hidden windows and synthetic state only. No screenshots, screen recording, live microphone capture, real credentials, clipboard content or real receiving fields are used. The running app is not restarted.

## Validation

Initial rebuild: **S2T 1.0.1 · Build 846**, compiled September 24, 2026 at 18:19:19 UTC. All 12 packaged checks passed: settings-top-bar (including 780×720 and 1040×860 resizing), settings-sidebar, models-window, api-keys, local-models, writing, meetings, dashboard, appearance-selection, menu-highlights, recording-startup and build.

- Packaged sidebar and unified toolbar actions, all destinations, keyboard traversal, native secure key fields, narrow layouts and resize/titlebar bounds.
- Models and Local model configuration, routing, unsupported choices, draft preservation and recording guards.
- Writing, Meetings, Dashboard, Appearance selection, menu metadata, synthetic recording-to-delivery and build identity.
- `bash scripts/test.sh` encounters a pre-existing compile failure: three tests in `DictionaryTests.swift` pass `insertionSelection`, which the current `DictionaryObservation` initializer does not accept. Neither that implementation nor those tests was changed.
- A temporary package under `build/.native-settings-checks` excludes only those three incompatible tests. The remaining **449 service/domain tests pass**. Original test files remain untouched.

Live provider authentication and physical microphone/keyboard delivery are not claimed by these checks. Credentials and permissions were not exercised against live services.

## Sidebar restoration

**S2T 1.0.1 · Build 848** restores the original eight-point inset, 88-point rail, 12-point continuous corners, single Liquid Glass surface, white selected tiles, subtle hover fills and 38×26-point logo artwork. The native toolbar, traffic-light placement, page controls and resizing remain. Hidden sidebar geometry/hover/keyboard/cache checks pass, alongside toolbar/resizing, Dashboard, Appearance selection, Models, synthetic recording delivery and build identity. No screen capture, saved verification logs or running-app restart.

## Continuous native titlebar

**S2T 1.0.1 · Build 849**, compiled September 24, 2026 at 19:30:44 UTC, hosts the custom rail in a regular split-view item and removes its tracking toolbar separator. AppKit now supplies one full-width native titlebar background instead of splitting it at the sidebar and adding another full-height glass material. The original inset rail remains full height, with its own single glass surface.

The packaged `--verify-settings-top-bar` check reads hidden native view geometry after navigation and at 780×720 and 1040×860. It confirms a single titlebar background extends from the left edge across the full window, no tracking divider remains, the rail keeps its eight-point inset and 88-point width, and ordinary pages stay below the toolbar. Packaged sidebar (including themes, keyboard and artwork cache), Dashboard, Appearance selection, synthetic recording-to-delivery and build-identity checks also pass. Verification is structural, not a pixel-level visual claim. No screen capture, live microphone, real credentials, saved logs or running-app restart.

## Sidebar divider correction

**S2T 1.0.1 · Build 850** removes the vertical split-view divider exposed by the regular split-view item. The native split view has zero divider thickness, a clear divider color and no divider drawing, preserving the inset rail and continuous titlebar. The packaged toolbar check now also verifies the sidebar and page meet with no gap after navigation and resizing. Packaged toolbar, sidebar, Dashboard, Appearance selection and build checks pass. Verification used hidden geometry only, without screen capture or restarting the running app.

## Horizontal line behind the sidebar

**S2T 1.0.1 · Build 853** restores the horizontal toolbar baseline using native NSBox separators. Their hairlines share the window content-layout boundary and meet without a gap at the sidebar edge. The sidebar portion is below the inset glass; the page portion is above page content. NSBox's two-point alignment margins are included in the native five-point frame around the one-point alignment rectangle. The window's overlaid baseline is disabled to avoid drawing across the glass face. Both portions are hidden on Home, and the vertical split divider remains absent.

Packaged toolbar checks verify endpoint continuity, horizontal alignment, sidebar stacking, no vertical divider, native toolbar actions and navigation at both window sizes. Sidebar, Dashboard, all 25 Appearance transitions and build identity also pass. These are hidden geometry and behavior checks, without pixel capture, live credentials or a running-app restart.

## Home traffic lights

**S2T 1.0.1 · Build 854** keeps the native unified toolbar attached on Home with no actions, a hidden title and a transparent background. Removing the toolbar previously switched AppKit to compact titlebar spacing, moving the traffic lights up and left against the rail edge. AppKit now retains the same native button geometry throughout navigation; no button frames are set manually. Home content and its hidden horizontal baseline are preserved.

The packaged toolbar check compares the actual close, minimize and zoom button frames after returning to Home from all six ordinary pages at 780×720 and 1040×860, and checks comfortable containment inside the inset glass rail. Toolbar, sidebar, Dashboard, Appearance selection and build checks pass. No screen capture, saved verification logs or running-app restart.

## Sidebar background during resizing

**S2T 1.0.1 · Build 855** synchronizes the cached sidebar wallpaper with native frame/bounds notifications from the actual Appearance preview viewport. The fixed-width rail could otherwise retain old preview geometry when the neighboring page resized. Geometry updates are immediate, disable implicit layer animations and skip unchanged frames. The original image cache and main-preview crop are preserved; observers are removed when replacing the viewport or destroying the backdrop.

The packaged sidebar check reproduces a preview-only width change without laying out the rail, then exercises seven grow/shrink sizes for every Appearance mode. It checks scale, horizontal centering, top alignment, complete rail coverage, no geometry animations and no image regeneration, without manually refreshing the backdrop. Resizing Home keeps the wallpaper cleared. Sidebar, toolbar (including horizontal baseline and Home traffic lights), Dashboard, Appearance selection and build checks pass. Hidden geometry and bundled-asset checks only; no screen capture, saved logs or running-app restart.

## Settings declutter

**S2T 1.0.1 · Build 856** moves rarely used options into sub-pages. Dictation keeps setup, microphone, shortcut and writing mode on its main page; Prompt mode, Clipboard history, Input detection and Advanced open from chevron rows. The Models overview keeps the quick model list, reasoning and key status, with Provider and model ID, Local models and Compare models as sub-pages. Sub-pages get a leading native Back toolbar item and their own window title. The API key placeholder no longer doubles as a row label.

Packaged checks pass: settings-top-bar (now also covering every Dictation and Models sub-page, leading Back placement, titles and return), settings-sidebar, models-window, local-models, api-keys, credits, models, writing, meetings, dashboard, appearance-selection, menu-highlights, recording-startup and build. Onboarding failed once under parallel load on the held-Escape timing step, then passed three consecutive reruns. Layout was reviewed with `--render-settings-pages`, which draws a never-shown preview-state window into PNGs; no screen capture, live credentials or running-app restart.

## Filled Appearance top bar

**S2T 1.0.1 · Build 857** gives the Appearance top bar the same opaque `windowBackgroundColor` fill as ordinary settings pages, using native borderless NSBox views. The fill spans the toolbar area beneath the native title/actions and continues behind the sidebar glass. The horizontal baseline remains above the fill and beneath the glass. Home keeps its transparent top area. The existing artwork and its resizing logic are preserved, including the newer input-preview placement work present during this build.

Packaged toolbar checks confirm fill coverage, adjoining edges and stacking in light/dark appearances at 780×720 and 1040×860, alongside native actions, Home traffic lights and the horizontal baseline. Dashboard, all 25 Appearance transitions and build identity also pass. Hidden geometry and behavior checks only; no screen capture or running-app restart.
