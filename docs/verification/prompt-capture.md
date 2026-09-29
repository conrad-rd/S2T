# Prompt capture update

The fixture contains a generated 2560 × 1440 display image encoded as JPEG at quality 0.72. Both measurements select the same 800 × 600 area nine times, using optimized Swift compilation and the production screenshot conversion methods. No screen or microphone capture is involved.

| Measurement | Before | After |
| --- | ---: | ---: |
| Median crop preparation | 111.54 ms | 18.47 ms |
| Maximum crop preparation | 121.00 ms | 21.84 ms |
| Eight analysis image inputs, before base64 | 10,568,656 bytes | 7,610,464 bytes |

The previous crop path encoded the whole display to PNG, decoded that PNG, and encoded the crop. The new path decodes the retained frame once and encodes only the crop. Production dispatches this work away from the UI thread. Analysis preparation took 39.05 ms for this fixture and reduced payload bytes by 28 percent. It changes only analysis copies, preserving PNG attachments. Small PNGs remain PNGs when JPEG would be larger. The existing selected model and its options remain unchanged.

Source copies and raw measurement output are in `build/prompt-measurements`. The app's `--verify-prompt-mode --benchmark` runs the updated conversion and the existing fake-provider latency workload. Network delays in that workload are artificial; these numbers do not measure live capture, provider inference, or receiving-app attachment acceptance.

`--verify-prompt-mode` uses hidden native panels, generated images, unposted events, fake providers, and isolated pasteboards/files. It checks click jitter, reverse drags, final mouse-up coordinates, Command release, Escape, inactive passthrough, shortcut coexistence, stack placement on offset displays, pending captures at finish, capture ordering, cancellation, capture limits, direct-crop equivalence, and screenshot-only delivery. No real screen, microphone, credentials, clipboard, or receiving fields are read.

## Packaged result

S2T 1.0.1 Build 553 passed `--verify-prompt-mode`, `--verify-onboarding`, `--verify-menu-highlights`, and `--verify-build`. `bash scripts/test.sh` passed 307 tests. The packaged benchmark measured a 21.28 ms median crop, 22.27 ms maximum, and a 28.4 percent reduction in analysis image bytes. Image preparation is also measured separately in the standalone before/after fixture above. The controlled provider workload made one metadata read, one vision request, and one attachment transaction for eight references; its 0.310-second analysis and 0.766-second attachment wait are not live-provider measurements.

## Screenshot deck and delivery refinement

The same generated 3840 × 2160 image is shown twelve times in hidden panels. The before fixture uses the original production thumbnail and deck code. The after fixture uses a thumbnail prepared during the existing background conversion, a prewarmed panel and layer animations. Source copies and raw output are in `build/prompt-fluidity`.

| Measurement | Before | After |
| --- | ---: | ---: |
| Median main-thread capture presentation | 25.30 ms | 0.20 ms |
| Maximum main-thread capture presentation | 51.97 ms | 4.54 ms |
| Two-display, twelve-tick encoding workload | 180.81 ms | 192.47 ms |

Panel setup now happens once during Prompt startup and measured 32.37 ms. Encoding is unchanged; its fixture timings varied between runs. The improvement removes thumbnail decoding and window resizing from repeated capture presentation. These are CPU timings for hidden fixtures, not displayed FPS or live ScreenCaptureKit measurements. Full-resolution saved PNGs and the four-sample-per-second recording history remain intact.

The packaged probe checks rounded image-only layers, highlight and shadow metadata, actual layer attachment, stable hidden window frames, 120 coalesced selection updates, collapse, stale-hide cancellation and Reduce Motion. A blocked encoder fixture checks that stopping the sampling gate does not block the main thread. Attachment fixtures test before-text ordering, accepted filenames or image-count changes, absent-image fallback, a late confirmation that prevents retry, unknown/busy results, changed fields, permission and menu guards, clipboard changes and cancellation. Observations, recipients and paste events are injected; the clipboard and files are isolated.

### Packaged refinement result

S2T 1.0.1 Build 564 passed the packaged Prompt mode, benchmark, paste, onboarding, menu-highlight and build-identity checks. The release was packaged with `scripts/build-app.sh` from a stable copy of the current source while holding the shared package lock, into the canonical `build/S2T.app`. This avoided concurrent source edits interrupting the compiler. `bash scripts/test.sh` passed 307 tests after the delivery integration.

The packaged benchmark measured 0.19 ms median and 0.41 ms maximum capture-presentation work after 39.31 ms of one-time hidden panel setup. Crop preparation including its thumbnail measured 19.92 ms median and 21.80 ms maximum. The blocked-encoder fixture kept the stop gate below 0.001 ms. Mock provider timings do not represent live provider performance. Receiving-app attachment acceptance and displayed FPS remain unverified.

The broader paste fixture initially inherited `creditsEnabled=true` from shared preview preferences and stopped before delivery. It passes with launch-only `-speechUsesCredits NO -cleanupUsesCredits NO -creditsEnabled NO`, without changing real preferences. Prompt mode checks save and restore their isolated preference state themselves.
