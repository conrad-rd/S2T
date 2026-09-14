# Paste, clipboard, and Liquid Glass

2026-09-12

The last stored insertion failure was `noTarget`. A separate native test editor reproduced that exact failure before the change: regular insertion worked, but passing a missing initial target returned `noTarget` despite an editable field being selected.

S2T now resolves the active external field at completion. If S2T is active, it returns to the remembered external app, including after clicking Finish. It checks focus again before delivery. Verified Accessibility insertion remains available. Editors that ignore Accessibility writes receive their native Paste command, with marked Command-V events as the final fallback. Clipboard content is checked before native paste so a newly copied item is not inserted by mistake.

The completion code now always copies the finished output. The old copy toggle is replaced by an Always status. An isolated completion check ran the real AppState completion path with insertion disabled and confirmed the resulting clipboard text. It made no provider requests and restored the previous clipboard.

The packaged app passed these live tests in a disposable native editor:

- Native text editor selection replacement.
- Missing initial target recovery.
- Native search-field selection replacement.
- Native Paste after an Accessibility write acknowledged success without changing the text.
- Starting in S2T, remembering the prior app, returning to it, and inserting at its selection.

Each insertion read back the complete expected string, including the text before and after the selection. All five passed in one uninterrupted run after the user agreed to pause keyboard and mouse input. Earlier interrupted runs stopped if focus left the fixture. The final raw keyboard fallback was not separately exercised because the native Paste command succeeded.

Settings now use native SwiftUI glass and glassProminent button styles on macOS 26 and later. Earlier macOS versions retain bordered controls. Sliders and switches remain native. Removed the global tint that turned every glass button blue. Added native toolbar spacing and a small page title, and reduced descriptive text in General.

The packaged settings window passed live sidebar navigation for General, API keys, Models, and Appearance. Setting the native slider updated the real setting, and pressing the glass Preview button entered preview mode. WindowServer captures in `build/verification/liquid-glass-live` were inspected. These use the same window factory and ContentView as the installed app. Offscreen bitmap snapshots cannot render the glass correctly and are not used as visual evidence for this update.

`bash scripts/test.sh` passed all 36 service and domain tests. `bash scripts/build-app.sh` built and signed the app. No live provider requests or Raycast interactions were used for this change.
