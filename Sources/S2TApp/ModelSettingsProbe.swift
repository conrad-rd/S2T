import AppKit
import ApplicationServices
import S2TCore

@MainActor enum ModelSettingsProbe {
    static func run() throws {
        try verifyDictionaryObservation()
        var field: [String: CFTypeRef] = [kAXRoleAttribute: kAXTextAreaRole as CFString,
                                        kAXValueAttribute: "Hello Konrad" as CFString]
        guard DictionaryLearner.readText(attribute: { field[$0] }) == "Hello Konrad" else {
            throw failure("Dictionary learning rejected an editor without an optional character count.")
        }
        field[kAXSubroleAttribute] = kAXSecureTextFieldSubrole as CFString
        guard DictionaryLearner.readText(attribute: { field[$0] }) == nil else { throw failure("Dictionary read a secure field.") }
        field[kAXSubroleAttribute] = nil
        field[kAXNumberOfCharactersAttribute] = 20_000 as CFNumber
        guard DictionaryLearner.readText(attribute: { field[$0] }) == nil else { throw failure("Dictionary ignored the field size bound.") }
        field[kAXNumberOfCharactersAttribute] = nil
        field[kAXValueAttribute] = String(repeating: "x", count: 16_385) as CFString
        guard DictionaryLearner.readText(attribute: { field[$0] }) == nil else { throw failure("Dictionary read oversized text without a character count.") }
        print("PASS: dictionary reads editors without character counts and rejects secure or oversized values using isolated attributes.")
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
              state.processingEndpoint == "" else { throw failure("New model settings must use automatic hosting.") }
        let visibleWindows = NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).count
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        guard controller.menu.items.compactMap({ $0.identifier?.rawValue }) ==
            ["appearance.styles", "result.copy", "result.retry", "appearance", "quit"] else {
            throw failure("Model and setup controls must stay in Settings")
        }
        controller.appearanceWindow.showDictation()
        guard controller.appearanceWindow.showingDictation else { throw failure("Dictation setup page missing") }
        let pane = ModelsPane(state: state)
        pane.loadViewIfNeeded()
        guard (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == "provider/selected",
              (pane.controls["cleanup.host"] as? NSPopUpButton)?.selectedItem?.representedObject as? String == "",
              pane.controls["model.prompt.finder"] == nil, pane.controls["model.dictionary.finder"] == nil else {
            throw failure("Model fields are missing or editing instructions remain under Models")
        }
        state.routerEndpoint = "custom/endpoint"
        state.processingProvider = .local
        pane.rebuild()
        guard state.processingEndpoint == nil, state.processingModel == ProcessingProvider.local.defaultModel,
              pane.controls["cleanup.host"] == nil else {
            throw failure("Local provider inherited OpenRouter's endpoint")
        }
        state.processingProvider = .openRouter
        guard state.processingEndpoint == "custom/endpoint", state.processingModel == "provider/selected" else { throw failure("Provider switch lost settings") }
        state.routerEndpoint = ""
        guard AppState(preview: true).processingEndpoint == "" else { throw failure("Cleared endpoint was replaced by default") }
        pane.rebuild()
        state.useCerebrasThroughOpenRouter()
        pane.rebuild()
        pane.navigation.select(.cleanup)
        guard state.processingModel == ProcessingProvider.defaultOpenRouterModel, state.routerEndpoint == "cerebras/fp16",
              pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == true,
              (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == "provider/selected",
              (pane.controls["cleanup.choice"] as? NSPopUpButton)?.selectedItem?.representedObject as? String == ProcessingProvider.defaultOpenRouterModel,
              (pane.controls["cleanup.host"] as? NSPopUpButton)?.selectedItem?.representedObject as? String == state.routerEndpoint else { throw failure("Preset must select its model/host while preserving the hidden custom draft") }
        guard state.saveProcessingModel("cerebras/fp16", for: .openRouter) != nil else { throw failure("Endpoint accepted as model") }
        state.processingProvider = .local
        let activeLocalModel = state.processingModel
        guard state.saveProcessingModel("provider/stale", for: .openRouter) != nil,
              state.processingModel == activeLocalModel else { throw failure("Stale editor changed provider") }
        preferences.set("openrouter", forKey: "processingProvider")
        preferences.set("cerebras/fp16", forKey: "fallbackModel")
        guard AppState(preview: true).processingModel == ProcessingProvider.defaultOpenRouterModel else { throw failure("Invalid persisted model was not repaired") }
        state.processingFailureModel = ProcessingProvider.defaultOpenRouterModel
        state.phase = .complete
        controller.appearanceWindow.showDictation()
        guard controller.appearanceWindow.showingDictation, state.processingFailureModel != nil else { throw failure("Rewrite failure hidden") }
        state.processingProvider = .local
        state.transcriptionProvider = .local
        state.assemblyKey = ""; state.routerKey = ""
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
        print("PASS: The five-item root menu has no model or key editors; model, endpoint, prompt and dictionary controls remain in Settings.")
        print("PASS: persisted provider models, endpoint isolation, preset fields, invalid/stale model rejection, local and Codex settings, and visible rewrite failure. No menus opened, screen capture or live providers.")
    }

    private static func verifyDictionaryObservation() throws {
        let editor = NSTextView(frame: .zero)
        let output = "Ask conrad, use cloud flair today."
        let prefix = "Draft 📝: "
        editor.string = prefix + output + " End."
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("s2t-dictionary-" + UUID().uuidString).appendingPathComponent("dictionary.md"))
        guard var observation = DictionaryObservation(output: output, baseline: editor.string, startedAt: 100) else {
            throw failure("Dictionary did not attach to the generated editor.")
        }
        editor.string = prefix + "Ask Konrad, use cloud flair today. End."
        guard case .waiting = observation.sample(editor.string, at: 101),
              case .waiting = observation.sample(editor.string, at: 101.1),
              case .suggestions(let first, let range) = observation.sample(editor.string, at: 101.25),
              first.map(\.replacement) == ["Konrad"], range.location == prefix.utf16.count else {
            throw failure("Dictionary did not wait for a stable first correction or preserve Unicode offsets.")
        }
        editor.string = prefix + "Ask Konrad, use Cloudflare today. End."
        guard case .waiting = observation.sample(editor.string, at: 104),
              case .suggestions(let second, _) = observation.sample(editor.string, at: 105.5), second.map(\.replacement) == ["Konrad", "Cloudflare"],
              case .waiting = observation.sample(editor.string, at: 107) else {
            throw failure("Dictionary stopped after its first suggestion or duplicated a stable correction.")
        }
        guard !FileManager.default.fileExists(atPath: file.url.path) else {
            throw failure("Dictionary observation must leave persistence to the confirmation controller.")
        }
        _ = try file.append(first)
        _ = try file.update(adding: second, removing: first)
        let persisted = try file.read()
        guard persisted.contains("Replaces: \"conrad\""), persisted.contains("Replaces: \"cloud flair\""),
              persisted.contains("Context:"), persisted.components(separatedBy: "Replaces:").count == 3 else {
            throw failure("Sequential corrections must persist with bounded usage context.")
        }
        guard case .stopped = observation.sample(nil, at: 108),
              case .stopped = observation.sample(editor.string, at: 110), try file.read() == persisted else {
            throw failure("Dictionary resumed after losing its receiving field.")
        }
        guard var expired = DictionaryObservation(output: output, baseline: output, startedAt: 0),
              case .waiting = expired.sample("Ask Konrad, use Cloudflare today.", at: 59),
              case .stopped = expired.sample("Ask Konrad, use Cloudflare today.", at: 60), try file.read() == persisted else {
            throw failure("Dictionary saved a correction after the one-minute deadline.")
        }
        print("PASS: native offscreen editor, sequential stable suggestions, context-preserving file writes, Unicode offsets, no duplicate saves, field loss and one-minute deadline. No real fields, dictionary or clipboard accessed.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ModelSettingsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
