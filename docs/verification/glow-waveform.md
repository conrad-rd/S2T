# Listening wave verification

The listening effect now draws a defined translucent contour over masked NSVisualEffectView behind-window material. The material mask fades from the sharp background at the contour to stronger blur near the screen edge. This blends native blur progressively; it does not change an undocumented blur-radius property. The only color bloom is a narrow 2.2-point blur along the bottom. The bright edge stays 1.2 points tall.

The live meter still updates the effect at 60 Hz. Existing audio smoothing remains 4 ms attack and 55 ms release, without extra visual smoothing. The visual energy curve suppresses the lowest 6% of the meter and expands the remaining range. Idle brightness is 0.24 and full speech brightness is 1.0, versus 0.55 and 0.95 before. A 48-sample local history shapes spatial variations, while current energy controls overall height immediately so past speech cannot keep the wave expanded in silence. Height stays below 47 points. Reduce Motion freezes shape and gradient movement while retaining brightness feedback. Reduce Transparency omits the material.

## Checks

- Packaged app built and signed successfully.
- All 42 existing service and domain tests passed.
- Eight live WindowServer captures use an owned opaque grid/text fixture, covering quiet, speaking, loud, and loud without material on light/dark backgrounds. No external application is activated or inspected.
- Nonactivating and click-through panel behavior passed; the foreground process remained unchanged.
- At 10 points above the bottom, grid contrast fell from 32.58 to 13.21 color levels on light and 34.24 to 14.10 on dark when enabling the material. The color overlay was identical, confirming real backdrop softening.
- The loading-line function is unchanged. Six fixed-time loading previews retain the same shapes and motion positions. RGB differences are at most 2 out of 255, so the captures are visually equivalent rather than byte-identical.

## Timing

The same 60-frame 1440 by 240 ImageRenderer workload measured 0.03 ms median / 0.08 ms p95 before and 0.05 ms median / 0.08 ms p95 after the initial change. Profile and material-mask generation measured 0.17 ms median / 0.21 ms p95 separately in the final live probe. ImageRenderer does not render the native backdrop and these timings exclude GPU completion, WindowServer composition, and physical microphone-to-screen latency. This change increases visual response contrast; it does not claim a reduction in hardware latency.

Artifacts are in build/verification/glow-waveform-live and glow-waveform-static. No microphone recording, dictation paste, or live provider request was needed for this visual change.

## Taller overlay revision

Removed the upper contour stroke and its time-driven sine motion. The contour now uses 24 recent meter samples, mapped symmetrically with the newest speech at the center, so it expands with speech without rolling sideways. Typical speaking and loud profiles are about twice their previous height, with a maximum of 89 points. Quiet height remains 3 points. The upper tint is weaker and its boundary has only a 1.2-point softening.

The native blur mask now reaches full coverage across the lower part of the overlay instead of retaining a large sharp-background contribution. It still fades progressively at the top. Eight packaged live captures in build/verification/glow-taller-live confirm the stronger blur on light and dark text/grid fixtures. The panel remains nonactivating and click-through. The loading drawing function is unchanged. Mask/profile generation measured 0.14 ms median and 0.16 ms p95, excluding WindowServer composition.

## Full-width blur sizing

The material mask used a 384-point image inside views 1800 or 1920 points wide. The compact grid fixture did not reproduce the reported left-only blur, nor did full-width static fixtures reliably reproduce it. The sizing fix removes implicit image scaling: the NSImage and its bitmap representation now both declare the material view's actual logical size. A dedicated NSVisualEffectView updates the mask when its frame or backing properties change, including moves between Retina and external displays. The bitmap retains its small sampling resolution. Color drawing, contour shape, and loading animation are unchanged.

The expanded --verify-glow probe checks every connected display at full width, starting with a zero-sized panel like the normal overlay. It captures quiet, speech, loud, a material-free comparison, and an animated loud state in light and dark appearances. Final captures cover the 1800-point Retina display at 2x and 1920-point external display at 1x. Material and mask dimensions match on both. At 18 points above the bottom, left/center/right grid contrast falls to 0.0–1.3% of the material-free comparison, including animation. All 42 existing tests pass. The overlay remains nonactivating and click-through. Artifacts and measurements are in build/verification/glow-displays-after. This verifies full-width coverage in controlled fixtures, not the intermittent state the user originally saw.

## True progressive radius and feathered edge

The previous material mask changed the opacity of a fixed-radius blur. It did not vary blur radius and should not have been described as equivalent to progressive blur. This revision replaces NSVisualEffectView with an isolated WindowServer backdrop layer and its variableBlur filter. The radius map follows the existing speech contour. Radius starts at zero with zero slope at the contour and increases quadratically to 18 toward the bottom. Opacity remains independent of radius. The color contour is feathered by 4.5 points; the 1.2-point bright bottom edge and loading function are unchanged.

This uses undocumented CABackdropLayer and CAFilter runtime APIs. Class/selector/filter-key support is checked before installation. If unavailable, the color effect remains without a fixed-blur substitution. Future macOS changes may require renderer changes. It does not capture or save screen content during normal use and needs no screen-recording permission for its effect. Reduce Transparency skips the backdrop entirely. The alpha map represents blur radius, not material coverage.

The packaged --verify-glow check now uses independent nonactivating windows with sparse 3-point background lines, on both connected displays and in light/dark appearances. A wider line-spread measurement distinguishes progressive radius from a faded fixed blur. At 90, 65, 55, and 45 points above the bottom, measured line widths are 3, 3, 7, 14.5 points on the 2x Retina display and 3, 3, 7, 12 on the 1x external display. scripts/check-glow-progression.py passes on both. Live quiet, speaking, loud, animated, and color-only comparison captures remain full width. Foreground process and click-through behavior passed. All 42 existing service/domain tests pass. No microphone recording or live provider requests were needed.

Final artifacts are in build/verification/progressive-blur-independent-windows. Filter availability was confirmed on the installed macOS version. The captures verify real WindowServer output, not ImageRenderer approximations. GPU frame time and physical audio-to-display latency were not measured.

## S2T 1.0.1, build 2

The requested release is build/S2T.app, built at 2026-09-12T19:57:55Z. A new compiled BuildIdentity provides the version/build shown near the bottom of the native menu. scripts/build-app.sh increments the previous packaged build number and stamps both executable and bundle metadata. --verify-build confirms their agreement without opening a menu. Previously every release reported 1.0.0/build 1.

The visible contour had a hard Canvas clip around its blur. The color path now draws without that clip and has a 12-point feather. The blur-radius transition extends 40% beyond the color contour, with a minimum 12-point extension. Quiet blur radius is reduced independently so pauses remain subdued. The listening contour geometry, color palette, and loading function are otherwise unchanged.

Native full-width captures in build/verification/build-2-glow cover both displays, light and dark, and animated/static cases. The sparse-line progression check passes. At 90/65/55/45 points above the bottom, measured line widths are 4/13.5/21/27.5 points on Retina and 3/15/22/27 on the external display. The color-only capture now has a gradual tint transition extending 15 points farther above the previous visible onset. Reduce Transparency and Reduce Motion were both disabled in the user's system settings. All 42 service/domain tests pass. No live speech, provider, or paste checks were needed.

## S2T 1.0.1, build 3

Doubled maximum variable radius from 18 to 36. Increased the unclipped color feather from 12 to 26 points. Expanded the blur transition beyond the contour by at least 32 points or 80% of crest height, versus 12 points or 40% before. Lowered color-face opacity stops from 0.48/0.18/0.035 to 0.28/0.10/0.018 so the real blurred background remains visible. Silence now reduces radius to zero. The sharp bottom light and loading function remain unchanged.

Full-width native captures in build/verification/build-3-glow cover static and animated states on both displays, in light and dark. The progression script accepts explicit sample heights because the transition now occupies more vertical space. At 180/130/115/100 points above the bottom, line widths are 3/3/6.5/13.5 on Retina and 3/3/6/15 on the external display. Both progression checks pass, as do all 42 service/domain tests. Packaged metadata, compiled build identity, and the native menu label agree on S2T 1.0.1, build 3.

## S2T 1.0.1, build 5

Restored the visible color body while preserving the 26-point feather. Color opacity stops are now 0.95/0.50/0.12 before spatial blurring. The visual meter curve uses exponent 0.7 instead of 1.25, so low and moderate input drives a larger and brighter effect. The audio envelope and capture configuration are unchanged. Active speech extends the variable-blur transition up to another 48 points above the prior feathered contour. Silence still has zero blur radius. The loading function remains unchanged. Build 4 was an intermediate verification package; build 5 is the delivered package.

The expanded native probe includes 0.3 soft-speech and 0.55 speaking levels, each with a color-only comparison, on both displays. At speaking level, a 3-point background line widens to 9 then 20.5 points on Retina and 9 then 22 on the external display as it approaches the bottom. At soft level it widens to 13 then 27 points on Retina and 13 then 32 on the external display. These checks exercise visible backdrop spread above the main color body rather than depending on loud input. Static and animated captures remain nonactivating and click-through.

Artifacts: build/verification/build-5-glow. Commands: scripts/check-glow-progression.py with default speaking state, and --state soft-speech --heights 180 90 75 60. Both pass on both displays. The 42 service/domain tests passed after the response change; the final color adjustment was checked through the packaged native captures. Packaged metadata, compiled identity, and menu label match S2T 1.0.1, build 5. No live microphone or provider request was needed.

## S2T 1.0.1, build 6: cross-app window hosting

The custom variable blur layer had windowServerAware enabled but omitted the window registration and auto-flatten configuration needed for a live behind-window compositor tree. The prior fixtures and pixel comparisons did not establish normal cross-process behavior. This revision configures only the S2T overlay window after attaching its backdrop: disable shouldAutoFlattenLayerTree, toggle canHostLayersInWindowServer off/on to register the tree, and use a nonopaque, nearly transparent backing. The backdrop disables in-place filtering and allows native substitute colors for unavailable content. The setup repeats when the view joins a different window and retains full-width masks. Colors, response curve, feather, loading animation, and audio routing are unchanged.

The window hosting requirements were cross-checked against the original implementation notes in [Oskar Groth's NSVisualEffectView investigation](https://oskargroth.com/blog/reverse-engineering-nsvisualeffectview). The local runtime exposes the required setters; its default auto-flatten value was true, and the new configuration reads back false. The required hosting and filter APIs remain undocumented.

The user prohibited screen recording. No screen recording, screenshots, image-based computer use, or screen pixel readback were performed for this revision. --verify-glow now performs structural checks only. A separate fixture process supplies a window behind the overlay. On both the Retina and external displays, runtime checks confirmed independent fixture processes, live WindowServer hosting, automatic flattening disabled, full-width variable filter attached, persistence beyond the idle interval and hide/show, and no keyboard-focus change. The test does not assert the visual result. The earlier image-based regression script and artifacts are historical and were not used for this revision.

Logs: build/verification/build-6-hosting.log and build-6-tests.log. All 42 service/domain tests pass. Compiled identity, bundle metadata, and menu label agree on S2T 1.0.1, build 6. No live microphone, provider, or paste test was required.
