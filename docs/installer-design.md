# Keyboard installer

This is the saved default installer design. To build a fresh app and DMG with it, run `bash scripts/package-beta.sh`. The output goes to `build/releases`. Each new DMG contains the newly built app and reuses this layout. Change the design only when explicitly requested.

`scripts/build-dmg.sh` builds the reusable Finder layout at 660 × 750 points using the supplied empty keyboard artwork. The supplied artwork is used directly, without the previous caption-cleanup patch.

The 72-point app icon is centered at 335, 472, over the empty keyboard key. The Applications shortcut is centered above it at 330, 164. Its custom native folder icon occupies 400 of 512 image units, making it about 22 percent smaller while keeping the app icon unchanged. A Finder alias to /Applications supports this per-file icon without changing the system folder. Finder uses manual icon placement and opens without its toolbar or sidebar.

The regular signed app icon is preserved, as requested after checking the custom keycap's signing limitations. There is no installer launcher or first-launch replacement. Dragging S2T to Applications copies the actual app.

The packaging script verifies the final read-only image's layout, Applications link, copied app signature, and build identity using a local copy under build. It does not open Finder or capture the screen. The image remains locally signed, without Developer ID signing or notarization.

Build with `S2T_UNIVERSAL=1 bash scripts/build-app.sh`, then pass `build/S2T.app` and a new output path to `bash scripts/build-dmg.sh`. `scripts/package-beta.sh` uses this same design.

Verification on September 14, 2026: an isolated Finder `duplicate` operation copied a keycap-decorated alias as an alias file, not an app directory. The copied alias still resolved to its original payload. This confirms that an alias does not provide ordinary drag-to-install behavior.

The universal build also required replacing ARM-only Swift Float16 vector packing in ChromaExpansion with Accelerate half-float conversion. All 65,536 byte-color/alpha combinations matched the prior GPU bytes on Apple silicon. The packaged glow-clarity check passed, as did 218 service/domain tests. Intel compilation passed; runtime rendering was checked on Apple silicon.

Background repair: retain Finder's `icvl` record alongside `vstl`, include the complete icon-view color and scroll defaults, and preserve the background alias's real volume metadata. Package both 1x and 2x image representations. The volume name includes the app version and build to separate its background alias from older mounted images. Verification remounts the finished image at a different local path and uses macOS alias resolution plus NSImage decoding to verify the actual background file and both image scales. These checks do not establish visual Finder rendering.

Finder uses dark filenames for custom picture backgrounds and exposes no supported white-label option. Do not claim white labels from metadata alone or modify system Finder preferences.

Keycap alignment uses the source artwork at 1320 by 1500 pixels. The slot spans approximately x=604 to 733 and y=879 to 1006. Its center is 334.25, 471.25 points, rounded to Finder placement 334,471. This corrects both horizontal and vertical offset.

Layout 4 enlarges the app icon from 76 to 78 points at the same measured center. Applications padding compensates by 76/78 so its visible folder size remains unchanged.

Layout 5 restores the 76-point app icon at 334,471 because the user explicitly wants the visible keycap border. Applications retains its original smaller appearance with a 400/512 custom-icon scale.

Layout 6 follows the user’s explicit rightward correction: move only the app center to 336,471. Preserve its 76-point size, visible keycap border, Applications placement and size, background and dark labels. Earlier source-based centering was not visually accepted.

Layout 7 widens the visible keycap border with a 72-point app icon at 335,472. This moves it one point left and down from Layout 6. Applications artwork scales by 76/72 to preserve its visible size at the existing position.
