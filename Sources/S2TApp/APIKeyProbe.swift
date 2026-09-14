import AppKit
import S2TCore

@MainActor enum APIKeyProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true, api: DictationAPI(transport: KeyProbeTransport()))
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        guard !controller.menu.items.contains(where: { $0.identifier?.rawValue == "keys" }),
              let settings = controller.menu.items.first(where: { $0.identifier?.rawValue == "appearance" }),
              let setup = controller.menu.items.first(where: { $0.identifier?.rawValue == "setup" })?.submenu else { throw failure("Keys still have a root menu") }
        controller.menuNeedsUpdate(setup)
        guard let entry = setup.items.first(where: { $0.identifier?.rawValue == "setup.keys" }) as? ActionMenuItem,
              entry.submenu == nil else { throw failure("Setup must link to Settings") }
        entry.invoke()
        let window = controller.appearanceWindow
        let pane = window.apiKeysPane
        guard window.showingKeys, window.sidebar.table.selectedRow == window.sidebar.keysRow,
              window.window?.isVisible == false, !window.preview.running, pane.editors.count == APIAccount.allCases.count else { throw failure("API keys did not open in isolated Settings") }
        if let native = window.window { try SettingsLayoutFixture.write(native, name: "settings-api-keys") }
        for account in APIAccount.allCases {
            let id = account.rawValue
            guard let editor = pane.editors[id], editor.field is NSSecureTextField else { throw failure("Key must be masked") }
            if #available(macOS 26, *) {
                guard editor.saveButton.bezelStyle == .glass, editor.pasteButton.bezelStyle == .glass,
                      editor.saveButton.borderShape == .capsule else { throw failure("Key actions must use native glass capsules") }
            }
            pane.setKey("invalid-fixture", account: id); pane.refresh()
            editor.saveValue(nil)
            try await waitForCheck(state, account: id)
            pane.refresh(); controller.refreshStatus()
            guard state.keyStatuses[id]?.needsAttention == true, editor.feedback.stringValue.contains("rejected"),
                  settings.symbolLabel.hasPrefix("⚠"), editor.feedback.textColor == .systemRed else { throw failure("Key failure is not visible in Settings") }
            pane.setKey("accepted-fixture", account: id); pane.refresh()
            guard !editor.saveButton.title.contains("Saved") else { throw failure("Editing retained saved confirmation") }
            editor.saveValue(nil)
            try await waitForCheck(state, account: id)
            pane.refresh()
            guard state.keyStatuses[id] == .accepted, editor.saveButton.title.contains("Saved") else { throw failure("Save did not confirm") }
        }
        controller.refreshStatus()
        guard !settings.symbolLabel.hasPrefix("⚠") else { throw failure("Correcting keys retained warning") }
        state.routerKey = "slow-invalid-fixture"; state.saveAPIKey(account: "openrouter")
        try await Task.sleep(nanoseconds: 20_000_000)
        state.routerKey = "accepted-fixture"; state.saveAPIKey(account: "openrouter")
        try await waitForCheck(state, account: "openrouter")
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.keyStatuses["openrouter"] == .accepted else { throw failure("Stale check replaced corrected key") }
        state.routerKey = "slow-accepted-fixture"; state.saveAPIKey(account: "openrouter")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = state.recordKeyFailure(ServiceError.account(.openRouter, status: 402), using: "slow-accepted-fixture")
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.keyStatuses["openrouter"]?.needsAttention == true else { throw failure("Check erased runtime failure") }
        state.cerebrasKey = "offline-fixture"; state.saveAPIKey(account: "cerebras")
        try await waitForCheck(state, account: "cerebras")
        guard state.keyStatuses["cerebras"]?.message.contains("Couldn't check") == true else { throw failure("Network error misreported") }
        state.phase = .recording; pane.refresh()
        guard pane.editors.values.allSatisfy({ !$0.pasteButton.isEnabled && !$0.saveButton.isEnabled }) else { throw failure("Keys editable during recording") }
        state.phase = .idle; pane.refresh()
        window.refresh()
        guard window.sectionBar.isHiddenOrHasHiddenAncestor else { throw failure("Appearance tabs overlap API key settings") }
        window.window?.contentView?.layoutSubtreeIfNeeded()
        guard let scroll = pane.view as? NSScrollView, let document = scroll.documentView,
              document.bounds.height > scroll.bounds.height else { throw failure("Key controls must scroll") }
        for editor in pane.editors.values {
            let frame = editor.convert(editor.bounds, to: pane.view)
            guard frame.minX >= 0, frame.maxX <= pane.view.bounds.width, editor.bounds.height >= 54, editor.field.bounds.width >= 180,
                  editor.pasteButton.bounds.width == 76, editor.saveButton.bounds.width == 114 else { throw failure("Key editor clipped") }
        }
        window.sidebar.selectModels()
        guard window.showingModels, !window.showingKeys, pane.view.isHidden else { throw failure("Models navigation failed") }
        window.sidebar.select(.bottom)
        guard !window.showingModels, !window.showingKeys, pane.view.isHidden else { throw failure("Appearance navigation failed") }
        print("PASS: API keys moved to Settings, no root key menu, setup link, masked provider editors, native Save, validation errors, Settings warning, stale-check protection, recording guards and scroll geometry.")
        print("No live credentials, provider requests, visible menus, screen capture, or clipboard changes.")
    }

    private static func waitForCheck(_ state: AppState, account: String) async throws {
        for _ in 0..<100 {
            if state.keyStatuses[account] != .checking { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw failure("Key check did not finish")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "APIKeyProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private actor KeyProbeTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let key = request.value(forHTTPHeaderField: "xi-api-key") ?? request.value(forHTTPHeaderField: "Authorization") ?? ""
        if key.contains("slow") { try? await Task.sleep(nanoseconds: 150_000_000) }
        if key.contains("offline") { throw URLError(.notConnectedToInternet) }
        let status = key.contains("invalid") ? 401 : 200
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
