# Plain paste and Cerebras

2026-09-12

The user's actual preferences had `pasteToApp = false`, so production skipped the entire insertion routine. Earlier isolated insertion tests did not exercise that application-level condition.

Removed the paste preference from AppState and the settings toggle. Completed dictation always copies output and sends marked Command-V down/up events through the HID event stream. Removed production Accessibility field reads, writes, focus comparison, menu walking, and readback. The only app restoration is returning from S2T to the prior app. Posting permission errors still leave the text copied and show a hint.

The live editor check passed six cases, all using real Command-V events: an editor whose Accessibility writes are ignored, a native editor, no captured target, search selection, return from Start, and the full AppState completion path with the old paste preference explicitly false. Each test read the complete expected field text. The completion test also verified the clipboard. Results are in `build/verification/plain-paste-live.log`.

Added a Cerebras Keychain account and secure API key field. The native provider selector is available in API keys and Models. Provider switches load separate stored feed URLs and fallback models. Cerebras does not require an OpenRouter key. Verbatim continues to require only AssemblyAI.

Cerebras requests use the authenticated chat completion API at `https://api.cerebras.ai/v1/chat/completions`. Its default model is `qwen-3.8-27b` with `reasoning_effort: none`, matching the current official example and public model listing. Custom model IDs remain editable. Provider-specific validation prevents sending OpenRouter IDs to the Cerebras API. Only the selected provider receives its key and the transcript.

Six new service tests cover Cerebras routing and authentication, preservation of language and final content, credential separation, direct model IDs from feeds, invalid model rejection, and incomplete output. All 42 service and domain tests pass. Packaged live settings checks passed provider selection, loading the Cerebras default, credential requirements, page navigation, the slider, and Preview. Inspected API keys and Cerebras Models captures in `build/verification/cerebras-settings`.

No live Cerebras completion was run because the user has not supplied a Cerebras key. No Raycast interaction or live provider request was used for verification.

Sources checked:

- https://inference-docs.cerebras.ai/api-reference/chat-completions
- https://api.cerebras.ai/public/v1/models
