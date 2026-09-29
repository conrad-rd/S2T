# Processing delay investigation

September 20, 2026. The saved successful-stage measurements were 2.616746 seconds for transcription and 0.616346 seconds for cleanup. Jev was already off. These older counters have no request identifier or timestamp, so they do not prove that both values came from the same dictation. The selected speech path was credit-funded AssemblyAI streaming. The cleanup model and host were GPT-OSS 120B and Cerebras.

The existing isolated `--verify-streaming-latency --require-nonblocking` check delivered its synthetic transcript in 0.016 seconds with immediate provider responses, without waiting for a one-second billing report. Its low-balance case correctly waited for settlement and took 1.019 seconds. This does not measure a real connection or identify the cause of the user's wait.

## Duration breakdown

`CreditStreamingSession` now measures authorization, WebSocket connection, and three disjoint intervals after Finish: waiting for the connection, sending remaining audio, and waiting for the final provider response. `AppState` stores these numbers in `lastStreamingTiming` and their observation time in `lastStreamingTimingAt`, in its existing local preferences. The previous timing is cleared when a new transcription begins. Preview checks use their isolated preference domain. No transcript, audio, credential, provider response, account identifier or session identifier is included in these measurements.

The startup probe checks the breakdown against independently injected one- and six-second authorization delays, known synthetic audio durations, and a 150-millisecond final-response delay. It retains cancellation, rejected authorization, exact audio bytes and real-time pacing checks. The timing intervals must account for the total Finish duration without double counting connection setup completed while recording.

Build 679 changed no model, reasoning setting, Jev preference, audio pacing, provider request or delivery behavior. That initial update added diagnostic instrumentation, not a demonstrated speed improvement. A normal dictation with the updated app is needed to separate the observed streaming delay into its actual stages. Do not infer the cause from the synthetic provider timings.

## Verified package

Canonical `build/S2T.app`, version 1.0.1 Build 679, passed `--verify-recording-startup --require-nonblocking`, `--verify-streaming-latency --require-nonblocking`, and `--verify-build`. All 398 service/domain tests passed through `bash scripts/test.sh`.

The one-second authorization fixture reported 0.664 seconds of remaining connection delay, 0.503 seconds of buffered audio, and 0.159 seconds awaiting the final response, totaling 1.326 seconds after Finish. The six-second authorization/six-second synthetic audio fixture reported 5.655, 6.046 and 0.160 seconds respectively, totaling 11.860 seconds. These fixtures intentionally supply audio independently of physical recording time and demonstrate correct attribution, not expected real dictation latency. Cancellation, rejected authorization, exact samples and pacing checks passed.

The packaged delivery check remained at 0.016 seconds with immediate fake speech responses; its low-balance case took 1.021 seconds including the injected one-second settlement delay. No live provider requests or screen capture were performed. Raw checks are in `build/processing-timing-*.log`.

## Longer dictations and pacing

The user clarified that longer dictations are slow. A standalone generated-audio fixture compiled the actual `CreditStreamingSession` and `AssemblyStreamingClient` sources, with a fake microphone that exposes samples at recording speed and a fake socket with 30 milliseconds of send overhead. Both five- and sixty-second recordings included a one-second authorization delay. It checked sample order and complete delivery. No microphone, user recording, screen, credentials or real provider was accessed.

| Generated recording | Before, Finish to result | After, Finish to result |
| --- | ---: | ---: |
| 5 seconds | 1.313 seconds | 1.220 seconds |
| 60 seconds | 1.792 seconds | 1.221 seconds |

The old sender set each deadline from the previous chunk's actual send time, accumulating scheduling delay. The corrected sender advances its deadline by the duration of the audio sent on one continuous clock. Saved-recording replay previously slept for a full chunk duration after every completed send, adding all send overhead to the recording duration. It now uses the same elapsed-time pacing principle. This follows AssemblyAI's [wall-clock pacing guidance](https://www.assemblyai.com/docs/streaming/guides/stream_prerecorded_file_realtime). It preserves all audio and overall real-time pacing, rather than sending the entire backlog immediately.

These single-run synthetic comparisons are not real provider latency measurements. Actual authorization wake-up time was 1.064 seconds before and 1.004 seconds after, accounting for about 60 milliseconds of the absolute difference. The more useful result is that the extra 55 seconds of audio added 479 milliseconds to the old Finish delay and only 2 milliseconds after the correction. Connection setup still leaves a fixed backlog, and the real provider's final-response delay remains unmeasured.

The independent packaged replay regression sends two seconds of known PCM through the production replay method with an injected 40-millisecond per-send delay. It checks exact bytes, that sent audio never leads elapsed streaming time by more than 40 milliseconds, and that completion stays under 2.5 seconds. Sources, generated audio, executable fixtures and raw before/after reports are in `build/streaming-duration-check`.

The standalone replay comparison measured 3.072 seconds before and 2.080 seconds after for the same two-second PCM and delayed socket. The old implementation therefore fails the new 2.5-second completion requirement. The final packaged regression completed in 2.036 seconds with every sample preserved.

S2T 1.0.1 Build 680 passed all 398 service/domain tests, `--verify-streaming-latency --require-nonblocking`, `--verify-recording-startup --require-nonblocking`, and `--verify-build`. The existing one-second authorization, cancellation, rejection and six-second backlog checks still pass. The user approved restarting S2T; the canonical app was reopened with the fix. A real long-dictation comparison remains pending and no paid inference was performed by the agent.


## Authorized live 50-word comparison

The user authorized up to 10 S2T credits for a generated clip, using the saved S2T connection without changing settings. One streaming request and one file request used identical 16 kHz mono PCM, 19.275625 seconds and 50 authored words. Credentials stayed in memory, no personal recording was used, and no transcript or token was logged. The client conservatively committed the entire authorized budget before dispatch to prevent accidental repeat spending.

| Route | Stop to transcription result | Normalized word errors |
| --- | ---: | ---: |
| Direct streaming | 2.255 seconds | 0 of 50 |
| File transcription, including upload | 0.852 seconds | 0 of 50 |

Streaming authorization took 0.780 seconds and connection 0.842 seconds while the simulated microphone recorded. At Stop, the remaining audio took 1.645 seconds to send, followed by 0.610 seconds for the final provider result. File transcription was 1.403 seconds faster in this single comparison. The wallet difference was 1 credit, with no pending holds afterward. This comparison excludes cleanup and insertion, uses generated speech, and does not establish typical or worst-case latency. It is not proof of two-second visible delivery. Raw results and the bounded runner are in build/fifty-word-latency.

New credit-funded AssemblyAI recordings now use the existing file transcription route after Finish. The Universal 3.5 Pro model, cleanup settings, exact captured samples, encrypted recovery and payment identities remain unchanged. Existing streaming recovery records still take their original replay/reporting path. File audio passes through the S2T credit service instead of the direct streaming socket. Long recordings retain the existing lossless part upload and completed-part retry cache; this live comparison did not measure long recordings.

Local duration diagnostics now cover Finish-to-pipeline, preparation, transcription, cleanup when used, insertion return and completion, with a word count and timestamp. They contain no transcript, credentials or audio. Insertion return is not a screen-pixel measurement. The startup fixture checks these counters against injected transcription delays and the total pipeline duration.

Canonical S2T 1.0.1 Build 682 passed the packaged startup/cancellation/failure checks, credits and encrypted recovery checks, streaming settlement/replay checks, hidden Models interface checks and build identity verification. All 400 service/domain tests passed. Earlier timing-sensitive runs encountered long scheduling delays and failed; the full rerun with idle sleep inhibited completed in 8.381 seconds with no failures. No provider inference was performed by these verification checks.

The previously authorized restart was completed after verification. S2T reopened from the canonical Build 682 app in the background. Actual user dictation with the new route remains to be measured.
