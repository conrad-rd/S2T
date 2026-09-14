# Settings hierarchy

The root menu action is Settings with a gear symbol and Command-comma shortcut. Its stable internal identifier remains appearance, preserving existing menu dispatch and metadata checks.

The native sidebar has Appearance and Dictation group headers. Bottom, Notch, Input and Bezel remain appearance modes. Models sits under Dictation. Group headers cannot be selected.

Theme has its own row at the top of the main pane. The selected mode has a separate heading above the fixed forest preview. Glow, Edge and Speech tabs replace the combined Fine-tuning list, so only one related set of settings appears at a time. The five edge controls remain together. Native sliders retain saved values and the shared preview renderer. The 704 by 652 content-point window gives five rows room below the preview. A fallback notice appears when Around Input actually falls back to Bottom.

Verification uses the packaged app and never-shown authored AppKit layouts, without display capture. The existing checks cover sidebar navigation, saved sliders, theme, visible preview, independent edge controls, native progressive blur and preview cancellation. Models checks cover navigation and its existing isolated editor controls.

## Result

Verified the canonical S2T 1.0.1, Build 221, compiled September 14, 2026 at 13:02:58 UTC. This package includes the concurrent glow work and the completed Settings layout. Earlier packaging attempts collided with edits from other active tasks; the final packaged app was checked after those changes.

All 204 service/domain tests passed. Packaged appearance-window, models-window, menu-highlights, appearance-performance, bezel and build checks passed. The preview measured 500 by 232.5 points for every mode; all saved controls remained reachable and each tab displayed only its own settings. Native slider action times in the existing performance check stayed below 2.5 ms. These timings do not measure physical mouse latency or display frame rate.

The first window check failed its combined close/focus assertion. A repeat passed without changes to that behavior, followed by a passing check of the final package; the first failure was not isolated further. Verification did not capture screen pixels or use real microphone, clipboard, fields or providers. Generated authored layouts are in build/settings-hierarchy-final-fixtures. Logs are in build/settings-hierarchy-*.log.

The canonical app was restarted without activation after verification.
