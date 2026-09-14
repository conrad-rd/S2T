# Blur response correction

Delivered in S2T 1.0.1, Build 193.

The amount slider multiplied both blur radius and field depth by as much as five. It also resized the panel above 200 percent. Each new geometry invalidated pending native frames. Once the panel reached the display bounds, its geometry stopped changing and rendering caught up.

A generated input fixture reproduced 25 geometries and only 6 published frames during a 2.05-second drag from 200 to 500 percent. The same drag now retains one geometry and publishes 30 frames. Native slider actions took at most 0.791 ms in the separate packaged performance check. These measurements use synthetic audio and isolated preview preferences.

The raw amount still controls brightness and retains the saved 0–500 percent range. Exterior expansion now follows `2a / (1 + a)`. Native radius follows `2a / (a + 1/3)`. Both curves are continuous. The first preserves the approved extent at 100 percent and limits growth. The second strengthens lower settings and approaches a ceiling without a threshold. Reduce Motion still freezes expansion and deformation. Bezel's radius path and source files are unchanged.

For the reference 940-point input at full intensity:

| Amount | Previous radius | Updated radius | Previous spread | Updated spread |
| --- | ---: | ---: | ---: | ---: |
| 30% | 5.4 pt | 17.05 pt | 0.30 | 0.46 |
| 100% | 18 pt | 27 pt | 1.00 | 1.00 |
| 200% | 36 pt | 30.86 pt | 2.00 | 1.33 |
| 400% | 72 pt | 33.23 pt | 4.00 | 1.60 |
| 500% | 90 pt | 33.75 pt | 5.00 | 1.67 |

The original offscreen Core Animation filter did not show a discrete radius discontinuity at 400 percent. The confirmed issues were compounded growth and discarded frames during geometry changes. The updated generated-line rendering changes by at most 2/255 between the sampled 390, 400 and 410 percent settings.

Input uses consistent top-down local coordinates, including fractional field bounds. The fixed padding retains the entire outward fade. The wider low-amount field avoids the previously compressed lower tail. At 30 percent, generated Canvas alpha below the input is 36, 16, 2 and 0 out of 255 at distances of 15, 30, 60 and 120 points. At 500 percent it reaches zero before the fixture's lower boundary. Input interiors remain clear. These are authored render checks, not captured app pixels.

The new regression tests failed on the previous panel resizing, excessive expansion, weak quiet extent and fractional vertical alignment. All 187 domain and service tests pass after the changes.

Packaged checks passed:

- `--verify-blur-response`, generated native filters and Canvas, hidden panel geometry on both displays, synthetic slider drag.
- `--verify-brighter-edge`, approved nominal colors and maps still match within 1.14/255; updated blur strength checked separately.
- `--verify-appearance-performance`, `--verify-appearance-sliders` and `--verify-menu-highlights`.
- `--verify-notch-fit`, `--verify-notch`, `--verify-input-outline` and `--verify-glow build/glow-verification`.
- `--verify-bezel` and `--verify-build`.

Logs and generated fixtures are in `build/blur-response-*`. No screen capture, real fields, real clipboard, microphone capture or provider requests were used. Cross-app visual blur and the user's exact live scene were not captured or visually verified.
