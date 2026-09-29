# Local models

Settings → Models offers Local models as one provider for Speech, Cleanup and Vision. It lists installed models for the selected task, labels Apple languages as managed by macOS, and includes a Custom endpoint option with editable model ID and full endpoint URL. Managed downloads use S2T’s private runtime without an editable server address. OpenRouter hosting is editable below its quick choices for cleanup and vision; speech hosting remains Automatic because OpenRouter ignores speech host pins.

Manage local models opens an On this Mac inventory before the three task choices. The inventory separates completed downloads, macOS language assets and incomplete downloads, shows measured storage and approximate download progress, and offers confirmed Move to Trash for unused S2T downloads. Verification injects removal inside an isolated fixture and never touches the user’s Trash. Choose opens a compact model list; selecting a model opens its details and Install or Use action. Search and sorting stay in the list, and the published comparison opens only on request from model details. Install downloads the runtime and model into `~/Library/Application Support/S2T/LocalModels`. Use selects an installed model. Repair repeats runtime setup and resumes missing model downloads. Pausing preserves downloaded pieces. No read-aloud feature is included.

The runtime requires Apple Silicon and macOS 26. Package versions, Python 3.12.14, the uv archive hash and model revisions are pinned. The app does not change the user's Python installation. Model inputs stay in the worker's memory. Only installation needs internet access. The worker binds an ephemeral loopback port with a random private URL, loads one model at a time, limits its reusable allocation cache to 128 MiB and unloads the model after two idle minutes. Quit, cancellation and parent exit stop inference. Existing cleanup error handling still delivers the original transcription if cleanup fails.

## Verification

- `bash scripts/test.sh`: 242 domain/service tests.
- `--verify-local-models`: hidden native table/navigation, task filters, isolated installation markers, provider-specific selection and recording guards. No actual installation through preview controls.
- `--verify-models-window`: existing model settings and light/dark inheritance.
- `--verify-build`: compiled identity and bundle metadata.
- `scripts/verify-local-worker.py`: all catalog models, generated text, synthesized WAV and a generated two-shape PNG. Uses the isolated `build/local-verification` directory and the pinned environment. No real screen, microphone, credentials or clipboard.
- `--verify-local-runtime --local-fixture-root <directory>`: packaged Python worker, native URLSession speech/cleanup, cancellation and restart. Requires a fixture marker, generated WAV, runtime and installed models in that directory.

The six-model fixture produced the following single-run timings on the development Mac. Each model's first request includes loading; the first process request also includes shared library initialization. These are not directly comparable general benchmarks.

| Model | First request | Repeated request |
| --- | ---: | ---: |
| Qwen3 0.6B | 11.413 s | 0.125 s |
| Qwen3 1.7B | 0.710 s | 0.172 s |
| Qwen3 ASR 0.6B | 1.241 s | not measured |
| Parakeet TDT v3 | 3.332 s | not measured |
| SmolVLM 256M | 6.208 s | not measured |
| Qwen3 VL 2B | 2.347 s | not measured |

Both speech models returned the synthesized sentence exactly. SmolVLM described the blue square but missed the red circle; Qwen3 VL described both. Both cleanup models returned the requested text. These fixtures establish working inference, not broad accuracy. UI quality/speed ratings and memory budgets remain labeled estimates. Measured model download sizes are rounded in the catalog.

The idle test uses the same unloading code with a five-second interval. MLX active allocations fell from 1,782,299,298 to 352,926 bytes after unloading Qwen3 VL. This measures MLX allocations, not the entire Python process. The production interval is 120 seconds, checked every five seconds.

## Upstream references

- [MLX Audio](https://github.com/Blaizzy/mlx-audio)
- [MLX LM](https://github.com/ml-explore/mlx-lm)
- [MLX VLM](https://github.com/Blaizzy/mlx-vlm)
- [uv releases](https://github.com/astral-sh/uv/releases/tag/0.12.15)

Each table row links to its model card. `Resources/LocalModels/catalog.json` records model revisions and licenses. Verification artifacts and downloaded models stay under build and are not included in the application bundle.

## Catalog expansion, September 16

The catalog has 12 entries: four speech models, five cleanup models and three image models. Added Qwen3 ASR 1.7B, OpenAI Whisper Turbo, Qwen3 4B Instruct, Qwen3 8B, Qwen3 VL 4B and OpenAI gpt-oss 20B. Model revisions and file sizes come from their pinned Hugging Face metadata. Speed, quality and memory budgets remain estimates, not comparative benchmarks.

GPT-oss uses Harmony output. `response_text.py` extracts only the final channel, rejects absent/empty final answers and leaves ordinary text-model output unchanged. `scripts/test-local-response.py` checks converted and original Harmony token names, incomplete reasoning, empty answers and plain text. Native model actions and inference reject models whose estimated memory budget exceeds the Mac's physical memory. GPT-oss 20B has a 20 GB budget and an approximately 13.79 GB download in this conversion.

OpenAI gpt-oss and Whisper are downloadable OpenAI models. They are labeled by their actual model names, without implying that the ChatGPT service's proprietary models are available for download. See [OpenAI's open-weight model documentation](https://help.openai.com/en/articles/11870455) and [Whisper](https://github.com/openai/whisper).

Expansion verification passed for all six additions using the pinned runtime and generated fixtures. Qwen3 4B cleanup took 0.216 seconds warm, Qwen3 8B took 0.319 seconds warm, and gpt-oss 20B took 0.687 seconds warm. First-request times included model loading and are not direct speed comparisons. Both added speech models returned the expected sentence. Qwen3 VL 4B identified both generated shapes. GPT-oss returned final-channel text without Harmony markers. Its active MLX allocations dropped from 13,763,332,248 bytes to 24 bytes after idle unloading. These are controlled fixture results, not broad accuracy or whole-process memory measurements.

All 242 service/domain tests and six independent response-format fixtures passed. Packaged hidden Local controls, provider selection, native URLSession speech/cleanup, cancellation/restart and build metadata checks passed. No screen capture, microphone capture or real credentials were used.

## Catalog navigation

The Local summary has one Choose action for each task. The catalog keeps a native task popup beside search and sorting. Selecting a model opens a separate detail page with Install, Use, Repair and source actions as applicable. Back returns to the catalog, then to the task summary. The hidden Local probe checks navigation, task filtering, narrow layouts, comparison access and action guards without opening a visible window.

## Provider continuation, September 25

`--verify-models-window` exercises Local models with an empty and populated isolated inventory, task filtering, automatic selection of an installed compatible model, custom URL/model restoration, host validation, stale edit rejection and recording guards. `--verify-local-models` checks inventory layout, incomplete downloads and confirmed removal at 420 points. The overview observes inventory changes directly, including macOS language discovery.

Downloaded model sizes and memory requirements are approximate. Apple language storage is managed outside S2T. Custom endpoints require a running compatible server; no model is downloaded by choosing that option. Runtime inference checks require separately installed fixture models and do not establish broad model quality or live dictation latency.

S2T 1.0.1 Build 865 passed the packaged Models, Local, Apple Speech and build-identity checks. The preceding build also passed toolbar, API-key, credit/recovery, sidebar and isolated text-delivery checks; the final rebuild only corrected the Apple Speech probe’s Download-button expectation and labels. All six local response-format fixtures passed. The full `bash scripts/test.sh` run was blocked at compilation by existing DictionaryTests calls using an `insertionSelection` argument absent from DictionaryObservation. No live provider requests or model inference were performed for this continuation.
