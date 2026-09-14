# Local image detection and Codex

Text cleanup and Prompt mode image detection have independent provider and model choices. Changing one does not change the other. Existing OpenRouter settings remain selected until you change them.

For local image detection, open Prompt mode → Image model → Local endpoint. Enter the complete OpenAI-compatible chat completions URL and the image-capable model loaded on that server. The default URL is `http://localhost:1234/v1/chat/completions`. Images are sent as PNG data URLs. The server must accept image inputs and return JSON with one description per image. S2T sends no API key, does not query OpenRouter for local model metadata, and does not fall back to a cloud provider. An endpoint on another machine sends the images to that machine.

For Codex text cleanup, open Models & API keys → Text cleanup → Codex CLI. For Codex image detection, open Prompt mode → Image model → Codex CLI. Install the current Codex CLI and sign in once with `codex login`. S2T uses that login without copying its credentials into S2T. Codex uses OpenAI cloud inference, so this option is not offline.

Codex settings accept an executable path, with a blank path selecting an installed CLI automatically. S2T checks Homebrew locations and its process PATH. It resolves the npm launcher to its native executable. Use `default` for the CLI's built-in default model, or enter an explicit model ID. The image choice must support image input. Text cleanup and vision keep separate model IDs but share the executable setting.

Each Codex request runs `codex exec` in a private temporary directory with `--ephemeral`, `--ignore-user-config`, read-only sandboxing, disabled interactive approvals, and disabled shell, browser, computer-use, plugin and app features. It passes dictated material on stdin and reference images as attachments. It does not inherit project instructions or your Codex configuration. Temporary request files are removed when the request ends. Cancellation stops the running process, and requests time out after two minutes.

A failed cleanup delivers the original transcript. A failed image description keeps the saved image and its reference in the prompt. S2T never retries either operation with a different provider automatically.

The integration follows the official [non-interactive mode documentation](https://learn.chatgpt.com/docs/non-interactive-mode) and [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli). Model access and usage limits depend on the signed-in account.

Verification uses generated images, mock HTTP transport, a fixture CLI executable, isolated preferences and pasteboards, and injected text delivery. It does not use real credentials, real screen captures, or a live model server. These checks establish request routing and app behavior, not recognition quality or account access.
