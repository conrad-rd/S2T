import AppKit
import SwiftUI
import S2TCore

@MainActor enum APIKeyProbe {
    static func run() async throws {
        try await BenchmarkFeedProbe.run()
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true, api: DictationAPI(transport: KeyProbeTransport()))
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        guard !controller.menu.items.contains(where: { $0.identifier?.rawValue == "keys" }),
              controller.menu.items.contains(where: { $0.identifier?.rawValue == "appearance" }) else { throw failure("Keys must be reached through Settings") }
        let window = controller.appearanceWindow
        window.showAPIKeys()
        let pane = window.apiKeysPane
        let editing = pane.editing
        guard window.showingKeys, window.window?.isVisible == false,
              pane.view is NSHostingView<APIKeysView>, editing.account == nil else { throw failure("API keys must use a hidden SwiftUI host") }
        for account in APIAccount.allCases {
            let id = account.rawValue
            editing.paste("invalid-fixture", for: id)
            guard state.keyValue(id).isEmpty else { throw failure("Paste activated an unsaved key") }
            editing.save(id)
            try await waitForCheck(state, account: id)
            guard editing.status(id)?.needsAttention == true, editing.message(id).contains("rejected"),
                  window.showingKeys else { throw failure("Provider failure is not exposed in Settings") }
            editing.beginEditing(id)
            guard editing.account == id else { throw failure("Edit must reveal the selected key") }
            editing.change("accepted-fixture", for: id)
            pane.refresh()
            guard state.keyValue(id) == "invalid-fixture", editing.value(id) == "accepted-fixture", !editing.saved(id) else { throw failure("Draft activated before Save or was lost") }
            editing.endEditing(commit: false)
            guard editing.account == nil, editing.value(id) == "accepted-fixture" else { throw failure("Hiding must retain the draft") }
            editing.save(id)
            try await waitForCheck(state, account: id)
            guard editing.account == nil, state.keyValue(id) == "accepted-fixture", editing.saved(id), editing.status(id) == .accepted,
                  !editing.canSave(id) else { throw failure("Save did not apply and mask the key") }
        }
        state.routerKey = "slow-invalid-fixture"; state.saveAPIKey(account: "openrouter")
        try await Task.sleep(nanoseconds: 20_000_000)
        state.routerKey = "accepted-fixture"; state.saveAPIKey(account: "openrouter")
        try await waitForCheck(state, account: "openrouter")
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.keyStatuses["openrouter"] == .accepted else { throw failure("Stale check replaced corrected key") }
        editing.change(" \n ", for: "openrouter")
        guard editing.canSave("openrouter") else { throw failure("An empty draft must allow removing a saved key") }
        editing.save("openrouter")
        guard state.routerKey.isEmpty, !editing.saved("openrouter"), editing.status("openrouter") == nil,
              state.assemblyKey == "accepted-fixture" else { throw failure("Clearing a key must disconnect only that provider") }
        state.routerKey = "slow-accepted-fixture"; state.saveAPIKey(account: "openrouter")
        editing.change("", for: "openrouter"); editing.save("openrouter")
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.routerKey.isEmpty, state.keyStatuses["openrouter"] == nil else {
            throw failure("A late validation restored a cleared key")
        }
        editing.beginEditing("openrouter")
        editing.change("accepted-fixture", for: "openrouter")
        editing.endEditing()
        try await waitForCheck(state, account: "openrouter")
        guard editing.saved("openrouter"), state.routerKey == "accepted-fixture" else {
            throw failure("Leaving the key field must save its draft")
        }
        state.routerKey = "slow-accepted-fixture"; state.saveAPIKey(account: "openrouter")
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = state.recordKeyFailure(ServiceError.account(.openRouter, status: 402), using: "slow-accepted-fixture")
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.keyStatuses["openrouter"]?.needsAttention == true else { throw failure("Check erased runtime failure") }
        state.assemblyKey = "offline-fixture"; state.saveAPIKey(account: "assemblyai")
        try await waitForCheck(state, account: "assemblyai")
        guard state.keyStatuses["assemblyai"]?.message.contains("Couldn't check") == true,
              editing.canSave("assemblyai") else { throw failure("Network error must remain visible and allow retrying Save") }
        editing.beginEditing("openrouter")
        state.phase = .recording; pane.refresh()
        let activeKey = state.routerKey
        guard editing.enabled else { throw failure("Recording must not block API-key drafts") }
        editing.change("draft-fixture", for: "openrouter")
        editing.save("openrouter")
        guard editing.value("openrouter") == "draft-fixture", state.routerKey == activeKey,
              !editing.canSave("openrouter"), editing.message("openrouter").contains("Finish dictation") else {
            throw failure("A key draft changed the active recording credentials or failed to explain deferred saving")
        }
        editing.endEditing()
        state.phase = .idle; pane.refresh()
        window.refresh()
        guard window.sectionBar.isHiddenOrHasHiddenAncestor else { throw failure("Appearance tabs overlap API keys") }
        let layoutEditing = APIKeyEditing(state: state)
        for id in ["s2t"] + APIKeysPane.accounts.map(\.rawValue) { layoutEditing.change("synthetic-key", for: id) }
        layoutEditing.change(String(repeating: "synthetic-key-", count: 30), for: "openrouter")
        let host = NSHostingView(rootView: APIKeysView(state: state, editing: layoutEditing))
        let fixture = SettingsEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        fixture.cancelFieldEditing = { layoutEditing.endEditing(commit: false) }
        fixture.contentView = host
        for width: CGFloat in [420, 600] {
            fixture.setContentSize(NSSize(width: width, height: 600))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            for id in ["s2t"] + APIKeysPane.accounts.map(\.rawValue) {
                guard let field = layoutEditing.layout["field." + id],
                      let title = layoutEditing.layout["title." + id], title.maxX <= field.minX, field.width >= 120,
                      field.height < 40, field.maxX <= width - 20 else { throw failure("Compact key controls overlap or clip at width \(width), account \(id): \(layoutEditing.layout)") }
                if let status = layoutEditing.layout["status." + id] {
                    guard status.minY >= field.maxY, status.minX >= 0, status.maxX <= width - 20 else {
                        throw failure("Key feedback overlaps its field or clips")
                    }
                }
            }
        }
        guard !APIKeysPane.accounts.contains(.artificialAnalysis) else { throw failure("Benchmark credentials must not appear in API keys") }
        let idleEditing = APIKeyEditing(state: state)
        host.rootView = APIKeysView(state: state, editing: idleEditing)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard idleEditing.layout["row.artificialanalysis"] == nil else {
            throw failure("Artificial Analysis must not render an API-key row")
        }
        for id in ["s2t"] + APIKeysPane.accounts.map(\.rawValue) {
            guard let field = idleEditing.layout["field." + id], field.width >= 120,
                  field.maxX <= 580, idleEditing.layout["actions." + id] == nil else {
                throw failure("Idle key rows must have one editable value without redundant Save actions, account \(id)")
            }
        }
        host.rootView = APIKeysView(state: state, editing: layoutEditing)
        func nativeFields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(nativeFields)
        }
        layoutEditing.beginEditing("openrouter")
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard let inline = nativeFields(host).first(where: { $0.isEditable && $0.stringValue == layoutEditing.value("openrouter") }),
              inline is NSSecureTextField else {
            throw failure("API keys must use native secure text fields")
        }
        let activeBeforeEscape = state.routerKey
        fixture.makeFirstResponder(inline)
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: fixture.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
            guard fixture.handleEditingEvent(event), layoutEditing.account == nil,
                  state.routerKey == activeBeforeEscape else { throw failure("Escape saved the API-key draft instead of masking it") }
        } else { throw failure("Could not create the unposted Escape fixture") }
        layoutEditing.endEditing()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard nativeFields(host).filter({ $0.isEditable && $0.stringValue.contains("synthetic-key") }).allSatisfy({ $0 is NSSecureTextField }),
              layoutEditing.value("openrouter").contains("synthetic-key") else {
            throw failure("Leaving editing must keep every credential masked and preserve its draft")
        }
        guard !fixture.isVisible else { throw failure("Layout check exposed a window") }
        fixture.contentView = nil
        window.sidebar.selectModels()
        guard window.showingModels, !window.showingKeys, pane.view.isHidden else { throw failure("Models navigation failed") }
        window.sidebar.selectAppearance()
        guard !window.showingModels, !window.showingKeys, pane.view.isHidden else { throw failure("Appearance navigation failed") }
        print("PASS: API keys are in Settings, with native grouped rows, masked idle controls, Return/blur saving, empty-key removal, validation, draft protection, recording guards and scroll geometry.")
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
        let key = request.value(forHTTPHeaderField: "x-api-key") ?? request.value(forHTTPHeaderField: "xi-api-key") ?? request.value(forHTTPHeaderField: "Authorization") ?? ""
        if key.contains("slow") { try? await Task.sleep(nanoseconds: 150_000_000) }
        if key.contains("offline") { throw URLError(.notConnectedToInternet) }
        let status = key.contains("invalid") ? 401 : 200
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
