# Meetings

Meetings is available in the root menu and settings sidebar. It records microphone audio, optionally alongside Mac playback through Core Audio process taps. It does not use ScreenCaptureKit or read screen pixels. Mac audio requires macOS 14.2 or later and the system audio permission. The microphone remains input-only; capture does not change the system's devices or formats.

The meeting model is independent of dictation. The initial choices are AssemblyAI Universal 3.5 Pro and Universal 2 with speaker diarization. Meetings currently require the saved personal AssemblyAI key. They do not use S2T credits. The selected model is snapshotted per meeting.

Audio is written to local WAV parts under `~/Library/Application Support/S2T/Meetings/<UUID>/`. Each complete 120-second part is queued while recording continues. Stop queues the remaining partial part. Saved provider job IDs allow later polling without another upload. A terminal provider failure permits explicit resubmission; transport failures retain the job ID. No automatic retries run on application launch. The history and pending audio remain available through Retry.

The library stores timestamps, speaker names, model, job IDs and completion state in an atomic JSON manifest. Interrupted recordings recover the final WAV length and discover audio written before its manifest entry. Quitting during capture waits for the local tail to be saved. Closing the settings window does not stop a meeting. A menu action stops the meeting without reopening settings. Dictation, Writing microphone capture and microphone testing cannot start during a meeting.

With Mac audio enabled, the microphone track is labeled You and call audio is diarized separately. This assumes the local microphone is used by the account holder. Headphones avoid recording the call through both sources. Mac playback includes other applications and notification sounds. In-person recordings use speaker labels; users identify themselves by renaming a detected speaker to You.

Later parts include up to eight seconds from each of at most twenty earlier speakers. Labels are matched by their overlap with those known sample intervals, rather than assuming provider letters are stable across requests. Ambiguous matches receive a separate identity. Reference speech is excluded from transcript output. This is probabilistic speaker matching, not authenticated identity or a measured accuracy guarantee. It adds some provider audio usage. Users can correct display names.

Export offers Markdown, PDF, Word DOCX, plain text and RTF. Each includes the meeting title, date, speaker names, chronological timestamps and available transcript text. Export during processing contains only completed transcript parts. PDF uses paginated Core Text. DOCX and RTF use AppKit document serialization.

## Verification

- `bash scripts/test.sh`: domain regression suite, including model/key isolation, diarization request fields, speaker label swaps, ambiguous matching, Unicode exports and persistence.
- `build/S2T.app/Contents/MacOS/S2T --verify-meetings`: twelve-minute synthetic recording, exact sample reconstruction, two-minute boundaries and final partial part, orphaned WAV recovery, all five exports, multi-page PDF text extraction, DOCX/RTF readback, hidden settings navigation, microphone exclusion, mocked processing before Stop and final-part completion after Stop.
- `--verify-settings-sidebar`: includes the Meetings destination and its distinct icon.
- `--verify-build`: compiled identity, bundle metadata and menu label.

The probes use temporary directories, preview preferences, synthetic PCM and fake provider responses. They do not use real credentials, real microphones, real Mac playback or screen capture. The existing app process is left running.

Real microphone/system audio capture, permission dialogs, live AssemblyAI compatibility and speaker accuracy have not been exercised in this verification. Automated checks do not establish real meeting transcription latency or speaker accuracy.

## Independent model settings

Meetings → Models now separates Speech to text from Text processing. Speech choices include AssemblyAI Universal 3.5 Pro and Universal 2, plus xAI Grok Voice Transcribe 2 and 1. All require speaker separation. Text processing offers OpenRouter, xAI, Codex and a local endpoint. OpenRouter has a searchable public text-model catalog, hosting choices, a manual model ID, capability-filtered reasoning, fast routing and explicit contributor consent. Codex choices come from its local catalog. Each provider retains its model choice. None of these controls changes dictation or Writing preferences.

Text cleanup is optional and initially off. Each new meeting snapshots its processing configuration. Completed parts are processed with that snapshot, including on retry after settings change. Processing validates a one-to-one mapping of utterance IDs, changes only the separate processed text, and retains original text, speaker IDs and timestamps. A failed cleanup can be retried without uploading or transcribing audio again. The Original transcript switch controls both the display and export. Old meeting records with no processing settings remain readable and unchanged.

MeetingProcessingTests cover response structure, original preservation, provider/key isolation, host routing and configuration snapshots. The packaged meeting probe injects a cleanup failure, checks original retention, retries after changing the current model and asserts no additional speech upload. It also checks populated native speech/provider controls in a hidden window. No live inference is part of these checks.


## September 21 speech choices

The main page exposes Provider and Voice model directly. Each provider restores its own saved choice. AssemblyAI retains its persisted upload/job flow. xAI sends `diarize=true` before the audio part to `/v1/stt`, parses word timestamps in seconds, and requires a speaker ID for each word. Both paths share cross-part speaker matching and preserve the selected model in the meeting record. Retries use that saved model and its matching personal key. No S2T credits are used for meetings.

Contract reference: https://docs.x.ai/developers/model-capabilities/audio/speech-to-text

Domain fixtures check xAI request fields, key routing and rejection of missing labels. The hidden meeting probe changes the native provider selector, checks both Grok choices, preserves per-provider preferences, and runs a synthetic Grok meeting through persistence. Live Grok inference and real speaker accuracy remain untested.
