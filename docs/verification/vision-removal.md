# Vision removal

Vision model selection and AI image descriptions were removed from Models, Local models, model comparison, Prompt mode, the menu, and the benchmark app. The local catalog no longer offers vision downloads. The description APIs, Codex image input, local image inference, and billed image requests were removed.

Prompt mode still saves and attaches screenshots with numbered inline references. It prepares those references while text cleanup runs. Previously saved image-description preferences are ignored. Existing screenshot files and downloaded model files are not deleted.

Verification on 2026-09-26, including packaged release Build 904 at `build/S2T.app`:

- 55 targeted Swift tests passed for reference matching, local model catalogs, benchmark data, Codex cleanup, routing options, and writing.
- 25 Node tests passed for the model catalog, gateway, and model choices. An image-description request is rejected before provider dispatch.
- The hidden Models and Local models checks passed in the packaged app, including provider selection, persisted cleanup settings, and local task filters. The rendered Models page was inspected and contains only speech and cleanup settings.
- The packaged prompt completion probe passed with the old description setting enabled. It made one speech request and one cleanup request, delivered text followed by two unchanged PNG attachments, and made no image request.

The app probes use isolated preferences, generated images and audio, an isolated clipboard, and injected delivery. They do not capture the user's screen or send provider requests. The backend source is updated; no service deployment was performed.

To rerun the app checks after building:

```sh
build/S2T.app/Contents/MacOS/S2T --verify-models-window
build/S2T.app/Contents/MacOS/S2T --verify-local-models
build/S2T.app/Contents/MacOS/S2T --verify-prompt-mode --benchmark-delivery
```
