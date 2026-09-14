import AppKit
import S2TCore

@MainActor enum ModelSettingsProbe {
    static func run() throws {
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 900, width: 1920, height: 1080)] {
            let text = CGRect(x: display.midX - 100, y: display.midY, width: 200, height: 30)
            let popup = DictionaryLearner.popupFrame(above: text, visibleFrame: display)
            guard popup.minY == text.maxY + 8, popup.midX == text.midX, display.contains(popup) else {
                throw failure("Dictionary confirmation must sit above the delivered text on its display.")
            }
            let topEdge = CGRect(x: display.minX, y: display.maxY - 30, width: 100, height: 30)
            let fallback = DictionaryLearner.popupFrame(above: topEdge, visibleFrame: display)
            guard display.contains(fallback), fallback.maxY < topEdge.minY else {
                throw failure("Dictionary confirmation must stay visible near display edges.")
            }
        }
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        preferences.setPersistentDomain([
            "fallbackModel": "provider/selected",
            "cerebrasModel": "gpt-oss-120b",
            "recommendationURL": "https://unused.example/feed"
        ], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        guard state.processingProvider == .openRouter, state.processingModel == "provider/selected",
              state.processingEndpoint == "cerebras/fp16" else { throw failure("Default endpoint changed the provider or saved model.") }
        let visibleWindows = NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).count
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.menuNeedsUpdate(controller.menu)
        guard let setup = controller.menu.items.first(where: { $0.identifier?.rawValue == "setup" })?.submenu else {
            throw failure("Missing dictation setup submenu.")
        }
        controller.menuNeedsUpdate(setup)
        guard setup.items.filter({ $0.identifier?.rawValue == "permissions.setup" }).count == 1,
              !controller.menu.items.contains(where: { $0.identifier?.rawValue == "accessibility" }) else {
            throw failure("Onboarding must have one setup action without duplicate permission buttons.")
        }
        guard !controller.menu.items.contains(where: { ["keys", "models"].contains($0.identifier?.rawValue ?? "") }),
              let setupKeys = setup.items.first(where: { $0.identifier?.rawValue == "setup.keys" }),
              setupKeys.submenu == nil else { throw failure("Model or API key menu remains outside Settings") }
        let pane = ModelsPane(state: state)
        pane.loadViewIfNeeded()
        guard (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == "provider/selected",
              (pane.controls["cleanup.host"] as? NSTextField)?.stringValue == "cerebras/fp16",
              pane.controls["model.prompt.finder"] is NSButton, pane.controls["model.dictionary.finder"] is NSButton else {
            throw failure("Models and editing instructions are missing from Settings")
        }
        state.routerEndpoint = "custom/endpoint"
        state.processingProvider = .cerebras
        pane.rebuild()
        guard state.processingEndpoint == nil, state.processingModel == "gpt-oss-120b", pane.controls["cleanup.host"] == nil else {
            throw failure("Cerebras inherited OpenRouter's endpoint")
        }
        state.processingProvider = .openRouter
        guard state.processingEndpoint == "custom/endpoint", state.processingModel == "provider/selected" else { throw failure("Provider switch lost settings") }
        state.routerEndpoint = ""
        guard AppState(preview: true).processingEndpoint == "" else { throw failure("Cleared endpoint was replaced by default") }
        pane.rebuild()
        (pane.controls["cleanup.preset"] as? NSButton)?.performClick(nil)
        guard state.processingModel == ProcessingProvider.cerebrasOpenRouterModel, state.routerEndpoint == "cerebras/fp16",
              (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == state.processingModel,
              (pane.controls["cleanup.host"] as? NSTextField)?.stringValue == state.routerEndpoint else { throw failure("Preset did not update both fields") }
        guard state.saveProcessingModel("cerebras/fp16", for: .openRouter) != nil else { throw failure("Endpoint accepted as model") }
        state.processingProvider = .cerebras
        guard state.saveProcessingModel("provider/stale", for: .openRouter) != nil, state.processingModel == "gpt-oss-120b" else { throw failure("Stale editor changed provider") }
        preferences.set("openrouter", forKey: "processingProvider")
        preferences.set("cerebras/fp16", forKey: "fallbackModel")
        guard AppState(preview: true).processingModel == ProcessingProvider.cerebrasOpenRouterModel else { throw failure("Invalid persisted model was not repaired") }
        state.processingFailureModel = ProcessingProvider.cerebrasOpenRouterModel
        state.phase = .complete
        controller.refreshStatus()
        guard controller.menu.items.first(where: { $0.identifier?.rawValue == "status.phase" })?.title.contains("Rewrite failed") == true else { throw failure("Rewrite failure hidden") }
        state.processingProvider = .local
        state.transcriptionProvider = .local
        state.assemblyKey = ""; state.routerKey = ""; state.cerebrasKey = ""; state.elevenLabsKey = ""
        state.localProcessingURL = "http://127.0.0.1:1234/v1/chat/completions"
        state.localTranscriptionURL = "http://localhost:8080/v1/audio/transcriptions"
        state.localTranscriptionModel = "whisper/large-v3"
        guard state.saveProcessingModel("org/model:latest", for: .local) == nil, state.canRecord, state.setupKeysReady, state.processingEndpoint == nil else { throw failure("Local provider requires a cloud key") }
        pane.rebuild()
        for id in ["speech.url", "cleanup.url"] {
            guard (pane.controls[id] as? NSTextField)?.stringValue.hasPrefix("http://") == true else { throw failure("Local endpoint missing from Settings") }
        }
        state.processingProvider = .codex
        state.processingModel = "fixture-codex"
        pane.rebuild()
        guard pane.controls["codex.executable"] != nil, pane.controls["cleanup.host"] == nil,
              AppState(preview: true).processingModel == "fixture-codex" else { throw failure("Codex settings missing or mixed with hosting") }
        guard NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).count == visibleWindows else { throw failure("Verification opened a window") }
        print("PASS: Root and setup menus contain no model or key editors; model, endpoint, prompt and dictionary controls remain in Settings.")
        print("PASS: persisted provider models, endpoint isolation, preset fields, invalid/stale model rejection, local and Codex settings, and visible rewrite failure. No menus opened, screen capture or live providers.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ModelSettingsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
