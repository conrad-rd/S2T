# Cursor preservation

Verified on September 14, 2026 with the packaged S2T 1.0.1, Build 285.

The regression was written before the fix. The previous implementation inserted ` appended` at offset zero in `Grüße 👩🏽‍💻 existing text`, even though the cursor had moved to UTF-16 offset 27 after capturing the starting destination. See `build/cursor-baseline-check.log`.

The destination now keeps the latest valid selection from the original focused field. Tracking stops before restoration and on session cleanup. Delivery avoids redundant focus requests, waits after required activation or focus changes, restores the saved range, and checks that the field keeps it. Normal delivery preserves the current selection. Text still arrives through one native Accessibility Paste action, without Command-V or character events.

Checks passed against the canonical app:

- `bash scripts/test.sh`: 211 tests, zero failures.
- `--verify-paste-batch`: existing Unicode text survives caret restoration; ignored writes, delayed selection resets, lost focus and cancellation prevent unsafe delivery. Clipboard rollback and destination settings pass with an isolated pasteboard.
- `--verify-insertion build/verification/PasteEditor.app`: 35 passing checks through the actual native Paste action. Generated text and search fields cover moved cursors, restored destinations, deferred select-all after focus, intentional selection replacement, menu deferral, cancellation, processing failures and long Unicode/multiline output. The system clipboard remained unchanged.
- `--verify-build`: executable identity, bundle metadata and menu label agree.

The canonical app was restarted after verification. No screen pixels, real text fields, microphone input or provider credentials were used. These checks establish behavior in generated native editors, not every third-party editor. Earlier fixture runs stopped safely when another app took focus. The menu test now waits for delivery completion instead of assuming a fixed 200 ms delay.
