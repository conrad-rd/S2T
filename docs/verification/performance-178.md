# Performance correction, Build 178

S2T 1.0.1, Build 178. No appearance presets, sampling rates, microphone gain, provider settings, or animation timing changed.

The original running Build 177 used about 189 percent CPU. A three-second process sample showed the main thread repeatedly generating glow maps and submitting native filters. Its physical footprint was 882 MB. The sample contains stack traces, not screen pixels or field contents, in `build/performance-before.sample.txt`.

Changes:

- Generate Bottom and Notch native maps at the native root only. The previous SwiftUI path also generated a map, including when no backdrop was requested.
- Reuse exact unchanged expansion images and radius maps in bounded caches. Keys include geometry, source identity, expansion, distortion, width and exclusion path as applicable. No quantization or reduced resolution.
- Preserve the native filter submission when its image, radius, geometry, scale and filter identity are unchanged.
- Pause Bottom, Notch and Input timelines after fade-out completes. Resume before presentation and preserve fade reversal. Keep layers and color hosts alive.
- Measure shortcut hold duration from event timestamps. Queued press/release events previously appeared simultaneous and could turn a hold into a tap.

## Measurements

Same synthetic workload before and after, release configuration on the same Mac. Times measure generated-field preparation, not complete display latency. Other applications remained running.

| Workload | Before median | After median |
| --- | ---: | ---: |
| Bottom quiet fields | 12.69 ms | 0.01 ms |
| Notch quiet fields | 8.31 ms | 0.04 ms |
| Input quiet fields | 7.55 ms | 0.02 ms |
| Existing 1440 × 240 Bottom full-frame benchmark | 5.44 ms | 2.20 ms |

Changing speech-field preparation alone remained approximately unchanged. The improvement during animation comes from removing redundant work around it. Exact-result reuse adds bounded retained image memory.

All six SHA-256 digests of generated tint, light, sweep and radius pixels match before and after, covering quiet and changing speech in all three appearances. Run `--benchmark-glow --fields` to reproduce. Reports are in `build/performance-before-fields.txt` and `build/performance-final-fields.txt`.

After normal restart, the packaged app was idle at 0 percent CPU and approximately 35 MB resident memory. This idle observation is not a matched recording workload and resident memory is not the physical-footprint metric reported by sample.

## Verification

- `bash scripts/test.sh`: 169 tests passed.
- New unposted queued-hold regression failed before the timestamp correction and passed afterward through `--verify-onboarding`.
- `--verify-build`, `--verify-menu-highlights`, `--verify-glow`, `--verify-notch`, `--verify-input-outline`, `--verify-contour-frames`, and `--verify-prompt-mode` passed on the packaged app.
- Glow verification includes hidden-window attachment, backing changes, phase transitions, fade reversal, pause after hiding and resume on restart. Both connected displays passed.

No screen capture, real field reads, microphone recording, credential access or live provider requests were used for these checks. Generated-pixel equivalence is not a live cross-app visual comparison. Physical keyboard behavior was not tested.
