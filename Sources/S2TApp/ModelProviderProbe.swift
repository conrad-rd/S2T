import AppKit
import S2TCore

@MainActor enum ModelProviderProbe {
    static func run() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-provider-probe-" + UUID().uuidString)
        let state = AppState(preview: true)
        state.localModels = LocalModels(preview: true, root: fixture, nativePreviewModels: [.appleSpeech(locale: "de-DE")])
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        let pane = controller.modelsPane
        guard pane.controls["cleanup.service"] == nil, pane.controls["speech.service"] == nil else {
            throw failure("Provider selection must use one flat list, not competing account/service selectors")
        }
        let tasks: [(String, String, ModelsSection)] = [("speech", "speech", .speech), ("text", "cleanup", .cleanup)]
        func picker(_ prefix: String) throws -> NSPopUpButton {
            guard let picker = pane.controls[prefix + ".provider"] as? NSPopUpButton else { throw failure("Missing provider picker") }
            return picker
        }
        func choose(_ value: String, prefix: String) throws {
            try ModelChoiceProbe.choose(prefix + ".provider", value, in: pane)
        }
        /// Providers stay a short list with one Local models entry; installed models appear only in the Model menu.
        func verifyInstalledOnly(_ category: String, prefix: String) throws {
            let items = try picker(prefix).itemArray
            guard items.filter({ $0.representedObject as? String == "local" }).count == 1,
                  !items.contains(where: { ($0.representedObject as? String)?.hasPrefix("managed:") == true }),
                  items.allSatisfy({ $0.submenu == nil && $0.title != "Install local models" }) else {
                throw failure("Provider dropdown must offer one Local models entry without model or download items")
            }
            guard let models = pane.controls[prefix + ".choice"] as? LocalModelChoicePicker else { return }
            let expected = Set(state.localModels.catalog.filter {
                $0.category == category && state.localModels.installed.contains($0.id)
            }.map(\.id))
            let localItems = models.menu?.items.first { $0.title == "Local" }?.submenu?.items ?? []
            let actual = Set(localItems.compactMap { item -> String? in
                guard let value = item.representedObject as? String, value.hasPrefix("managed:") else { return nil }
                return String(value.dropFirst("managed:".count))
            })
            guard actual == expected else {
                throw failure("Local models must list only installed models for its task")
            }
            let unavailable = state.localModels.catalog.filter { !state.localModels.installed.contains($0.id) }
            guard !localItems.contains(where: { item in item.isEnabled && unavailable.contains(where: { $0.name == item.title }) }) else {
                throw failure("An uninstalled model appeared as a selectable local model")
            }
        }
        func chooseModel(_ value: String, prefix: String) throws {
            try ModelChoiceProbe.choose(prefix + ".choice", value, in: pane)
        }
        func markInstalled(_ model: LocalModel) throws {
            let directory = fixture.appendingPathComponent("models/" + model.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["revision": model.revision]).write(to: directory.appendingPathComponent("installed.json"))
            state.localModels.refreshInstalled()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        for (category, prefix, _) in tasks {
            try verifyInstalledOnly(category, prefix: prefix)
            guard try picker(prefix).itemArray.filter({
                guard let value = $0.representedObject as? String else { return false }
                return !value.hasPrefix("managed:")
            }).allSatisfy(\.isEnabled) else {
                throw failure("Missing keys must not disable cloud provider setup")
            }
            guard (pane.controls[prefix + ".accountStatus"] as? NSTextField)?.stringValue == "Not added",
                  (pane.controls[prefix + ".keys"] as? NSButton)?.title == "Add key…" else {
                throw failure("An unconfigured provider must explain that it needs a key and offer Add key")
            }
        }
        try ModelChoiceProbe.beginCustom("cleanup", in: pane)
        guard let draft = pane.controls["cleanup.model"] as? NSTextField else { throw failure("Missing cloud model field") }
        draft.stringValue = "fixture/unsaved-draft"
        let speech = state.localModels.catalog.first { $0.category == "speech" && !$0.isNative }!
        try markInstalled(speech)
        guard pane.controls["cleanup.model"] === draft, draft.stringValue == "fixture/unsaved-draft",
              (pane.controls["models.local"] as? SettingsLinkRow)?.summary.contains("1 downloaded") == true else {
            throw failure("Installed models must appear without rebuilding unrelated drafts")
        }
        for (category, prefix, section) in tasks {
            let model = state.localModels.catalog.first { $0.category == category && !$0.isNative }!
            try markInstalled(model)
            for (task, taskPrefix, _) in tasks { try verifyInstalledOnly(task, prefix: taskPrefix) }
            pane.navigation.select(section)
            try choose("local", prefix: prefix)
            let customURL = category == "speech" ? "http://localhost:8081/v1/audio/transcriptions" : "http://localhost:1235/v1/chat/completions"
            let customModel = "fixture-" + category
            switch category {
            case "speech": state.localTranscriptionURL = customURL; state.localTranscriptionModel = customModel
            case "text": state.localProcessingURL = customURL; state.processingModel = customModel
            default: throw failure("Unexpected local category")
            }
            state.speechUsesCredits = true
            state.cleanupUsesCredits = true
            try choose("local", prefix: prefix)
            try chooseModel("managed:" + model.id, prefix: prefix)
            guard state.managedLocalModelID(for: category) == model.id,
                  (pane.controls[prefix + ".choice"] as? NSPopUpButton)?.titleOfSelectedItem == model.name,
                  pane.controls[prefix + ".url"] == nil, pane.controls[prefix + ".model"] == nil,
                  !state.usesCredits(for: category) else {
                throw failure("Installed selection must use the named model without endpoint editors or paid routing")
            }
            let restored = AppState(preview: true)
            guard restored.managedLocalModelID(for: category) == model.id else { throw failure("Installed model choice did not persist") }
            restored.selectLocalEndpoint(for: category)
            guard restored.localConfiguration(for: category).url == customURL,
                  restored.localConfiguration(for: category).model == customModel else {
                throw failure("Custom endpoint settings were lost across restart")
            }
            // Restore the first state's managed model after the isolated restart check updates the shared preview preferences.
            state.localModels.use(model, state: state)
            pane.rebuild()
            try chooseModel("endpoint", prefix: prefix)
            guard state.localConfiguration(for: category).url == customURL,
                  state.localConfiguration(for: category).model == customModel,
                  pane.controls[prefix + ".url"] != nil, pane.controls[prefix + ".model"] != nil else {
                throw failure("Returning to Custom local endpoint lost its configuration")
            }
            try verifyInstalledOnly(category, prefix: prefix)
        }
        pane.navigation.select(.cleanup)
        try choose("local", prefix: "cleanup")
        let available = state.localModels.catalog.first { $0.category == "text" && !state.localModels.installed.contains($0.id) && state.localModels.memoryFits($0) }!
        state.processingModel = available.id
        state.localProcessingURL = LocalModels.managedEndpoint
        pane.rebuild()
        try verifyInstalledOnly("text", prefix: "cleanup")
        guard (pane.controls["cleanup.choice"] as? NSPopUpButton)?.titleOfSelectedItem == available.name + " · Not installed",
              state.managedLocalModelID(for: "text") == available.id else {
            throw failure("A saved but uninstalled model must show a neutral placeholder without switching providers")
        }
        try choose("local", prefix: "cleanup")
        let before = state.processingModel
        let beforeProvider = state.processingProvider
        let sourcePicker = try picker("cleanup")
        sourcePicker.addItem(withTitle: available.name)
        sourcePicker.lastItem?.representedObject = available.id
        sourcePicker.selectItem(at: sourcePicker.numberOfItems - 1)
        if let action = sourcePicker.action { _ = sourcePicker.sendAction(action, to: sourcePicker.target) }
        guard state.processingProvider == beforeProvider, state.processingModel == before else {
            throw failure("An unavailable model value must never be treated as a provider")
        }
        try verifyInstalledOnly("text", prefix: "cleanup")
        state.phase = .recording
        let installed = state.localModels.catalog.first { $0.category == "text" && state.localModels.installed.contains($0.id) }!
        pane.rebuild()
        guard let retained = pane.controls["cleanup.choice"] as? NSPopUpButton else { throw failure("Missing local model menu") }
        retained.select(retained.itemArray.first { $0.representedObject as? String == "managed:" + installed.id })
        if let action = retained.action { _ = retained.sendAction(action, to: retained.target) }
        guard state.processingModel == before else { throw failure("Stale provider action changed a model during recording") }
        state.phase = .idle
        func chooseControl(_ id: String, _ value: String) throws {
            if id.hasSuffix(".model") {
                try ModelChoiceProbe.choose(id, value, in: pane)
                return
            }
            guard let popup = pane.controls[id] as? NSPopUpButton,
                  let item = popup.itemArray.first(where: { $0.representedObject as? String == value }),
                  let action = popup.action else { throw failure("Missing xAI speech choice: " + id) }
            popup.select(item)
            _ = popup.sendAction(action, to: popup.target)
        }
        state.xaiKey = "speech-xai-fixture"
        try choose("xai", prefix: "speech")
        guard state.transcriptionKey == "speech-xai-fixture", state.transcriptionModel == "grok-voice-transcribe-2.0",
              ModelChoiceProbe.values(in: (pane.controls["speech.choice"] as? NSPopUpButton)?.menu).contains("grok-voice-transcribe-1.0") else { throw failure("xAI dictation must list both speech models and use its own key") }
        try chooseControl("speech.model", "grok-voice-transcribe-1.0")
        try choose("openrouter", prefix: "speech")
        try choose("xai", prefix: "speech")
        guard state.transcriptionModel == "grok-voice-transcribe-1.0", AppState(preview: true).xaiTranscriptionModel == state.transcriptionModel else { throw failure("Personal xAI speech model did not persist") }
        try choose("s2t", prefix: "speech")
        guard let speechProviders = pane.controls["speech.provider"] as? NSPopUpButton,
              Array(speechProviders.itemArray.prefix(4)).map(\.title) == ["S2T", "AssemblyAI", "OpenRouter", "xAI"],
              speechProviders.itemArray.allSatisfy({ !(($0.representedObject as? String)?.hasPrefix("s2t:") ?? false) }) else { throw failure("Speech must show exactly four cloud providers, with one S2T entry") }
        guard let catalogPicker = pane.controls["speech.choice"] as? NSPopUpButton,
              Set(ModelChoiceProbe.values(in: catalogPicker.menu)).isSuperset(of:
                Set(state.creditModels.filter { $0.operation == "transcription" && $0.provider != "openrouter" }.map(\.model))) else {
            throw failure("Every authorized non-OpenRouter speech model must be selectable")
        }
        let beforeCreditModel = state.creditTranscriptionModel
        try chooseControl("speech.model", "grok-voice-transcribe-2.0")
        guard state.creditTranscriptionModel == beforeCreditModel, state.creditSpeechProvider != .xai else { throw failure("An unavailable hosted model was accepted") }
        let models = #"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"test","models":[{"provider":"xai","operation":"transcription","model":"grok-voice-transcribe-2.0","host":"","title":"Grok 2.0"},{"provider":"xai","operation":"transcription","model":"grok-voice-transcribe-1.0","host":"","title":"Grok 1.0"},{"provider":"openrouter","operation":"transcription","model":"openai/whisper-1","host":"","title":"Whisper"},{"provider":"xai","operation":"cleanup","model":"grok-4.6","host":"","title":"Grok"}]}"#
        state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(models.utf8)))
        pane.rebuild()
        try chooseModel("grok-voice-transcribe-2.0", prefix: "speech")
        guard state.creditTranscriptionModel == "grok-voice-transcribe-2.0" else { throw failure("Subscription inherited personal speech model") }
        try chooseModel("grok-voice-transcribe-1.0", prefix: "speech")
        try choose("openrouter", prefix: "speech")
        try choose("s2t", prefix: "speech")
        guard state.creditTranscriptionModel == "grok-voice-transcribe-1.0", AppState(preview: true).creditSpeechProvider == .xai,
              AppState(preview: true).creditXAISpeechModel == state.creditTranscriptionModel else { throw failure("Subscription xAI speech choice did not persist independently") }
        try choose("xai", prefix: "cleanup")
        state.xaiKey = "xai-isolated-fixture"
        state.routerKey = "router-isolated-fixture"
        guard state.processingProvider == .xai, state.processingKey == "xai-isolated-fixture",
              state.processingModel == "grok-4.6", state.processingEndpoint == nil,
              pane.controls["cleanup.host"] == nil else { throw failure("xAI selection inherited OpenRouter credentials or routing") }
        guard state.saveProcessingModel("grok-4.3", for: .xai) == nil else { throw failure("xAI model save failed") }
        try choose("openrouter", prefix: "cleanup")
        try choose("xai", prefix: "cleanup")
        guard state.processingModel == "grok-4.3", AppState(preview: true).processingProvider == .xai else { throw failure("xAI model and provider did not persist") }
        try choose("s2t", prefix: "cleanup")
        try chooseModel("grok-4.6", prefix: "cleanup")
        guard state.creditCleanupProvider == .xai, state.creditCleanupModel == "grok-4.6", state.creditCleanupHost.isEmpty,
              AppState(preview: true).creditCleanupProvider == .xai else { throw failure("Subscription xAI choice did not persist independently") }
        let selectedBeforeEmptyCatalog = state.creditCleanupModel
        let empty = #"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"test","models":[]}"#
        state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(empty.utf8)))
        try choose("openrouter", prefix: "cleanup")
        try choose("s2t", prefix: "cleanup")
        guard state.cleanupUsesCredits, state.creditCleanupModel == selectedBeforeEmptyCatalog,
              pane.controls["cleanup.keys"] != nil,
              (try picker("cleanup")).selectedItem?.isEnabled == true else {
            throw failure("S2T must stay selectable with setup guidance and preserve its saved model when the catalog is empty")
        }
        guard !window.isVisible else { throw failure("Provider verification showed a window") }
        print("PASS: one Local models provider with installed-only model menus for all tasks, no download submenu or uninstalled choices, live inventory updates, preserved drafts, missing-model placeholders, managed routing, custom endpoint restoration, persisted choices, native actions and recording guards. Isolated fixture files only; no downloads or inference.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ModelProviderProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
