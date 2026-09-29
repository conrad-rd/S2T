import AppKit
import SwiftUI
import S2TCore

@MainActor enum ProviderVisibilityProbe {
    static func run() async throws {
        let suite = "com.s2t.preview"
        let defaults = UserDefaults(suiteName: suite)!
        let saved = defaults.persistentDomain(forName: suite) ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: suite) }
        defaults.setPersistentDomain([:], forName: suite)
        let state = AppState(preview: true)
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        let pane = controller.modelsPane
        let originalSpeech = state.transcriptionProvider
        let originalProcessing = state.processingProvider
        let originalModel = state.processingModel
        let originalProviders = values(pane, "cleanup.provider")
        try require(originalProviders.contains("openrouter") && originalProviders.contains("s2t"), "Providers should start visible")
        state.speechUsesCredits = true
        state.cleanupUsesCredits = true
        state.jevCleanupMode = .beforeCleanup
        state.jevRoute = .openRouter
        pane.rebuild()

        let providerIDs = ["s2t", "openrouter", "xai", "local"]
        for id in providerIDs {
            try toggle(pane, provider: id, on: false)
            try await settle()
            try require(state.hiddenProviders == [id] && AppState(preview: true).hiddenProviders == [id], "Each switch must persist independently: " + id)
            try require(values(pane, "cleanup.provider") == originalProviders.filter { $0 != id }, "Only the selected provider should disappear: " + id)
            try require(controller.sidebar.creditNumber.isHidden == (id == "s2t"), "Only the credits switch should hide the balance")
            try require((pane.controls["models.local"] == nil) == (id == "local"), "Only the Local switch should hide the library")
            controller.showAPIKeys()
            try await settle()
            let layout = controller.apiKeysPane.editing.layout
            for account in ["s2t", "openrouter", "xai", "assemblyai", "typesafe"] {
                try require((layout["row." + account] != nil) == (account != id), "An unrelated API key disappeared: " + id + "/" + account)
            }
            let dashboard = controller.dashboardPane
            _ = dashboard.view
            try require(dashboard.model.availableSources == LocalUsageSource.allCases.filter { $0.rawValue.lowercased() != id }, "Dashboard sources must change independently")
            controller.showModels()
            try toggle(pane, provider: id, on: true)
            try await settle()
            try require(state.hiddenProviders.isEmpty && values(pane, "cleanup.provider") == originalProviders, "Each switch must restore only its provider")
        }
        for id in providerIDs { try toggle(pane, provider: id, on: false) }
        try await settle()
        try require(state.hiddenProviders == Set(providerIDs) && AppState(preview: true).hiddenProviders == Set(providerIDs), "Toggle must persist across launch")
        try require(state.speechUsesCredits && state.cleanupUsesCredits && state.transcriptionProvider == originalSpeech && state.processingProvider == originalProcessing && state.processingModel == originalModel, "Hiding must preserve active connections")
        try require(values(pane, "speech.provider") == ["assemblyai"] && values(pane, "cleanup.provider") == ["codex"], "Only visible providers should remain in pickers")
        try require(pane.controls["speech.choice"] == nil && pane.controls["cleanup.choice"] == nil && pane.controls["models.local"] == nil, "Hidden providers must not expose models or the local library")
        try require((pane.controls["cleanup.jev.route"] as? NSPopUpButton)?.titleOfSelectedItem == "Current connection hidden", "A hidden saved connection must not look like another provider")
        try require(controller.sidebar.creditNumber.isHidden && controller.sidebar.creditCaption.isHidden, "Sidebar credits must disappear")
        pane.navigation.select(.local)
        try require(pane.navigation.page == .settings, "Hidden local library must stay closed")

        controller.showAPIKeys()
        try await settle()
        let keys = controller.apiKeysPane.editing
        try require(keys.layout["row.s2t"] == nil && keys.layout["row.openrouter"] == nil && keys.layout["row.xai"] == nil && keys.layout["row.assemblyai"] != nil, "API key rows must follow visibility")
        let pasteMenu = controller.pageToolbar.toolbar.items.compactMap { $0 as? NSMenuToolbarItem }.first?.menu
        try require(pasteMenu?.items.filter { !$0.isHidden }.compactMap { $0.representedObject as? String } == ["assemblyai", "typesafe"], "Toolbar must hide provider actions too")
        let dashboard = controller.dashboardPane
        _ = dashboard.view
        try require(dashboard.model.availableSources == [.assemblyAI, .typeSafe], "Usage dashboard must hide the same providers")

        controller.showMeetings()
        controller.meetingsPane.navigation.showingModels = true
        state.meetings.selectSpeechProvider("xai")
        try await settle()
        let meetingControls = descendants(controller.meetingsPane.view).compactMap { $0 as? NSPopUpButton }
        for (id, allowed) in [("meetings.speech.provider", "assemblyai"), ("meetings.processing.provider", "codex")] {
            guard let picker = meetingControls.first(where: { $0.identifier?.rawValue == id }) else { throw failure("Missing meeting provider menu") }
            try require(picker.itemArray.filter(\.isEnabled).compactMap { $0.representedObject as? String } == [allowed], "Meeting provider menu leaked hidden choices")
            try require(picker.titleOfSelectedItem == "Current provider hidden", "Meeting selection must not reveal the hidden provider")
        }
        try require(!meetingControls.contains { $0.identifier?.rawValue == "meetings.speech.model" }, "Hidden speech models must disappear")

        let writing = controller.writingPane.editing
        writing.settings.funding = .credits
        for id in ["openrouter|fixture/model", "xai|grok-4.6", "local|fixture"] { writing.toggleFavorite(id) }
        try require(writing.modelChoices.allSatisfy { $0.provider == .codex } && !writing.modelChoices.isEmpty, "Writing choices and favorites must hide providers")
        try require(writing.selectedModelTitle == "Current provider hidden", "Writing button must conceal the saved model")
        let writingPicker = WritingModelPickerController(editing: writing, choices: writing.modelChoices, close: {})
        _ = writingPicker.view
        try require(writingPicker.group == "codex" && writingPicker.visibleChoices.allSatisfy { $0.provider == .codex }, "Writing picker must open a visible provider")
        writing.selectModel(.init(provider: .codex, model: "default", title: "Codex default"))
        try require(writing.settings.isCodex && !writing.settings.usesCredits, "Choosing a visible writing provider must explicitly switch its connection")

        controller.showModels()
        (pane.controls["speech.provider"] as? ModelProviderPicker)?.choose("assemblyai")
        (pane.controls["cleanup.provider"] as? ModelProviderPicker)?.choose("codex")
        try await settle()
        for prefix in ["speech", "cleanup"] {
            let id = prefix == "speech" ? "speech.mode" : "cleanup.choice"
            let menu = (pane.controls[id] as? NSPopUpButton)?.menu
            let branches = menu?.items.compactMap { $0.submenu == nil ? nil : $0.title } ?? []
            try require(!branches.isEmpty && !branches.contains { ["OpenRouter", "Local", "xAI"].contains($0) }, "Model submenus must hide providers too")
        }
        try toggle(pane, provider: "openrouter", on: true)
        try toggle(pane, provider: "xai", on: true)
        try await settle()
        try require(state.hiddenProviders == ["s2t", "local"], "Mixed provider visibility must remain independent")
        (pane.controls["models.providers"] as? NSButton)?.performClick(nil)
        try require(pane.navigation.page == .providers && pane.navigation.pageTitle == "Providers", "Models must open a dedicated Providers subsection")
        try require(providerIDs.allSatisfy { pane.controls["models.providerVisibility." + $0] is NSSwitch }, "Providers subsection must contain four switches")
        if let directory = ProcessInfo.processInfo.environment["S2T_PROVIDER_VISIBILITY_ARTIFACTS"] {
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try render(window, to: output.appendingPathComponent("provider-toggles.png"))
        }

        for id in providerIDs { try toggle(pane, provider: id, on: true) }
        try await settle()
        try require(AppState(preview: true).hiddenProviders.isEmpty && values(pane, "cleanup.provider") == originalProviders, "Turning on must restore all providers and persist")
        try require(pane.controls["models.local"] != nil && !controller.sidebar.creditNumber.isHidden, "Library and credits must return")
        controller.showAPIKeys()
        try await settle()
        try require(keys.layout["row.s2t"] != nil && keys.layout["row.openrouter"] != nil && keys.layout["row.xai"] != nil, "API keys must return")
        try require(pasteMenu?.items.allSatisfy { !$0.isHidden } == true, "Cached toolbar choices must return")
        try require(dashboard.model.availableSources == LocalUsageSource.allCases, "Dashboard providers must return")
        try require(!window.isVisible, "Verification must never show a window")
        print("Provider visibility passed: four independent native toggles, Models subsection, per-provider persistence, preserved connections, model menus, API keys, sidebar, meetings, writing, dashboard, and restoration.")
    }

    private static func values(_ pane: ModelsPane, _ id: String) -> [String] {
        (pane.controls[id] as? NSPopUpButton)?.itemArray.compactMap { $0.representedObject as? String } ?? []
    }
    private static func toggle(_ pane: ModelsPane, provider: String, on: Bool) throws {
        pane.navigation.showProviders()
        guard let control = pane.controls["models.providerVisibility." + provider] as? NSSwitch, let action = control.action else { throw failure("Missing provider visibility toggle: " + provider) }
        control.state = on ? .on : .off
        try require(control.sendAction(action, to: control.target), "Toggle action was not delivered")
        pane.navigation.back()
    }
    private static func settle() async throws { try await Task.sleep(nanoseconds: 180_000_000) }
    private static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private static func render(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw failure("Missing settings view") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw failure("Cannot render settings") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure("Cannot encode settings image") }
        try data.write(to: url)
    }
    private static func require(_ condition: Bool, _ message: String) throws { if !condition { throw failure(message) } }
    private static func failure(_ message: String) -> NSError { NSError(domain: "ProviderVisibilityProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
