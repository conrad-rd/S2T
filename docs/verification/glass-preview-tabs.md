# Floating preview tabs

Glow, Edge and Speech now float together inside the preview, centered 12 points above its bottom edge. The bar is 286 by 42 points. Each tab has a matching SF Symbol and a native button. Only the selected tab has a button backing; the other labels remain on the shared glass.

On macOS 26 and newer, NSGlassEffectView owns the button content, using regular glass and a 21-point corner radius. Older systems use the native within-window HUD material. Material and accessibility adaptations belong to AppKit. This follows [Apple's native glass composition guidance](https://developer.apple.com/videos/play/wwdc2025/310/), using contentView rather than placing button content beside the glass view.

The former bar below the preview is removed. Existing settings remain below the preview, and the bar follows the existing preview bounds. Bezel retains its renderer and does not show these tabs. Models and API keys keep the bar hidden through settings refreshes.

Verification uses never-shown authored AppKit views and the packaged application. Geometry checks require the complete bar to fit inside the preview, retain the bottom inset, and leave all three icon buttons accessible to hit testing. Existing tab checks exercise real button actions, exclusive selection and settings visibility. No display pixels, microphone, real clipboard, credentials or user fields are read.

## Result

Verified S2T 1.0.1, Build 235, in the canonical build/S2T.app. The package was built with scripts/build-app.sh from a stable copy of the latest shared sources, then copied back with an atomic executable replacement under the package lock. This preserved concurrent settings and glow changes while avoiding source-file changes during compilation.

All 206 service/domain tests passed. Packaged appearance-window, models-window, api-keys, menu-highlights, bezel and build checks passed. The actual mounted preview measured 528 by 245.5 points, and the complete glass bar stayed centered within it with the required 12-point bottom inset. Button actions, icon presence, hit targets and exclusive selection passed. A small native NSButtonCell layout override centers each icon-label pair with a six-point gap, including borderless tabs.

The first stable source copy lacked historical test references and contained an unfinished concurrent color-cycle revision. Refreshing it from the latest shared source and including docs/references resolved those test failures. The final tests above ran against the same source copy as Build 235.

The app was restarted without activation. Logs are in build/glass-tabs-*.log, with authored layout renders in build/glass-tabs-final-fixtures. These renders check authored layout, not WindowServer glass pixels on the desktop. The older-macOS material fallback was compiled but not run on an older OS.
