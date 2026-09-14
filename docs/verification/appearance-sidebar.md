# Appearance sidebar and preview repair

The old mounted preview measured only 10 by 184 points. Its unconstrained hosting view took its intrinsic width inside a vertical NSStackView. The earlier probe checked slider layout and separately generated glow images, which missed this failure. A new mounted-preview assertion reproduced the failure before implementation.

The window now uses NSSplitViewController and a native source-list NSTableView for mode selection. Its content is 640 by 586 points, with a 152-point sidebar. Controls sit in two rounded groups, the theme/reset footer stays anchored, and every stacked section has an explicit width constraint. The preview's aspect ratio follows its authored scene and measures 448 by 208.5 points. Mode changes retain the window size and selected setting. There is no settings window at launch.

The preview uses the existing production Chroma drawing and progressive blur on an authored miniature workspace. It never samples the microphone, clipboard, desktop or focused fields. Bezel's renderer is unchanged. All native sliders, theme and placement controls retain their saved behavior.

Verification checks the actual never-shown window hierarchy. It validates sidebar selection, preview and control bounds, the mounted background and current native filter request, and visible glow in AppKit's offscreen drawing of the authored preview. Generated layout fixtures come from that same hidden hierarchy, not screen capture. Separately generated Metal fixtures retain the blur-effect checks. These are not claims of live cross-app pixel equivalence.

Delivered S2T 1.0.1 Build 202 at the canonical `build/S2T.app`, preserving concurrent provider work. The canonical app was restarted without activation. The mounted-window and build-identity checks passed again on Build 202.

All 197 domain/service tests passed. Packaged checks passed for appearance performance and sliders, Brighter edge, blur response, notch fit/placement, input outline, Bezel, menu highlights, full glow composition and build identity. The native slider workload's maximum action durations were 1.985 ms for Bottom, 2.012 ms for Notch and 2.995 ms for Input. The previous Build 199 check's maximum was 5.277 ms; this confirms the layout retains responsive slider actions, rather than establishing a new rendering speed improvement.

The updated probe also confirms visible glow samples in the actual mounted preview's offscreen rendering. Complete authored layout fixtures are in `build/appearance-sidebar-fixtures`. Inactive native sidebar vibrancy in these offscreen drawings does not represent live WindowServer compositing. No screen capture, real provider request or microphone recording was needed.
