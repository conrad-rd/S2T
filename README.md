# S2T

S2T is a native macOS menu bar app for dictation. Hold a shortcut to speak, or tap to start and finish. S2T transcribes your audio, optionally cleans up the text, and inserts it into the active app.

Requires macOS 14 or later. Provider API usage is billed to your own accounts.

## Get started

Build the app using the instructions below, then open `build/S2T.app`. For a packaged DMG, drag S2T into Applications before opening it.

1. Open the menu bar menu and choose Dictation setup to grant Microphone and Accessibility access.
2. Under Models & API keys, configure Speech to text and Text cleanup. Paste and save the keys for your selected providers.
3. Test your shortcut, focus a text field, and dictate. Fn is the default shortcut. Hold-to-talk and tap-to-toggle can be enabled independently.

AssemblyAI is the default transcription provider. ElevenLabs, OpenRouter, and local transcription endpoints are also supported. Text cleanup supports OpenRouter, Cerebras, and local endpoints. Verbatim mode skips cleanup. See [local endpoint setup](docs/local-endpoints.md).

OpenRouter model IDs and hosting endpoints are separate settings. The Cerebras preset uses `openai/gpt-oss-120b` with the `cerebras/fp16` endpoint.

## App behavior

- Choose a microphone explicitly, or use Automatic to prefer the built-in microphone and avoid Bluetooth inputs.
- Choose Bottom, Around Notch, Around Input, or Bezel recording indicators under Appearance.
- Edit the system prompt and dictionary through their Finder actions in Models & API keys.
- Use Last dictation to recover or copy the latest result.

Completed dictation is inserted through Unicode text events and then copied to the clipboard. If cleanup fails, S2T delivers the original transcript and reports the failure. Delivery waits while a menu is open and can be cancelled before insertion.

Around Input detects the active field using Accessibility roles and geometry. It does not capture the screen. Dictionary learning can briefly observe corrections in the receiving nonsecure field after successful delivery.

## Privacy and credentials

Provider credentials are stored in macOS Keychain. Audio and text are sent to the providers you select. Local endpoints send requests to your configured servers without cloud fallback.

Optional clipboard context keeps up to 50 text copies for 48 hours in encrypted local storage, with its encryption key in Keychain. Clipboard references are resolved locally through placeholders. You can disable capture or clear history from the app.

Do not commit provider keys, recordings, local databases, or personal dictionary and prompt files.

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
- `billing-local/` contains an experimental billing service with its own [setup and limitations](billing-local/README.md). It is not a production billing deployment.

The separate website checkout, generated design studies, and build artifacts stay outside this repository. Website export helpers require that local checkout and its reference assets.

## Third-party code

S2T uses [Glur](https://github.com/joogps/Glur) for progressive backdrop blur. Third-party license notices are retained in the source and resources.
