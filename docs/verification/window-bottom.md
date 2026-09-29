# Window-bound Bottom appearance

Bottom follows the selected application's focused window during both dictation and Prompt mode. The two modes call the same session setup and overlay controller. With Paste where dictation started enabled at session start, the tracker retains that starting window's Accessibility identity. It re-reads that window's bounds through recording, processing and completion, even if another window gains focus. Failure to capture the starting identity never rebinds the pinned session to a later window.

Window reads run off the main thread, with one request in flight, bounded AX messaging timeouts and stale-result rejection. They request only window identity, role, position, size, minimized and fullscreen metadata. They never inspect field content or window titles. Preview state does not run the tracker. Raycast remains excluded.

The glow, progressive native blur and processing line share the lower-corner geometry. Optional, dynamically resolved WindowServer metadata supplies resolved corner radii. Square and fullscreen windows keep straight corners; unavailable corner metadata uses a straight boundary. Geometry cache keys omit screen position so moving a window does not rebuild its color field. A missing, closed, minimized or offscreen lower edge uses the existing pointer-display bottom fallback. Around Input's existing missing-field fallback remains screen-bound.

Run:

```sh
bash scripts/test.sh
bash scripts/build-app.sh
build/S2T.app/Contents/MacOS/S2T --verify-window-bottom
build/S2T.app/Contents/MacOS/S2T --verify-glow /tmp/s2t-window-glow
build/S2T.app/Contents/MacOS/S2T --verify-input-window
build/S2T.app/Contents/MacOS/S2T --verify-build
```

The window probe uses injected AX objects, generated maps and invisible native fixtures. It checks following versus pinning, starting-window absence, movement, resize, closure, minimization, stale sampling, negative/fractional coordinates, square/rounded native metadata, clipping, fallback and nonactivating panels. These checks do not establish pixel-perfect cross-app rendering or physically exercise dictation and Prompt capture.
