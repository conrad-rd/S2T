# Codex Accessibility activation

The installed Codex app reported `com.openai.codex`, display name ChatGPT, version 26.908.40834. With its prompt focused, Build 343 returned no target. The focused window existed, but its tree ended at empty outer groups and exposed no focused editor.

The app rejected `AXManualAccessibility` with `attributeUnsupported`. Sending `AXEnhancedUserInterface = true` returned `notImplemented`, then enabled the tree asynchronously. The unchanged detector subsequently found the complete prompt at x 670, y 1009, width 736, height 136, including the inset header. These inspections used Accessibility metadata only, with no field contents or screen capture.

[Chromium's application implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/chrome_browser_application_mac.mm) schedules enhanced accessibility after a two-second debounce, then delegates the setter to AppKit. Its return code therefore does not establish whether activation was accepted.

S2T now falls back to the Chromium request only when the Electron request is unsupported or unimplemented. Around Input starts this request off the main thread on app launch, foreground-app changes and appearance selection. Repeated reads for the same app do not resend activation. Warm-up reads no field metadata and is disabled for preview and installation state. Targeting still validates focus, window and every contour part before display. Drawing, texture storage and compound geometry are unchanged.

The recorded Codex regression failed before the fallback with a nil target. It now covers an initially unavailable editor, delayed activation, repeated warm-up, the accepted request returning an error, and the existing scaled, removed and moved header cases. Separate checks preserve Electron success and permission/transport failure handling. The T3 fixture also passes.

All 231 service/domain tests passed. Packaged input-outline and input-contour checks passed, including the two footer blur connections and clear interiors. The new full-size hidden Codex lifecycle check mounts the actual asynchronous view through preparation, recording, processing and recording again, retaining its compound native map and window layers.

The same 1684 by 1084 generated workload before the targeting change completed 49.96 frames/s with default tuning and 41.96 with thin-edge tuning. After the activation fallback, it completed 49.21 and 42.46 frames/s. Maximum gaps were 23.91/31.20 ms before and 21.14/27.64 ms after. These are generated-frame timings, not physical display FPS. Cold activation can still require Chromium's own delay if dictation starts immediately after opening the app; focus warm-up moves that work ahead of normal dictation.

The final packaged Build 346 rerun passed the same thresholds at 45.97/35.47 generated frames/s, with maximum gaps of 24.17/29.44 ms. These totals include cold preparation and varied between runs; they do not establish identical performance or a speedup. The full-size mounted lifecycle and visibility checks passed. Build identity, packaged metadata and menu label agree. The canonical Build 346 executable is running. A later requested live recheck encountered SecurityAgent in the foreground, so it supplied no additional Codex evidence.

Concurrent work subsequently packaged Build 347 and restarted the canonical app. It retains the activation fix and passes both --verify-build and the complete cold Codex fixture. The newer app was preserved.
