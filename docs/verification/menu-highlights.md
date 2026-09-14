# Exclusive menu highlights

S2T 1.0.1, build 7 fixes the multiple blue rows shown in the user's screenshot. Each custom row previously held an independent hover flag. Missing a mouseExited event left the old row highlighted while a new row set its own flag.

The regression check reproduced Start dictation and Close menu highlighted together before the fix. Entering a row now clears every sibling's hover first. NSMenuDelegate willHighlight synchronizes native and keyboard selection, including submenu headers and separators. Disabled rows, menu open/close, and detached views clear stale hover. A delayed exit from an older row does not clear the current row. Saved option checkmarks and action handling remain unchanged; clicks still do not explicitly dismiss the menu.

The packaged --verify-menu-highlights command passes missed/stale exit sequences, native and keyboard selection, disabled and reenabled rows, 100 rapid transitions, close/reopen, and a synthetic action retaining its saved checkmark. It constructs the real menu and sends local synthetic events to its views. It opens no menu, moves no pointer, invokes no real dictation/quit action, and captures no screen content. All 42 existing service/domain tests pass. --verify-build confirms the compiled version, packaged metadata, and menu version label agree.

Baseline evidence: build/verification/menu-highlight-baseline.log. Fixed debug evidence: build/verification/menu-highlight-fixed.log. Packaged checks were rerun against build/S2T.app before restart.
