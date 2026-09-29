# Menu bar visibility

AppKit persists visibility for unnamed status items under an automatically chosen name. Hiding a verification item can therefore hide the real app after restart when they share a bundle identifier.

`MenuBarStatusItem` assigns separate stable names to application and verification items before changing visibility. Application launch restores the visible item, and reopening the menu explicitly restores visibility too.

Run `python3 -m unittest discover -s Tests/AppKit -v` on macOS with AppKit services available. The fixture compiles the production status-item factory into a temporary app with a unique preferences domain. Separate processes save the old unnamed hidden state, launch the real item, hide a preview, and launch the real item again. It uses no S2T history, credentials, microphone, providers, or screen capture, and removes its preference domain afterward.

The pre-fix constructor failed the launch check with `Real app inherited the verification item's hidden state`. The named-item implementation passes all phases. The real packaged app must also be relaunched and its menu bar item checked after a visibility repair.

On 2026-09-27, the isolated restart regression passed, and universal build 909 passed `--verify-build`, `--verify-menu-highlights`, and `--verify-recent-recordings`. The running app was quit normally and relaunched from `build/S2T.app`. After the recent-recordings check, macOS persisted `S2T.MenuBar` as visible and `S2T.Verification` as hidden; the legacy unnamed item remained hidden without affecting the new identity. Direct visual confirmation was unavailable because native UI automation repeatedly timed out while selecting S2T. Evidence is in `.audit/menubar-regression-2026-09-27/`.
