# S2T

S2T is a native macOS menu bar app for dictation. Hold a shortcut to speak, or tap to start and finish. S2T transcribes your audio, optionally cleans up the text, and inserts it into the active app.

Requires macOS 14 or later. Provider usage can be charged to your own API accounts, run through local models and endpoints, or paid with prepaid S2T credits for routes offered by the credit service.

## Get started

Build the app using the instructions below, then open `build/S2T.app`. For a packaged DMG, drag S2T into Applications before opening it.

1. Open the menu bar menu and choose Dictation setup to grant Microphone and Accessibility access.
2. Under Models & API keys, configure Speech to text and Text cleanup. Choose personal provider billing, S2T credits, or local processing for each task, then save the required key.
3. Test your shortcut, focus a text field, and dictate. Fn is the default shortcut. Hold-to-talk and tap-to-toggle can be enabled independently.

AssemblyAI is the default direct transcription provider. Direct speech options also include OpenRouter audio models, xAI Grok voice models, and local endpoints or managed local models. Text cleanup supports OpenRouter, xAI Grok, Codex CLI, and local endpoints or managed local models. OpenRouter can pin a hosting endpoint such as Cerebras when that endpoint is available for the selected model. Verbatim mode skips cleanup. See [local endpoint setup](docs/local-endpoints.md).

OpenRouter model IDs and hosting endpoints are separate settings. The default GPT-OSS 120B preset uses the `cerebras/fp16` endpoint. S2T credits loads its available speech and cleanup routes from the service catalog, so its choices can differ from direct provider choices.

Optional Jev cleanup is under Settings → Models → Text cleanup. Choose S2T credits with your existing S2T key, direct TypeSafe, or direct OpenRouter with Jev 1.13 or Jev latest, then choose a preliminary dictionary/filler pass or let Jev finish simple transcripts without the normal cleanup model. It is off by default, bills the selected S2T or provider account, and falls back to normal cleanup on uncertainty or failure. See [Jev setup and verification](docs/verification/jev-cleanup.md).

## App behavior

- Choose a microphone explicitly, or use Automatic to prefer the built-in microphone and avoid Bluetooth inputs.
- Choose Bottom, Around Notch, Around Input, or Bezel recording indicators under Appearance.
- Edit your instructions and dictionary in Settings → Writing.
- Use Last dictation to recover or copy the latest result.

Completed dictation is inserted through Unicode text events and then copied to the clipboard. If cleanup fails, S2T delivers the original transcript and reports the failure. Delivery waits while a menu is open and can be cancelled before insertion.

Around Input detects the active field using Accessibility roles and geometry. It does not capture the screen. Dictionary learning can briefly observe corrections in the receiving nonsecure field after successful delivery.

## Privacy and credentials

Provider credentials are stored in macOS Keychain. Audio and text are sent to the providers you select. Local endpoints send requests to your configured servers without cloud fallback.

Optional clipboard context keeps up to 50 text copies for 48 hours in encrypted local storage, with its encryption key in Keychain. Clipboard references are resolved locally through placeholders. You can disable capture or clear history from the app.

Do not commit provider keys, recordings, local databases, or personal dictionary and prompt files.

Local environment files, deployment overrides, cloud CLI state, and audit captures are ignored. The shared Cloudflare configuration uses demo mode; keep account-specific deployment settings in the ignored `billing-local/wrangler.local.jsonc`. See the [publication checks](docs/publishing.md) before pushing or making the repository public.

## Build and verify

Install Xcode with a Swift 6 toolchain. Swift Package Manager resolves the pinned Glur dependency.

```sh
bash scripts/test.sh
bash scripts/build-app.sh
open build/S2T.app
```

The canonical development app is `build/S2T.app`. Each packaging run assigns a new compiled build identity.

Capture-free checks are available in the packaged executable:

```sh
build/S2T.app/Contents/MacOS/S2T --verify-build
build/S2T.app/Contents/MacOS/S2T --verify-onboarding
build/S2T.app/Contents/MacOS/S2T --verify-api-keys
build/S2T.app/Contents/MacOS/S2T --verify-jev
build/S2T.app/Contents/MacOS/S2T --verify-glow
build/S2T.app/Contents/MacOS/S2T --verify-input-outline
```

Verification uses isolated fixtures where applicable. These checks do not establish physical shortcut behavior, live provider compatibility, or pixel-level appearance across apps.

To build the app and package a universal DMG and ZIP using the saved keyboard installer design:

```sh
bash scripts/package-beta.sh
```

The installer keeps the approved keyboard background, 72-point app icon, and Applications shortcut. Its editable sources and layout are documented in [the installer design](docs/installer-design.md). `scripts/build-app.sh` builds only the app; it does not create a DMG.

Packages are written under `build/releases`. Local beta signing is not Developer ID signing or notarization. See [the beta guide](docs/BETA-READ-ME.txt).

## Repository layout

- `Sources/` and `Tests/` contain the native app, shared logic, and tests.
- `Resources/` and `Logo/` contain app resources and artwork.
- `scripts/` contains build, packaging, and verification helpers.
- `docs/` contains implementation notes and historical verification reports.
- `billing-local/` contains the transactional prepaid credit service and wallet. Read its [implementation and operating limits](billing-local/README.md), [setup guide](billing-local/SETUP.md), and dated [live deployment record](billing-local/LIVE.md). The live record documents specific checks and releases; it is not a continuous uptime or provider-balance attestation.

The separate website checkout, generated design studies, and build artifacts stay outside this repository. Website export helpers require that local checkout and its reference assets.

## Third-party code

S2T uses [Glur](https://github.com/joogps/Glur) for progressive backdrop blur. Third-party license notices are retained in the source and resources.
