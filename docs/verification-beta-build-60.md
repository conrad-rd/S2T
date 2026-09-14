# S2T 1.0.1 early beta, build 60

Share `S2T-1.0.1-beta-build-60-universal.zip` from `build/releases`. The ZIP is 3,713,655 bytes and includes S2T.app and tester instructions. Requires macOS 14 or later. The executable contains arm64 and x86_64 architectures.

Built from isolated source `beta-source-20260913-131513` because the working sources changed during compilation. Source hashes are recorded in that snapshot's `build/source-manifest.json` and remained unchanged during the build, excluding the generated BuildIdentity.

Verification passed

- 103 service and domain tests, zero failures.
- Packaged build identity, model settings, mock API keys, isolated clipboard history, menu highlights, notch placement, and input-outline checks.
- Hidden glow structural checks on two displays, including meter levels 0.3 and 0.55. Initial notch and glow runs detected foreground application changes; their repeat runs passed.
- ZIP integrity, extracted app signature, universal architectures, and matching executable, bundle and menu build identity.
- Both executable architectures link only to system libraries and frameworks.

Limits

The app has an ad hoc signature. No Developer ID Application certificate was available, so it is not notarized. Testers must use the documented macOS Privacy & Security exception on first launch. No Gatekeeper bypass or system security setting was applied by the agent.

No live provider requests were made with user credentials. Physical Intel Macs, macOS 14 hardware, first-launch permissions on a clean Mac, and pixel-level cross-app blur were not tested. No screen capture or Raycast interaction was used.

SHA-256: `507669c4c0d1c5c091336c5e76f0f2b72499c40457bd4c9a45e8323d8a592876`
