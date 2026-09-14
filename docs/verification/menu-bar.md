# Native menu bar app

Verified September 12, 2026.

Normal launch creates an NSStatusItem with native NSMenu hover submenus and no settings window. Keys, provider selection, writing and transcription modes, microphone selection and test, shortcuts, appearance and glow intensity, model IDs, recommendation feeds, and transcript copy are reachable from the menu.

API keys use a masked preview and embedded Paste and Save buttons. Save confirmation appears only after successful storage. Keychain reads mark existing saved keys accordingly. OpenRouter remains the default, and Cerebras is selectable in the same submenu. Preview tests use synthetic in-memory credentials.

Setting/action rows use embedded AppKit buttons so clicks leave menus open. Selected states and provider editors update in place. Manual outside click and Escape dismiss the menu. A completed transcript copies immediately; Command-V waits while a menu is open. Cancelling pending delivery prevents a delayed paste.

The updated Logo/S2T.icon compiles with actool into Assets.car and S2T.icns. The build copies the current black/white fill SVGs into the menu image asset before compilation. The normal status item is 32 points wide, reduced from 54, and the artwork is 24 points wide, reduced from 38.3. Its proportions follow the updated SVG. Recording uses red tint and processing uses accent tint. Shortcut capture temporarily shows a prompt beside the icon.

Verification:

- Packaged build and signing verification passed.
- All 42 service and domain tests passed.
- All 19 live paste cases passed, including selection replacement, processing error fallback, copying while waiting for menu dismissal, and cancelling a pending paste. Provider responses were simulated.
- The native hover test opened API keys and Text processing, clicked both providers without closing the menu, pasted a synthetic key, saved it, and verified the saved confirmation reset after replacement.
- Both light and dark appearance submenus were captured. Appearance selection kept the menu open, and the native slider changed the saved intensity.
- Every settings submenu was checked, including provider, writing-mode, and hold-to-talk actions. Packaged icon assets and absence of a settings window were verified.

Evidence is under build/verification: menu-bar-build.log, menu-bar-tests.log, menu-bar-live.log, menu-bar-paste.log, and menu-bar/*.png. Earlier hover automation attempts failed because programmatic status-button clicks did not reliably open the menu across the two displays. The passing test used native NSMenu popup tracking at the actual status button position and mouse hover.

The GUI probe intentionally closes its temporary menus when a check finishes. Normal app action buttons do not do this. Verification did not interact with Raycast or make live provider requests. Live probes restore their synthetic clipboard changes and preview preferences.
