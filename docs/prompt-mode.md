# Prompt mode

Prompt mode is an experimental beta, off by default. Enable it in the menu bar's Prompt mode submenu. Its setup action allows on-device Speech Recognition and Screen Recording. Existing dictation setup handles microphone and Accessibility access.

Prompt mode uses its own activation key, initially Right Command. Hold to speak and release to finish, or enable tap-to-toggle. Fn or your chosen normal shortcut continues ordinary dictation without screen recording. Command combinations pass through and cancel a held prompt recording.

While you dictate, S2T keeps a temporary local frame-and-cursor history at four samples per second. It retains the entire display under the pointer, including the desktop, menu bar, Dock and all visible windows. The display filter excludes no windows or applications. S2T verifies the filter has display scope and full display bounds before starting. System audio and the rendered cursor are excluded. Full frames use JPEG quality 0.72 in memory, with a 2400-frame and 256 MiB limit. Reaching either limit stops further frames and shows an explanation. The app's existing ten-minute dictation limit also applies.

After recording, S2T finds references such as "here", "like here", "zoom in here", "this tab here", "look at this", "check this out", "schau mal hier" and "schau dir das an" in the final transcript. It selects nearby recorded frames using word timestamps relative to the first microphone sample. AssemblyAI and ElevenLabs supply word times. Other providers can use aligned English or German on-device Speech results from the same microphone audio. Small recognition corrections can use a time estimated between neighboring words. The app reports these estimates.

Rapid repeated references are retained separately. There is no eight-reference cap or minimum interval between final cues. Up to 64 references can be delivered in a prompt; unmatched cues and references beyond that limit produce a visible warning. S2T never fills gaps by taking screenshots after recording. Frame selection rejects samples more than 0.6 seconds from the matched word. Sampling and display-frame timing are approximate, so very fast pointer motion can still associate a nearby position.

The separate OpenRouter image model analyzes all selected images in one request while text cleanup runs. It sees the original dictated request and each reference's timestamp and pointer coordinates. It is asked to inspect the whole area, prefer explicitly named objects, preserve ambiguity and return one sentence of at most 25 words per image. The default is google/gemini-2.5-flash. Public model metadata checks image input and text output before saving a model and before sending images or credentials. The cleanup model and hosting endpoint stay separate.

Only selected images and the dictation go to the image model. Full display frames are transient; unselected frame history stays in memory and is discarded after selection or cancellation. Clipboard-history contents are not added to image requests. Selected images become PNG files under ~/Library/Application Support/S2T/Prompt references. Each delivered reference includes its timestamp, filename and prompt-set ID. S2T does not automatically delete saved references.

After native text paste succeeds, S2T copies the selected file list in one marked clipboard transaction and sends one Command-V to the receiving app. Every screenshot also provides PNG clipboard data. There is one 750 ms wait for the batch, followed by copying the delivered prompt text if the clipboard has not changed. Pasting is guarded by focus, permission, menu and cancellation checks. S2T does not submit the prompt.

The receiving app must accept pasted files. Sent events do not prove that attachments appeared. Prompt mode → Reference images offers the saved files and manual image copy when needed. Image-description failures preserve the transcript and the selected screenshots, with short fallback notes. Error details stay in S2T. Cancel stops pending work and clears temporary history but preserves files already saved.

On-device Speech needs the chosen English or German model installed by macOS. Audio buffering remains bounded and task rollover uses overlapping audio. Final provider timestamps can still match references if local recognition fails. Without usable timestamps, S2T reports missing references instead of guessing a capture location.

## Verification

Use `bash scripts/test.sh` and package with `bash scripts/build-app.sh`. The packaged `--verify-prompt-mode` checks generated timelines, twelve rapid references with distinct frames, timestamp offsets, missing-frame warnings, memory bounds, cancellation, unconditional saving, error fallback and delivery ordering. It uses isolated clipboard/storage, fake transport and synthetic audio. Hidden WebKit fixtures check full Unicode text delivery without submission. No real screen, microphone, credentials, clipboard, keyboard posting or user fields are used.

See [timeline verification](verification/prompt-timeline.md) for the controlled before/after benchmark and its limits. Actual screen-stream behavior, live provider latency and receiving-browser attachment acceptance remain unverified.

Implementation references: [Apple screen streams](https://developer.apple.com/documentation/screencapturekit/scstream), [AssemblyAI word timestamps](https://www.assemblyai.com/docs/sync-stt/word-timestamps), [Apple on-device Speech requests](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest), [OpenRouter image inputs](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding).
