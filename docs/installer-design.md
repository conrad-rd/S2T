# Keyboard installer

This is the saved default installer design. To build a fresh app and DMG with it, run `bash scripts/package-beta.sh`. The output goes to `build/releases`. Each new DMG contains the newly built app and reuses this layout. Change the design only when explicitly requested.

`scripts/build-dmg.sh` builds the reusable Finder layout at 660 × 750 points using the supplied empty keyboard artwork. Only the baked-in S2T.app caption is replaced by a small crop from `Resources/Installer/caption-cleanup.png`, because Finder supplies the filename.

The 72-point app icon is centered at 323, 472, over the empty keyboard key. The Applications shortcut is centered above it at 323, 154. Finder uses manual icon placement and opens without its toolbar or sidebar.

The regular signed app icon is preserved, as requested after checking the custom keycap's signing limitations. There is no installer launcher or first-launch replacement. Dragging S2T to Applications copies the actual app.

The packaging script verifies the final read-only image's layout, Applications link, copied app signature, and build identity using a local copy under build. It does not open Finder or capture the screen. The image remains locally signed, without Developer ID signing or notarization.

Build with `S2T_UNIVERSAL=1 bash scripts/build-app.sh`, then pass `build/S2T.app` and a new output path to `bash scripts/build-dmg.sh`. `scripts/package-beta.sh` uses this same design.

Verification on September 14, 2026: an isolated Finder `duplicate` operation copied a keycap-decorated alias as an alias file, not an app directory. The copied alias still resolved to its original payload. This confirms that an alias does not provide ordinary drag-to-install behavior.

The universal build also required replacing ARM-only Swift Float16 vector packing in ChromaExpansion with Accelerate half-float conversion. All 65,536 byte-color/alpha combinations matched the prior GPU bytes on Apple silicon. The packaged glow-clarity check passed, as did 218 service/domain tests. Intel compilation passed; runtime rendering was checked on Apple silicon.

Background repair: retain Finder's `icvl` record alongside `vstl`, include the complete icon-view color and scroll defaults, and preserve the background alias's real volume metadata. Package both 1x and 2x image representations. The volume is named Install S2T to separate it from previous S2T Finder settings. Verification remounts the finished image at a different local path and uses macOS alias resolution plus NSImage decoding to verify the actual background file and both image scales. These checks do not establish visual Finder rendering.
