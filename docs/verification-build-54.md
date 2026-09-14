# Build 54 verification

S2T 1.0.1, Build 54, compiled 2026-09-13T10:09:00Z.

The outline stopped above the composer footer because the accessibility reader classified a non-editable AXComboBox as an independent input. Live browser metadata showed that both real editable combo boxes and select buttons advertise selection attribute names and settable flags. Only the actual editable combo box returned itself as AXEditableAncestor. No text values or pixels were read.

The shared reader now requires AXEditable or a self-referencing AXEditableAncestor for combo-box editability. Native child text fields remain discoverable. Select controls contribute to the composer boundary; independently editable siblings still block expansion. No app-name rules or geometry adjustments were added to production detection.

A reader regression failed before the change and passed afterward. It covers select controls, independent editable combo boxes, growing text areas, stable corners, and forbidden text-value reads. A 26-node measured accessibility fixture preserves the reported composer hierarchy and explicitly marks its truncated parent incomplete. The selected bounds are x 2099, y 822, width 636, height 130. Previously the live reader returned x 2100, y 823, width 635, height 85. Correct container spacing produces an 18-point outline radius instead of 11.

Validation passed:

- bash scripts/test.sh, 101 tests with zero failures, including five measured accessibility fixtures.
- bash scripts/build-app.sh, signed packaged build.
- Packaged --verify-input-outline, including the new regression and hidden passive windows.
- Packaged --verify-menu-highlights.
- Packaged --verify-build, compiled identity, bundle metadata and menu label agree.

The idle previous process quit normally and the packaged app restarted in the background. Live focus had moved to an AXLink by the final read, so that read could not confirm the new target on the focused composer. Boundary and corner results after the fix are verified against recorded geometry and injected accessibility relationships. No visual or pixel-level match is claimed. No screen captures, text reads, app activation, or Raycast inspection were used.
