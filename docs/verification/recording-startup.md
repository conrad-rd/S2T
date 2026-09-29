# Recording startup

S2T credits previously awaited streaming authorization before opening the microphone. The activation test reproduced a 1,027.74 ms wait with a 1,000 ms fake authorization and 15 ms simulated microphone startup. The appearance request itself took 0.13 ms, but preparation selected the processing appearance for Classic, Bottom and Around Notch.

Recording now opens the selected microphone before requesting streaming authorization. The streaming session authorizes in the background. Finish can await that same pending session, and cancellation cancels its task and authorization by the original idempotency key. Authorization failure preserves the recording for Retry or Save recording.

Streaming reads from the existing bounded recording buffer using a separate cursor. It no longer discards opening audio after a five-second connection delay or maintains a second copy of the backlog. Reads contain at most 100 ms of PCM. Finalization takes its recording snapshot before the streaming reader can release the buffer. Prompt speech keeps its independent buffer.

Buffered audio retains real-time pacing. AssemblyAI's [streaming guide](https://www.assemblyai.com/docs/streaming/guides/stream_prerecorded_file_realtime) warns against sending buffered recordings faster than real time. Any remaining connection backlog finishes during processing. This moves the connection wait out of recording startup; it does not eliminate provider latency.

Preparation now selects the listening appearance. Bottom and Around Notch use immediate panel opacity, and Within Input does not invalidate its focused-field lookup when preparation advances to recording. Existing appearance shapes, motion and asynchronous rendering remain intact. Cold render preparation and fresh Accessibility geometry can still take time; an immediate appearance request is not proof of physical key-to-visible-frame latency.

Run `build/S2T.app/Contents/MacOS/S2T --verify-recording-startup --require-nonblocking` for the complete activation-to-delivery fixture. It uses synthetic microphone input through the production capture callback, fake HTTP and WebSocket transports, isolated preferences and output, and no real credentials, fields or microphone. It checks exact opening PCM, release before authorization completes, cancellation, rejected authorization recovery, a six-second backlog, real-time send pacing, finalization and listening-phase selection.

The identical one-second-delay workload took 17.57 ms after the change, with an appearance request at 0.21 ms. Cancellation, rejection and six-second authorization scenarios started in 18.64, 24.63 and 23.64 ms. These are synthetic startup timings, not physical key-to-recording measurements.

Before the change, the existing no-storage physical microphone check measured 66.06, 84.45 and 84.81 ms for the built-in input. It preserved the output device, sample rate and channel count, and passed cancellation/restart checks. The microphone is still opened only when needed and released on stop. It is never kept recording while idle.

Verification logs are in `build/activation-latency/`. The canonical package is `build/S2T.app`.

## Verified package

Version 1.0.1, Build 671 passed all 391 service/domain tests and the packaged startup, streaming latency, Bezel, Liquid Glass, Around Notch, glow, input outline, onboarding and build identity checks. Input outline initially reported that the foreground app changed during its stability check; the repeated hidden check passed.

The same no-storage physical microphone workload after the change measured 78.26, 81.28 and 79.21 ms. Its worst main-run-loop heartbeat gap was 6.10 ms, compared with 6.08 ms before. Output routing and cancellation/restart passed. The measured benefit comes from removing the authorization wait before microphone opening, not making the physical device itself faster.

No live provider inference or screen capture was performed. Automatic approval review blocked restarting the running app because termination could lose in-memory dictation. The updated canonical package is ready; restart requires the user's approval.
