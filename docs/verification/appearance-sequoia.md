# Sequoia Appearance refinement

The native Appearance window now uses the user's macOS Settings references. It keeps the source-list sidebar and adds colored SF Symbol tiles, icons beside slider labels, separate Preview/Glow/Speech response headings, and miniature Light/Dark/Auto choices. The window has 640 by 548 content points with a full-height native material sidebar.

The forest is Apple's Sequoia Sunrise wallpaper, a bundled 1600 by 899 still extracted from the official wallpaper video listed in macOS's asset catalog. Resources/Appearance/README.md records its source. The preview has no runtime network request and never samples the user's desktop.

Only Intensity, Background blur and applicable Width are visible initially. Fine-tuning reveals softness, falloff, edge brightness and speech response amounts. The settings scroll independently of the fixed preview. Changing modes or closing Fine-tuning resets the settings scroll position. Every setting still saves immediately. Bezel's production renderer is unchanged.

The capture-free Appearance probe checks all saved controls through native actions, all four sidebar modes, icons, theme thumbnail buttons, disclosure behavior, scrolling each advanced setting into view, stable preview geometry while scrolling, the bundled wallpaper, and real mounted glow/filter updates. It draws only the authored hidden hierarchy for its fixtures, including an expanded dark layout. Native inactive sidebar vibrancy in those offscreen drawings does not describe live WindowServer compositing.

S2T 1.0.1 Build 207 passed all 197 service/domain tests and the packaged Appearance window, slider, performance, Brighter edge, blur-response, notch-fit, notch, input-outline, Bezel, menu-highlight, full-glow and build-identity checks. Native slider action maxima were 1.547 ms for Bottom, 2.243 ms for Notch and 2.625 ms for Input. The previous layout's equivalent check peaked at 2.995 ms; these are controlled checks, not a claim about measured live recording latency.

The mounted preview measures 436 by 202.5 points. Generated layout and native-filter fixtures are in build/appearance-sequoia-fixtures. Both collapsed and expanded settings, Light/Dark/Auto persistence, and the fixed preview while scrolling are covered. No screen capture, real provider request or microphone recording was used for verification.

Build 211 moves the unchanged Light/Dark/Auto thumbnail controls into the main pane's header, above the preview. The sidebar now contains only mode navigation. A small native AppearanceThemePicker owns the buttons and their saved selection. The packaged Appearance check verifies that the choices are outside the sidebar and above the preview, plus all three theme actions and existing layout/render checks. All 197 tests, menu-highlight checks and build identity passed. The canonical app was restarted without activation.
