import AppKit

@MainActor enum SettingsProbe {
    static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = NSWorkspace.shared.frontmostApplication
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let savedProvider = preferences.object(forKey: "processingProvider")
        preferences.removeObject(forKey: "processingProvider")
        defer { preferences.set(savedProvider, forKey: "processingProvider") }
        let state = AppState(preview: true)
        guard state.processingProvider == .openRouter else { throw failure("OpenRouter is not the default.") }
        let originalMode = state.mode
        state.mode = .clean
        let originalProvider = state.processingProvider
        let originalStrength = state.glowStrength
        let originalHold = state.holdEnabled
        let window = SettingsWindow.make(state: state)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            state.cancel()
            state.processingProvider = originalProvider
            state.mode = originalMode
            state.glowStrength = originalStrength
            state.holdEnabled = originalHold
            window.close()
            if let previous, previous.bundleIdentifier != "com.raycast.macos" { previous.activate(options: []) }
        }
        let root = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        try await Task.sleep(nanoseconds: 400_000_000)
        for page in [AppPage.settings, .connections, .models, .appearance] {
            for _ in 0..<20 {
                if let button = find("navigation.\(page.rawValue)", in: root) {
                    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                if state.page == page { break }
            }
            guard state.page == page else { throw failure("Cannot navigate to \(page.rawValue).") }
            try await Task.sleep(nanoseconds: 200_000_000)
            try capture(window: window, to: directory.appendingPathComponent("\(page.rawValue.lowercased().replacingOccurrences(of: " ", with: "-" )).png"))
            print("\(page.rawValue): navigation and window capture PASS")
            if page == .connections {
                state.assemblyKey = "fixture-assembly"
                state.routerKey = "fixture-router"
                state.cerebrasKey = "fixture-cerebras"
                try await Task.sleep(nanoseconds: 100_000_000)
                guard state.canRecord, state.processingProvider == .openRouter else { throw failure("OpenRouter is not ready.") }
                guard find("settings.cerebrasKey", in: root) == nil, find("settings.routerKey", in: root) != nil else { throw failure("Default provider key is missing.") }
                guard let save = find("settings.save.openrouter", in: root),
                      AXUIElementPerformAction(save, kAXPressAction as CFString) == .success else { throw failure("Cannot click Save API key.") }
                try await Task.sleep(nanoseconds: 100_000_000)
                guard state.savedKeyAccounts.contains("openrouter") else { throw failure("Save did not confirm.") }
                try capture(window: window, to: directory.appendingPathComponent("saved-key.png"))
                state.routerKey = "edited-fixture-router"
                guard !state.savedKeyAccounts.contains("openrouter") else { throw failure("Editing retained a stale saved confirmation.") }
                guard let item = find("provider.cerebras", in: root) ?? findProvider("Cerebras", in: root),
                      AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { throw failure("Cannot choose Cerebras.") }
                try await Task.sleep(nanoseconds: 150_000_000)
                guard find("settings.cerebrasKey", in: root) != nil, find("settings.routerKey", in: root) == nil else { throw failure("Key fields do not follow provider choice.") }
                state.assemblyKey = ""
                state.routerKey = ""
                state.cerebrasKey = ""
                try capture(window: window, to: directory.appendingPathComponent("cerebras-keys.png"))
                print("Default OpenRouter, selected key field, and save confirmation: PASS")
            }
            if page == .models {
                guard let item = find("provider.cerebras", in: root) ?? findProvider("Cerebras", in: root),
                      AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { throw failure("Cannot choose Cerebras.") }
                try await Task.sleep(nanoseconds: 150_000_000)
                guard state.processingProvider == .cerebras, state.processingModel == "qwen-3.8-27b" else { throw failure("Provider selector did not load Cerebras settings: \(state.processingProvider?.rawValue ?? "none"), \(state.processingModel).") }
                state.assemblyKey = "fixture-assembly"
                state.routerKey = ""
                state.cerebrasKey = "fixture-cerebras"
                guard state.canRecord else { throw failure("Cerebras still requires an OpenRouter key.") }
                state.assemblyKey = ""
                state.cerebrasKey = ""
                try capture(window: window, to: directory.appendingPathComponent("cerebras-models.png"))
                print("Cerebras selector and credentials routing: PASS")
            }
        }
        guard let slider = find("glow.intensity", in: root),
              AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString, NSNumber(value: 1.1)) == .success else { throw failure("Cannot move the glow slider.") }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard abs(state.glowStrength - 1.1) < 0.02 else { throw failure("Slider did not update the setting.") }
        print("Native slider value: PASS")
        guard let preview = find("glow.preview", in: root), AXUIElementPerformAction(preview, kAXPressAction as CFString) == .success else { throw failure("Cannot click the glass Preview button.") }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard state.phase == .preview else { throw failure("Preview button did not run.") }
        print("Glass Preview button: PASS")
    }

    private static func capture(window: NSWindow, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("Window capture failed.") }
    }

    private static func find(_ id: String, in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value)
        if value as? String == id { return root }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let result = find(id, in: child) { return result }
        }
        return nil
    }

    private static func findProvider(_ title: String, in root: AXUIElement) -> AXUIElement? {
        var role: CFTypeRef?
        var name: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &name)
        if [kAXRadioButtonRole, kAXButtonRole].contains(role as? String ?? ""), name as? String == title { return root }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let result = findProvider(title, in: child) { return result }
        }
        return nil
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SettingsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
