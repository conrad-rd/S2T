# Provider visibility

Settings → Models → Providers contains four independent switches: S2T credits, OpenRouter, xAI and Local. On shows that provider; off hides it throughout the app. All four start on. Each choice is saved independently.

Saved keys, favorites, models and active connections remain intact. A hidden active connection is labeled “Current provider hidden”; choosing a visible provider explicitly changes the connection. The old combined switch is removed.

Run `build/S2T.app/Contents/MacOS/S2T --verify-provider-visibility` after building with `bash scripts/build-app.sh`. The probe operates each native switch, checks that the other three remain available, checks mixed visibility and persistence, and exercises model menus, API keys, sidebar credits, toolbar actions, meetings, writing and usage sources. It uses a never-shown settings window and restores preview preferences afterward.

Set `S2T_PROVIDER_VISIBILITY_ARTIFACTS` to an output directory to render the Providers subsection. `--verify-models-window` checks existing model behavior with every provider visible.
