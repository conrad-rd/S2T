# Onboarding and installation

The setup submenu keeps permissions, provider keys, activation settings and local tests together. Permission actions advance from Microphone to Accessibility without opening both prompts together. Returning from System Settings and the two-second refresh update existing menu rows. Setup stays reachable after permissions are granted.

Fn now uses the same Int32 getter/setter pair referenced by the installed macOS KeyboardSettings.appex, TISGetFnUsageType and TISUpdateFnUsageType. The app resolves these private HIToolbox exports at runtime. It also notifies keyboard preference observers. If the exports are unavailable and the setting needs changing, setup explains how to change it in Keyboard settings. An absent preference and its effective original value are backed up separately. Manual changes are respected, and failed restoration retains the backup for another attempt.

The shortcut test consumes no audio and sends no transcription requests. It checks press and release, supports cancellation and timeout, and cannot interrupt a normal hold when it is inactive. A successful key test establishes event delivery only. The user still checks whether macOS also opened emoji.

Normal duplicate launches exit before creating AppState. Disk-image and translocated copies explain installation before permissions or Fn ownership. The first launch introduces the menu without opening a settings window.

The universal DMG contains only the packaged app, an Applications shortcut, the guide, generated background artwork and Finder metadata. scripts/build-dmg.sh authors the layout using ds-store and mounts its local images under build with Finder browsing disabled. It preserves intermediate files and refuses to overwrite an existing output.

## Verification

- bash scripts/test.sh: 116 tests passed.
- --verify-onboarding: fake Fn apply/restore, manual changes, failed restoration, crash recovery, synthetic unposted key events, normal hold after testing, Escape cancellation, permission progression, installation path guards and menu updates.
- --verify-build: compiled identity, packaged metadata and menu label agree.
- Release packaging also runs models, api-keys, clipboard, menu-highlights, notch, input-outline and glow checks. These use isolated state or hidden windows.
- The final DMG is checked for integrity, signature, universal architectures, executable equality, Applications link, guide and Finder layout metadata.

No real keyboard preference changes, microphone recordings, provider requests, Keychain credentials, user clipboard reads, screenshots or screen recordings were used. The Fn exports were resolved but not invoked during verification. Physical Fn/emoji behavior, first-install permission dialogs, visible Finder layout and Gatekeeper on another Mac remain unverified. The beta is ad-hoc signed and is not notarized. A Developer ID identity is not available in this environment.

The Build 91 packaging attempt stopped when the foreground application changed during the glow focus-preservation check. Its structural display checks passed before that check. No application was activated by the verification. The final package reruns the checks without weakening them.
