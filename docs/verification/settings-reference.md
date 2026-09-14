# Settings reference update

2026-09-12

The supplied screenshot informed the inset rounded sidebar, search field, neutral selection, compact 46-point settings rows, pale cards, and small native controls. Existing microphone, activation, output, provider, model, and appearance controls retain their bindings. Search filters navigation by page names and related settings terms. Back and forward keep page history. Branding remains empty.

`bash scripts/test.sh` passed all 36 tests. `bash scripts/build-app.sh` produced the signed app in `build/S2T.app`.

The packaged executable rendered the actual SwiftUI views with `--render-previews build/previews-settings-reference`. Inspected General, API keys, Models, Appearance, and Dictation. General also rendered at the minimum 780 by 630 window size; lower recording controls remain inside the vertical scroll view. The normal 860 by 820 layout displays all General controls.

These are offscreen renders. Native controls appear inactive and the borderless preview omits the live window's traffic lights. Live navigation, window chrome, and scrolling were not exercised. No provider requests or interactions with Raycast were performed for this visual update.
