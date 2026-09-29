# Provider model submenus, September 25

The single Models page keeps its separate S2T/personal provider selector. Each Model menu groups models under native provider submenus. Speech uses OpenRouter, AssemblyAI, Local and xAI; cleanup and image descriptions offer the providers applicable to those tasks, including personal Codex. Opening a submenu does not change settings. Selecting a leaf updates that task and its provider, preserving its funding route. Local choices switch to the local connection and never consume S2T credits.

OpenRouter has six speech recommendations, six cleanup recommendations and five image recommendations, followed by Custom model ID. An existing selected model remains accessible even when outside the shortlist. The long More models catalog is removed. Fixed S2T catalogs may provide fewer entries; menu grouping never bypasses the authenticated catalog. Custom S2T IDs use OpenRouter syntax and remain subject to existing authorization. Non-OpenRouter models, installed local models, macOS language labels, custom endpoints and the local library retain their existing behavior.

Models uses advertised capability metadata for reasoning visibility and levels. Unknown models and models without adjustable efforts hide that row. Codex uses its own advertised reasoning and fast-tier metadata. Asynchronous OpenRouter capability updates alter the row in place. Local installation updates refresh native menu contents without rebuilding unrelated editors. Saved task/model options and custom drafts remain independent. Existing request serialization is unchanged.

## Recommendation evidence and cost limits

On September 25 the public OpenRouter catalog confirmed the text/image shortlist IDs and image modalities. Published prices per million input/output tokens were GPT-6 Luna $0.10/$0.50; Gemini 3.8 Flash $0.75/$3.75; Gemini 3.1 Flash Lite $0.25/$1.50; Claude Haiku 4.5 $1/$5; and Grok 4.6 $2/$6. Long-context tiers, selected hosts and S2T margins may change the total. The GPT-OSS 120B shortcut retains the existing Cerebras host. Speech recommendations use the bundled September 21 public catalog and benchmark data. These are a curated set of alternatives, not a measured ranking of dictation cleanup quality. No paid inference or real credentials were used.

## Verification

Run `bash scripts/test.sh`, package with `bash scripts/build-app.sh`, then verify the canonical executable with `--verify-models-window`, `--verify-local-models`, `--verify-models`, `--verify-credits`, `--verify-jev`, `--verify-api-keys`, `--verify-settings-top-bar`, `--verify-prompt-mode`, `--verify-recording-startup` and `--verify-build`. Run preview checks sequentially because they share isolated preferences.

The Models probe invokes actual nested NSMenuItem actions and checks provider/funding/task isolation, explicit custom saving, unsupported options, saved reasoning, installed-only local choices, live inventory updates, stale action and removed-catalog-model rejection, recording guards and narrow hidden layouts. Existing credit and Prompt checks cover fake-provider dictation success/failure and synthetic delivery. No live microphone, user clipboard, screen capture or running-app restart is used. These checks do not establish pixel-level appearance or live service quality.

Verified canonical **S2T 1.0.1 · Build 879**. All 459 service/domain tests and all ten packaged checks listed above passed. The package lock protected the canonical bundle throughout verification; executable SHA-256 was `8501e0d2846a2e24cc9da9a82a0c639bced850284e3829fa1c09691930089a37` before and after. The package privacy and signature checks passed. The temporary fixture app was removed, no verification logs were retained, and the running app was preserved.

## xAI visibility correction

The initial grouping omitted xAI whenever the selected S2T catalog had no xAI entries and always omitted it for S2T image descriptions. xAI now remains visible in all three Model menus. Authorized S2T speech/cleanup models come directly from the current catalog; unavailable known models are disabled with a personal-key explanation. Use xAI API key is an explicit connection action and affects only that task. The native S2T image transport remains OpenRouter-only, while direct xAI vision uses the personal xAI connection. No provider deployment, funding change or real key access is part of this fix.

The Models regression now covers the bundled catalog and an empty authenticated catalog with S2T selected for every task. It asserts visible xAI submenus, disabled unsupported leaves, the explicit personal-key action, credential isolation and unchanged other tasks/credit model settings. Existing populated-catalog and removed-authorization fixtures retain their checks.

Verified this correction in canonical **S2T 1.0.1 · Build 881**. All 459 service/domain tests passed, followed by packaged Models, Local models, credits, API keys, recording startup/delivery and build-identity checks. The package lock protected the executable during the six checks; SHA-256 was `2e738778decc1f015011590fdaa2329c914a3637762adefb9f28f2c3cf1d92e3`. No real xAI credentials or inference, screen capture, persistent verification logs or running-app restart were used.
