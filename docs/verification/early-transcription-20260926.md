# Dictation latency, September 26

The saved successful dictations had a median Finish-to-completion duration of 2.781 seconds. Transcription took 1.328 seconds median and cleanup 0.912 seconds. The selected routes were S2T credits, AssemblyAI Universal 3.5 Pro, and GPT-OSS 120B on Cerebras with Low reasoning. These are local stage timings, not a screen-pixel measurement. Numeric baseline records are in `build/dictation-speed-20260926/baseline-timings.json`.

The user authorized sending audio while speaking, including the possibility that cancellation follows a charge. With S2T credits, Transcribe while speaking now defaults on and has a switch in Dictation settings. Personal-key and local speech routes keep their existing behavior.

After at least eight seconds of audio and a half-second pause, S2T sends the completed section to the selected speech model. It leaves a quarter-second of silence at the beginning of the next section. Continuous speech is not cut to meet a timer. Short utterances still use one request at Finish. All sections are combined before one final cleanup request, so later corrections remain available to the cleanup model.

Each boundary and its original audio are encrypted before upload. Saved section boundaries, deterministic resampling, cached results and stable request IDs let Finish and recovery reuse completed requests. An uncertain section keeps its request identity. Starting again after cancellation waits for the old reader to stop before reusing the microphone buffer. Completed delivery removes that recovery from the in-memory list instead of reopening every encrypted record.

The provider still uses the existing [synchronous transcription API](https://www.assemblyai.com/blog/sync-speech-to-text-api-technical-walkthrough). The older paced WebSocket implementation is not reenabled. No service deployment, provider model, cleanup instructions or reasoning setting was changed by this work.

The first app-level comparison used generated 21-second audio and a simulated provider whose response delay scales with uploaded duration. Finish-to-delivery was 1,171 ms with the previous timing of uploads and 500 ms with early transcription. This proves work moved before Finish in the production AppState path. It does not establish live provider latency or transcription accuracy.

The focused suite passed 33 checks covering audio conversion, section boundaries, encrypted recovery, payment identity and credit requests. The app probe also checks Finish during a pending request, cancellation, complete ordered audio delivery, one cleanup request containing all sections, and no repeated completed uploads. Its output is in `build/dictation-speed-20260926/early-probe.log`.

Recordings without a qualifying pause cannot get the same improvement. Provider latency and cleanup time still remain after Finish. No live inference, microphone recording or personal transcript was used for these checks.

## Packaged result

`build/S2T.app`, version 1.0.1 Build 901, passed build identity verification and the packaged early-transcription probe, including immediate cancel/restart. The packaged comparison measured 1,073 ms before and 380 ms with early transcription, a 65% reduction under simulated provider delays. The packaged startup and credits/recovery checks also passed. Logs are under `build/dictation-speed-20260926/package-*.log`.

The Models interface showed editable controls, which the app disables during recording or processing. The idle old process was then quit through the app and reopened from the canonical package. A process check confirmed the new S2T process started at 16:36:18 local time from `build/S2T.app`; its package remained Build 901. The interface tool timed out while reading the newly opened app, so post-restart UI state was not verified. The live preference has no override for Transcribe while speaking, so the new default applies.
