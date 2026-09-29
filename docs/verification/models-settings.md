# Models settings, September 20

The Models page exposes model ID, hosting, reasoning and speed directly. There is no Advanced disclosure. Three provider buttons distinguish the common S2T credits, personal API key and login routes. Other enables a flat list of the remaining providers and installed local models. Unavailable credit-funded services remain disabled; selecting a direct provider never borrows the S2T key.

Models use up to three suggested buttons and a Custom model ID, without a duplicate model dropdown. The active suggestion is blue and disables the gray custom field. Custom restores the previous custom ID. These choices persist independently for each task, provider and funding route. Providers with fewer supported suggestions show only their available choices. Recognition, hosting and reasoning remain separate settings.

Native and SwiftUI action buttons use white labels on blue or dark neutral glass, with capsule geometry. The sidebar uses the same native rounded plate for hover and selection rather than changing between separately drawn shapes. Page backgrounds still follow the selected window theme.

## Switching workload

`S2T_MODELS_BENCHMARK=1 .build/xcode/debug/S2T --verify-models-window` uses an isolated preview state and hidden window. Each sample includes the navigation action and native layout. It alternates Speech to text/Text cleanup 80 times, then API keys/Models 80 times. Both measurements used the same debug configuration and workload.

| Workload | Before, total | After, total | Before median | After median |
| --- | ---: | ---: | ---: | ---: |
| Model tabs | 2832.5 ms | 74.3 ms | 35.04 ms | 0.89 ms |
| Settings pages | 1652.2 ms | 197.1 ms | 36.99 ms | 2.78 ms |

Tab navigation now changes section visibility without rebuilding all controls. Returning to Models rebuilds only after app state has changed; initial catalog loading is not repeated on every visit. Actual provider/model changes still rebuild the affected form configuration. The cost is retaining the existing controls between visits, which the page already retained for hidden sections. These results do not measure physical input-to-display latency or live provider response time.

## Verification

Run `bash scripts/test.sh`, then `bash scripts/build-app.sh`. Run packaged checks with `build/S2T.app/Contents/MacOS/S2T`: `--verify-models-window`, `--verify-local-models`, `--verify-models`, `--verify-credits`, `--verify-jev`, `--verify-writing`, `--verify-api-keys`, `--verify-settings-sidebar` and `--verify-build`.

The Models check asserts direct visibility, retained control identity across repeated navigation, white foreground configuration in both page themes, fixed button border shapes and editing behavior. ModelChoiceProbe clicks the actual suggestion and Custom controls, checks the model used by app state, restores the previous custom ID after a new app state, and switches recommended providers. Credit checks also cover the 420-point layout. The provider and credit checks exercise native selection actions, unavailable service rejection, independent saved models and outgoing credentials through isolated transports. The sidebar check asserts that hover and selection use the identical native plate, frame and shape. No screen capture, real credentials or live inference is used. Native configuration checks are not pixel-level visual verification.

Verified the canonical S2T 1.0.1 Build 704. All 410 domain tests and all nine packaged checks listed above passed. Concurrent packaging included the model changes; the final canonical app was checked directly and its compiled identity matches the bundle and menu. The running user app was not restarted.
