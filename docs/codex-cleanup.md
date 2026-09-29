# Codex text cleanup

For Codex text cleanup, open Models → Text cleanup → Codex. Install the current Codex CLI and sign in once with `codex login`. S2T uses that login without copying its credentials into S2T. Codex uses OpenAI cloud inference, so this option is not offline.

Codex settings accept an executable path, with a blank path selecting an installed CLI automatically. S2T checks Homebrew locations and its process PATH. It resolves the npm launcher to its native executable. Use `default` for the CLI's built-in default model, or enter an explicit model ID.

Each Codex request runs `codex exec` in a private temporary directory with `--ephemeral`, `--ignore-user-config`, read-only sandboxing, disabled interactive approvals, and disabled shell, browser, computer-use, plugin and app features. It passes dictated material on stdin. It does not inherit project instructions or your Codex configuration. Temporary request files are removed when the request ends. Cancellation stops the running process, and requests time out after two minutes.

A failed cleanup delivers the original transcript. S2T never retries cleanup with a different provider automatically.

The integration follows the official [non-interactive mode documentation](https://learn.chatgpt.com/docs/non-interactive-mode) and [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli). Model access and usage limits depend on the signed-in account.

Verification uses mock HTTP transport, a fixture CLI executable, isolated preferences and pasteboards, and injected text delivery. It does not use real credentials, real screen captures, or a live model server. These checks establish request routing and app behavior, not recognition quality or account access.
