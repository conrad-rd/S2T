# Glow response verification

Measured on this Mac with the release executable. The baseline rendering source is preserved in `Glow-baseline.swift.txt`.

| Check | Before | After |
| --- | --- | --- |
| Audio-level handoff | App-state timer at 30 Hz, then animation at 30 Hz | Direct meter read at 60 Hz |
| Broad app-state updates while recording | Audio level and elapsed time at 30 Hz | Elapsed time at 1 Hz |
| Requested microphone callback size | 1,024 frames | 256 frames |
| Synthetic level step, 90% attack | 42.67 ms | 10.67 ms |
| 60-frame ImageRenderer probe, median | 0.08 ms | 0.04 ms |
| 60-frame ImageRenderer probe, p95 | 0.08 ms | 0.05 ms |

The synthetic level step uses the same RMS of 0.05 and peak of 0.1, a 48 kHz sample clock, and each version's requested buffer size. Each result is relative to that version's steady-state level. It measures smoothing response, not microphone hardware or screen latency. Actual audio callback sizes depend on the device and driver.

The rendering probe generates the same 60 frames at 1,440 × 240 after five warm-up frames. These timings measure the ImageRenderer calls. They do not measure display-server composition, GPU completion, dropped frames, or physical input-to-display latency.

The revised glow uses a single Canvas, a broader diffuse halo, a brighter inner glow, and a luminous bottom edge. Its width and height respond to level. Reduced Motion retains brightness feedback without ambient movement or height changes. Rendered quiet and loud frames were visually inspected.

All 21 service, gesture, and envelope tests pass. The test cases include independent hold/tap switches, tap latching, hold release, cancelled key combinations, orphan release events, bounded envelope output, and buffer-size-independent smoothing.

Live physical microphone switching and shortcut execution were not verified during this pass. Computer control failed with `Sky Computer Use native pipe startup failed`; reconnecting after a reset failed with `CUA_REPL_ENABLED_SURFACES is required`. The app includes a 15-second local microphone test for verifying the selected input and the real overlay without API keys or uploading audio.

## Input-only capture update

The later Bluetooth-routing fix replaces AVAudioEngine and its requested 256-frame tap with an input-only HAL audio unit. It uses the existing hardware buffer size. The 256-frame synthetic probe above remains a smoothing comparison, not a claim about the current hardware callback size. Direct 60 Hz metering and the time-based envelope are unchanged. See `audio-routing.md` for the new live capture checks.

## Processing line

Busy phases now render a separate 1.5-point bottom line with a soft five-to-six-point glow. A highlight travels left to right every 2.8 seconds. It uses elapsed animation time rather than microphone volume, and remains still when Reduce Motion is enabled. The panel remains transparent, nonactivating, and click-through. Existing phase handling shows it during microphone preparation, AssemblyAI transcription, and OpenRouter processing, including retries. Cancellation hides the overlay, and completion uses the existing brief completion glow before hiding.

Packaged previews in `build/previews-loading` cover transcription, processing, and reduced motion on light and dark backgrounds. The light and dark loading frames were visually inspected. Live network processing was not exercised because no provider calls were needed for this visual change.
