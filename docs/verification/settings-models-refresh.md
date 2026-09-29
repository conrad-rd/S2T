# Settings model refresh, September 21

September 22 local browser refinement: one native popup for the local task shares a compact row with NSSearchField and the sort popup. The main Speech/Cleanup/Vision/Local navigation stays in place. Reusable NSTableCellView rows let AppKit control selection and focus, with readable selected text, truncated summaries and complete tooltips. Apple models use a shorter native group row. The list fits small catalogs before scrolling, and a native separator distinguishes the selected model details. Download metadata wraps in narrow windows. Existing actions and the published comparison remain available.

Verified in S2T 1.0.1 Build 785. All 447 domain/service tests passed, followed by packaged local-models, native-speech, models-window and build probes. Native task popup actions, model selection, search, sorting and 420/600-point control bounds passed. No screen capture, model download, live inference or running-app restart was used.

One native provider dropdown replaces the recommendation buttons and Other row. Speech lists S2T, AssemblyAI, OpenRouter and xAI. Text cleanup lists S2T, OpenRouter, xAI and Codex. Installed local models and custom endpoints remain in the same list below a separator. S2T models select their catalog-authorized service without exposing multiple S2T providers. Personal and paid configurations stay separate.

Model suggestions and the custom ID editor remain visible. Provider, host, reasoning and speed selectors use ordinary native dropdowns. Host names no longer contain the full pricing comparison. The selected host's published speed and price appear beneath it. Refresh is a small text action. Vision uses Image model, Hosting, Response and Codex connection headings, without disclosures.

## Speech hosting limitation

[OpenRouter's speech documentation](https://openrouter.ai/docs/guides/overview/multimodal/stt) states that its transcription endpoint ignores `order`, `only` and `ignore` routing preferences. Speech therefore displays a disabled Automatic host with an explanation. No unsupported pin is saved or sent. Manual speech hosting remains blocked by the upstream endpoint's capabilities.

AssemblyAI's Model row retains the existing fast/extended behavior. Extended languages use the batch service's Universal 3.5 Pro / Universal 2 selection, not a new fixed-model request.

## Local models

The model browser has two-line rows, search, memory/download/name sorting, installed and active status, and visible details/actions. Apple models use a static heading. The small performance chart stays open and uses proportional horizontal bars from zero. Selecting a bar selects the model's details without downloading or activating it.

Published scores describe parent models, not measured S2T quantized models or this Mac's speed. Sources were checked on September 21, 2026. Each selected scored model has a direct source link and its evaluation configuration. Unknown results have no bar. No local speed is fabricated.

- Speech uses FLEURS English word error rate. Qwen ASR 0.6B = 4.39%, Qwen ASR 1.7B = 3.35%, from [Qwen's report, Table 2](https://arxiv.org/html/2601.21337v1#S4.T2). Parakeet TDT v3 = 4.85%, from [NVIDIA's model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3#multilingual-asr). These are separate publisher evaluations on the named dataset. Whisper Turbo and Apple Speech have no assigned result in this comparison.
- Cleanup uses Artificial Analysis Intelligence Index v4.3.2. [Qwen 0.6B](https://artificialanalysis.ai/models/qwen3-0.6b-instruct) = 5, [Qwen 1.7B](https://artificialanalysis.ai/models/qwen3-1.7b-instruct) = 5, [Qwen 4B Instruct 2507](https://artificialanalysis.ai/models/qwen3-4b-2507-instruct) = 7, and [Qwen 8B](https://artificialanalysis.ai/models/qwen3-8b-instruct) = 6 are AA's non-reasoning estimates. [gpt-oss 20B](https://artificialanalysis.ai/models/gpt-oss-20b) = 9 uses high reasoning. The UI identifies estimates and configuration differences.
- Vision uses MMMU validation. [SmolVLM 256M](https://huggingface.co/HuggingFaceTB/SmolVLM-256M-Instruct#evaluation) = 28.3%, [Qwen3-VL 2B](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct#model-performance) = 53.4%, and [Qwen3-VL 4B](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct#model-performance) = 67.4%. Qwen's values come from its published multimodal table image, not a screen capture.

## Dictionary

The word list has a search toolbar, an always-visible Add row and lightly divided editable word/context rows. Learned source spellings appear below the word. Removing an entry asks for confirmation. Draft, explicit Save, exact Markdown, search and conflict behavior remain in WritingEditor.

## Verification

Run `bash scripts/test.sh`, package through `bash scripts/build-app.sh`, and run the canonical executable's `--verify-models-window`, `--verify-local-models`, `--verify-native-speech`, `--verify-writing`, `--verify-credits`, `--verify-api-keys`, `--verify-settings-sidebar` and `--verify-build` checks. Preview preferences must be tested sequentially because these probes restore the same isolated domain.

All interface verification uses hidden windows and synthetic state. No live provider inference, model downloads, microphone recording, user dictionary changes, real keys or screen capture. This does not establish pixel-level appearance or physical keyboard behavior.

Verified result: S2T 1.0.1, Build 719. All 420 domain/service tests passed, including benchmark provenance, unknown-result handling, estimate labels and independent bar ratios. All eight packaged checks listed above passed. Logs are in build/settings-refresh-tests.log and build/settings-refresh-verify-*.log. The build script's package privacy and code-signature checks passed. The running app was not restarted.

The current source also required a compile-only fix in PromptDestinationAccess: initializer default arguments use the concrete class name rather than covariant Self. No destination behavior changed.

## Task-page redesign, September 21

The benchmark landing page is unchanged. Model settings now opens a task page with provider and model choices together. Model, connection and advanced controls no longer open additional child pages. Back returns to Model settings, and browsing local models from a task returns to that task.

Provider/model/host/response choices use native dropdowns. Custom model IDs appear only after choosing Custom model ID and have an explicit Save action. Return saves; Escape, leaving the field and navigation preserve the draft without activating it. Model drafts survive a settings refresh. Model selectors include every supplied catalog entry, with duplicate model IDs removed, instead of truncating the list to three suggestions. Hosting, reasoning, speed, extra cleanup and Codex connection options expand in place with short explanations.

A missing key has a Set up API key action. S2T stays selectable when its authenticated catalog is empty; the page preserves the saved model and offers setup and refresh actions. This does not bypass catalog authorization or claim that a provider is operational. Missing local installations identify the saved model and link to Local models. Unsupported hardware and insufficient memory remain real restrictions.

Verification uses isolated preferences, mocked credits/providers and never-shown AppKit windows. No real keys, inference, microphone, screen capture or running-app restart.

Verified in canonical S2T 1.0.1 Build 770. All 444 service/domain tests passed. The packaged `--verify-models`, `--verify-models-window`, `--verify-local-models`, `--verify-credits`, `--verify-api-keys`, `--verify-writing`, `--verify-settings-sidebar` and `--verify-build` checks each exited successfully. Checks cover inline model/provider visibility, explicit custom saving, unsaved draft retention, custom ID restoration, empty S2T catalogs, complete supplied speech choices, task-aware Local navigation, key setup navigation, capability refresh after Save, narrow layouts and theme inheritance. Live provider availability and pixel-level appearance were not tested. The running app was preserved. Detailed exit statuses are in `build/models-redesign-results.json`.


## Direct configuration, September 22

The benchmark landing remains unchanged. Model settings opens directly into the configuration screen. A persistent native task bar switches between Speech, Cleanup, Vision and Local, and Back returns directly to Models. This replaces the task list and previous task-parent navigation.

Provider and model selectors stay together. A compact account row states whether a key is needed, saved, being checked or needs attention. Its action opens that provider's existing key editor. Missing keys and an empty S2T catalog do not disable provider setup. Account and speech-catalog updates preserve custom drafts. Codex default is available without a local catalog.

Local task filters and Install, Use, Details, Repair and Pause actions now use native controls consistent with the rest of model settings. Unsupported memory and hardware have explicit explanations. The application still rejects unavailable installations and unauthorized S2T models.

Hidden layout checks cover the persistent task bar at 420 and 600 points, unchanged containing-window height, provider setup navigation, default Codex selection and matching local action styling. Benchmark content remains mounted and receives its size from the settings window, preventing task changes from shrinking that window.

Verified in canonical S2T 1.0.1 Build 777. All 447 service/domain tests passed. All nine packaged checks passed: models, models-window, local-models, native-speech, credits, api-keys, writing, settings-sidebar and build. The executable remained unchanged throughout verification, and its identity matches bundle metadata and the menu label. Native task selection follows both direct clicks and navigation from other controls. The build script passed privacy and signature checks. Results are in `build/models-workspace-results.json`, with corresponding `models-workspace-verify-*.log` files. Live provider inference and pixel-level appearance were not tested. The running process and real key drafts were left untouched.
