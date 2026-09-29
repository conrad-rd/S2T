# Screenshot selection scheduling

The reported lag affected S2T's screenshot selection during dictation. The selector delayed every new batch of pointer movements by a full display interval, including the first movement. When pointer events arrived near the display rate, this unnecessarily coalesced movements and reduced border updates.

`PromptCaptureFeedback` now draws immediately when a frame is due, schedules intervening movements for the next cadence deadline, and retains only the latest pending rectangle. Deadlines advance on a stable cadence rather than accumulating callback delay. Clearing selection invalidates queued work and resets the deadline for the next gesture. Capture, dictation and appearance rendering are unchanged by this fix.

## Measurement

Run the packaged executable with `--benchmark-selection`. The fixture submits 90 synthetic rectangles at each requested frequency to the actual selector and measures time until its native border layer update. Panels stay hidden. The same fixture ran before and after the scheduling change.

| Requests | Updates before | Updates after | p95 before | p95 after |
| --- | ---: | ---: | ---: | ---: |
| 60 Hz | 55 / 90 | 90 / 90 | 19.813 ms | 0.094 ms |
| 120 Hz | 53 / 90 | 90 / 90 | 9.415 ms | 0.105 ms |

These are event-to-layer timings, not displayed frame rates or live screenshot capture latency. The original live stall has not been reproduced. Main-thread contention elsewhere can still delay selection.

Evidence is in `build/selection-latency/before.log` and `after-final.log`.

## Verification

- Packaged `--verify-prompt-mode` passed. Selection checks cover immediate first movement, latest-rectangle coalescing, cancellation of pending updates, fresh-gesture timing, hidden panels and existing capture gesture behavior.
- `bash scripts/test.sh` passed all 345 tests.
- Packaged `--verify-build` passed for S2T 1.0.1, Build 630, compiled September 19, 2026 at 08:34:50 UTC.
- Canonical package: `build/S2T.app`.

Verification used synthetic data, hidden windows and isolated state. No screen capture, microphone capture or events posted to user apps.
