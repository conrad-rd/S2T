# Draggable Classic website preview

Classic now uses one live contour for both the floating glass capsule and the edge-attached Bezel. Pointer capture stays on the same SVG path throughout a drag. Moving within 36 scene points of an edge attaches it; an attached indicator releases beyond 72 points. Floating releases retain their position. The parent page retains placement across appearance changes. Escape and pointer cancellation restore the starting placement, and keyboard controls provide movement, attachment and Reset.

The renderer uses the native 112-by-36 capsule, existing Lisse Bezel geometry, ClassicDockMotion's 11.5-frequency critical spring and ClassicLiquidMotion's bounded deformation. The five floating processing bars use GlassCapsuleArtwork.drawProcessing's 1.5-second period, .14 phase spacing, 3.2-point width, 4–16-point heights and .48–.90 opacity. Reduce Motion fixes the phase at .22. The attached state keeps the spinner. The older prerecorded glass cycle is no longer rendered by Classic.

One layout-effect owns animation setup and cleanup, so tab removal cancels animation before its SVG refs detach. The SVG owns touch gestures on the hit path, and the page scroll handler excludes that path. Ordinary page scrolling remains available outside it. The three placement buttons now fit their container.

Glass remains a browser approximation using clipped backdrop blur and the native dark lower fade. Checks inspect DOM, actual mouse/touch event handling and geometry without screenshots. They do not prove pixel parity with NSGlassEffectView.

Build and TypeScript checks pass. Browser verification is in build/website-classic-drag/verify.mjs, with exact result records next to it. The app and its running process are unchanged. This corrects the earlier website implementation that offered only buttons to switch floating and attached forms.

Published to https://s2t.app as deployment dpl_FPnsnZTUnaFCPhb32M4TErrhhMeX, https://s2t-fui4rjolz-conradbaulig-9662s-projects.vercel.app. The local Chrome and WebKit checks passed at 375 and 1280 pixels. Chrome additionally passed actual touch attachment and detachment. No native app or billing deployment was made for this correction.

The public site passed the same complete Chrome/WebKit drag and processing checks. A follow-up restores the existing transcript layout rules for Classic's new DOM identity: floating text remains at 40% height, and attached text reserves space at the active edge. Independent DOM bounds checks passed for both edges and floating placement in Chrome/WebKit at 375 and 1280 pixels. Browser console checks reported no uncaught errors. Deployment drains and continuous monitoring were outside this UI change.

Final deployment dpl_FCVAQsko1kapDscqKhdHwzyYb1TM is ready at https://s2t.app, with deployment URL https://s2t-14np2x68n-conradbaulig-9662s-projects.vercel.app. Post-deployment Chrome/WebKit layout checks passed at both widths. The interaction implementation is unchanged from the preceding complete live drag/processing verification.

## First-visit drag hint

Classic shows a small noninteractive "Move me!" bubble after one continuous second without placement movement. It dismisses on interaction, visibility loss, appearance changes or after three seconds. One in-memory flag belongs to the persistent preview host, so dragging, Reset and tab remounts do not repeat it. A fresh page visit resets the flag; no cookies or local storage are used. The bubble stays within the preview width, appears below the indicator when there is no room above, and disables its fade for Reduce Motion.

The hidden-browser check in build/website-classic-hint/verify.mjs covers delay, movement resetting the delay, dismissal, no repeats after movement/tab changes/Reset, a fresh visit, expiry, pointer-event passthrough and narrow-screen bounds. Chrome and WebKit passed. No screenshots were used.

The hint is published in dpl_5agb4Pqm937CzkHD3XwELmx1KHKD at https://s2t.app, https://s2t-5g3yd8h7q-conradbaulig-9662s-projects.vercel.app. Idle timing tracks placement and docking motion, so processing/speech artwork changes do not restart the delay.
