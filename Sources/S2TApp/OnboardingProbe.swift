import AppKit
import S2TCore

@MainActor enum OnboardingProbe {
    static func run() async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "Onboarding", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        // The simulated keyboard service only sees changes after notification.
        for original: Int? in [nil, 0, 1, 2, 3] {
            let defaults = UserDefaults(suiteName: "com.s2t.verification.fn.\(UUID().uuidString)")!
            var saved = original
            var live = original
            var writes = 0
            var failWrites = false
            let fn = FnSystemAction(defaults: defaults, read: { saved }, write: { value in
                guard !failWrites else { return false }
                saved = value; writes += 1; return true
            }, notify: { live = saved })
            try check(fn.begin() && live == 0, "Fn must update the running service, not only its stored preference")
            let firstWrites = writes
            try check(fn.begin() && writes == firstWrites, "Polling must not rewrite system preferences")
            failWrites = true
            fn.restore()
            try check(defaults.bool(forKey: "fnOverrideHasBackup"), "Failed restoration must retain the original setting")
            failWrites = false
            fn.restore()
            try check(saved == original && live == original, "Quitting must restore the running service and stored setting")
            try check(!defaults.bool(forKey: "fnOverrideHasBackup"), "Successful restoration must finish the transaction")
            _ = fn.begin()
            saved = 3; live = 3
            try check(!fn.begin() && live == 3, "Polling must respect a later manual keyboard change")
            fn.restore()
            try check(live == 3, "Quitting must preserve a newer manual choice")
        }
        let defaults = UserDefaults(suiteName: "com.s2t.verification.fn.\(UUID().uuidString)")!
        var value: Int? = 2
        let first = FnSystemAction(defaults: defaults, read: { value }, write: { value = $0; return true }, notify: {})
        _ = first.begin()
        let restarted = FnSystemAction(defaults: defaults, read: { value }, write: { value = $0; return true }, notify: {})
        _ = restarted.begin()
        restarted.restore()
        try check(value == 2, "Restart after a crash must retain the pre-S2T Fn setting")
        try check(AppState.needsInstallation(path: "/Volumes/S2T/S2T.app"), "Disk-image launch must not request permissions")
        try check(AppState.needsInstallation(path: "/private/var/folders/test/AppTranslocation/id/d/S2T.app"), "Translocated copy must direct installation first")
        try check(!AppState.needsInstallation(path: "/Applications/S2T.app"), "Installed app must allow setup")
        let shortcut = ActivationShortcut(verification: true)
        defer { shortcut.stop() }
        var actions: [ActivationAction] = []
        var listening = false
        shortcut.onAction = { action in
            actions.append(action)
            if action == .start { listening = true }
            if action == .stop || action == .cancel { listening = false }
        }
        shortcut.isListening = { listening }
        shortcut.configure(key: .function, hold: true, tap: false)
        shortcut.refresh()
        func keyEvent(_ code: Int64, _ flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(source: nil)!
            event.type = .flagsChanged
            event.flags = flags
            event.setIntegerValueField(.keyboardEventKeycode, value: code)
            return event
        }
        shortcut.beginTest()
        try check(shortcut.isTesting, "Shortcut test must start without microphone or provider keys")
        try check(!shortcut.receive(type: .flagsChanged, event: keyEvent(63, .maskSecondaryFn)), "Fn modifier must remain available to combinations")
        _ = shortcut.receive(type: .flagsChanged, event: keyEvent(63, []))
        try await Task.sleep(nanoseconds: 10_000_000)
        try check(shortcut.testPassed && !shortcut.isTesting && actions.isEmpty, "A shortcut test must never dispatch recording actions")
        _ = shortcut.receive(type: .flagsChanged, event: keyEvent(63, .maskSecondaryFn))
        try await Task.sleep(nanoseconds: 10_000_000)
        try check(actions == [.start], "Normal hold must start after testing")
        shortcut.cancelTest()
        _ = shortcut.receive(type: .flagsChanged, event: keyEvent(63, []))
        try await Task.sleep(nanoseconds: 10_000_000)
        try check(actions == [.start, .stop], "Cancelling an inactive test must not interrupt a normal hold")
        shortcut.configure(key: .function, hold: true, tap: true)
        actions = []
        let queuedDown = keyEvent(63, .maskSecondaryFn)
        let queuedUp = keyEvent(63, [])
        queuedDown.timestamp = 1_000_000_000
        queuedUp.timestamp = 2_000_000_000
        _ = shortcut.receive(type: .flagsChanged, event: queuedDown)
        _ = shortcut.receive(type: .flagsChanged, event: queuedUp)
        try await Task.sleep(nanoseconds: 10_000_000)
        try check(actions == [.start, .stop], "Queued hold events must retain their physical duration instead of becoming a tap")
        shortcut.beginTest()
        _ = shortcut.receive(type: .keyDown, event: keyEvent(53, []))
        try check(!shortcut.isTesting && !shortcut.testPassed, "Escape must cancel a shortcut test")
        let state = AppState(preview: true)
        try await HoldEscapeProbe.run()
        state.microphoneAccess = .notDetermined
        state.shortcutAccessGranted = false
        try check(!state.dictationPermissionsReady && state.permissionActionTitle == "Allow microphone…", "First step must request the microphone")
        state.microphoneAccess = .authorized
        try check(!state.dictationPermissionsReady && state.permissionActionTitle == "Enable Accessibility…", "Second permission must be a separate explicit action")
        state.shortcutAccessGranted = true
        try check(state.dictationPermissionsReady && !state.setupReady, "Permissions alone must not complete setup")
        state.microphoneAccess = .denied
        try check(state.permissionActionTitle == "Open Microphone settings…", "Denied microphone must have a recovery action")
        state.microphoneAccess = .restricted
        try check(state.permissionActionTitle == "Microphone access is restricted", "Restricted permission must not offer a futile request")
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        let settings = controller.appearanceWindow
        settings.showDictation()
        try check(settings.showingDictation && settings.dictationPane.superview != nil,
                  "Onboarding must be reachable in hidden Dictation settings")
        state.microphoneAccess = .authorized
        settings.showAPIKeys()
        try check(settings.showingKeys && settings.apiKeysPane.view.superview != nil,
                  "Provider keys must be reachable from Settings")
        settings.showDictation()
        try check(settings.showingDictation && state.dictationPermissionsReady,
                  "Completed permission state must remain available in Dictation settings")
        try check(NSApp.windows.allSatisfy { !$0.isVisible || $0.level != .normal }, "Verification must not show onboarding windows")
        print("Native Fn apply/get functions available: \(NativeFnPreferences.update != nil && NativeFnPreferences.get != nil). Resolved only, never called during verification.")
        print("Onboarding verified: Fn apply/restore/retry/crash recovery, installation guard, permission progression, and hidden Settings navigation. No real permissions, keys, clipboard, or keyboard preferences changed.")
    }
}
