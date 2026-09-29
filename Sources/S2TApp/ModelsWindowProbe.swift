import AppKit
import SwiftUI
import S2TCore

@MainActor enum ModelsWindowProbe {
    static func run() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        let pane = controller.modelsPane
        if ProcessInfo.processInfo.environment["S2T_MODELS_BENCHMARK"] == "1" {
            try benchmark(controller, window: window)
            return
        }
        guard pane.navigation.page == .settings, !pane.scroll.isHidden,
              pane.localPane.view.isHidden, pane.comparison.isHidden else {
            throw failure("Models must open on its single settings page")
        }
        try verifyBenchmark(state)
        try verifySinglePage(pane, window: window)
        try verifyRecommendations()
        try verifyProviderSubmenus()
        try verifyXAIVisibility()
        try verifyLocalProvider()
        let originalModels = [state.transcriptionModel, state.processingModel]
        (pane.controls["models.compare"] as? NSButton)?.performClick(nil)
        guard pane.navigation.pageTitle == "Compare models", !pane.comparison.isHidden, pane.scroll.isHidden else {
            throw failure("Compare models must open as a sub-page")
        }
        pane.navigation.back()
        guard pane.navigation.page == .settings, !pane.scroll.isHidden,
              originalModels == [state.transcriptionModel, state.processingModel] else {
            throw failure("Opening and leaving a sub-page must not select a model")
        }
        try ModelChoiceProbe.verify(pane)
        try verifyButtonTitles(pane.view)
        let changingTitle = SettingsFormButton(title: "Save", target: nil, action: nil)
        changingTitle.title = "Saved"
        changingTitle.font = .systemFont(ofSize: 15, weight: .medium)
        changingTitle.isEnabled = false
        changingTitle.isEnabled = true
        try verifyButtonTitles(changingTitle)
        guard changingTitle.attributedTitle.string == "Saved", changingTitle.attributedAlternateTitle.string == "Saved" else {
            throw failure("Changing a label left stale normal or pressed text")
        }
        for primary in [false, true, false] {
            changingTitle.primary = primary
            try verifyButtonTitles(changingTitle)
            guard changingTitle.appearance == nil,
                  changingTitle.bezelColor == nil,
                  changingTitle.contentTintColor == nil else {
                throw failure("Changing button prominence retained a forced theme or stale tint")
            }
            if #available(macOS 26, *) {
                guard changingTitle.bezelStyle == .rounded, changingTitle.borderShape == .automatic,
                      changingTitle.tintProminence == (primary ? .primary : .none) else {
                    throw failure("Changing prominence must retain system button styling")
                }
            }
        }
        guard ["speech", "cleanup"].allSatisfy({ pane.controls[$0 + ".provider"]?.isHiddenOrHasHiddenAncestor == false }),
              pane.controls["credits.mode"] == nil,
              pane.controls["model.prompt.finder"] == nil else {
            throw failure("Models must show every task's settings together on one page")
        }
        let provider = state.processingProvider
        let selectedModel = state.processingModel
        (pane.controls["models.local"] as? NSButton)?.performClick(nil)
        guard pane.scroll.isHidden, !pane.localPane.view.isHiddenOrHasHiddenAncestor, pane.navigation.pageTitle == "Local models",
              controller.showingModels, !controller.preview.running,
              state.processingProvider == provider, state.processingModel == selectedModel else {
            throw failure("Local models must open as a sub-page without changing the configured model")
        }
        pane.localPane.selectCategory(1)
        pane.navigation.back()
        pane.navigation.select(.local)
        guard pane.localPane.selectedCategory == "text" else { throw failure("Local task filter reset while navigating") }
        pane.navigation.select(.cleanup)
        guard pane.localPane.view.isHidden, !pane.scroll.isHidden else { throw failure("Leaving Local models failed") }
        guard pane.controls["cleanup.host"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.provider"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.choice"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.jev.mode"]?.isHiddenOrHasHiddenAncestor == false,
              !pane.controls.keys.contains(where: { $0.hasPrefix("models.expand.") }) else {
            throw failure("Task pages must show their settings as open sections without disclosure buttons")
        }
        pane.showSettings(containing: "cleanup.host")
        guard pane.controls["cleanup.choice"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.provider"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.host"]?.isHiddenOrHasHiddenAncestor == false else {
            throw failure("Hosting must remain beside the model settings")
        }
        pane.navigation.back()
        guard pane.navigation.page == .settings else {
            throw failure("Back must return directly to Models")
        }
        pane.navigation.select(.cleanup)
        guard pane.controls["cleanup.preset"] == nil,
              pane.controls["cleanup.model.save"] is NSButton,
              pane.controls["cleanup.host.save"] == nil else {
            throw failure("Custom IDs need Save; immediate selections must not have redundant Save actions")
        }
        let retainedProvider = pane.controls["cleanup.provider"]
        let retainedModel = pane.controls["cleanup.model"]
        for _ in 0..<20 {
            pane.navigation.select(.speech)
            pane.navigation.select(.cleanup)
        }
        (pane.controls["cleanup.keys"] as? NSButton)?.performClick(nil)
        guard controller.showingKeys, controller.apiKeysPane.editing.account == "openrouter" else {
            throw failure("Provider setup must open the selected provider's key editor")
        }
        controller.showModels()
        guard pane.navigation.page == .settings, !pane.scroll.isHidden else {
            throw failure("Re-entering Models must open its settings page")
        }
        guard pane.controls["cleanup.provider"] === retainedProvider,
              pane.controls["cleanup.model"] === retainedModel else {
            throw failure("Unchanged navigation must retain controls rather than rebuild every section")
        }
        pane.showSettings(containing: "cleanup.reasoning")
        window.contentView?.layoutSubtreeIfNeeded()
        guard let reasoning = pane.controls["cleanup.reasoning"], let hostMenu = pane.controls["cleanup.host"] as? NSPopUpButton,
              pane.controls["cleanup.fast"] == nil,
              hostMenu.itemArray.contains(where: { $0.representedObject as? String == ModelsPane.fastestHost }) else {
            throw failure("OpenRouter speed must be a Fastest available host choice, not a separate switch")
        }
        guard let choices = reasoning as? NSPopUpButton,
              choices.itemArray.compactMap({ $0.representedObject as? String }) == OpenRouterReasoningCatalog.shared.efforts(for: state.processingModel).map(\.rawValue) else {
            throw failure("The reasoning menu must include every selectable effort")
        }
        state.setRouterOptions(.init(reasoning: .none), model: state.processingModel)
        guard state.routerOptions(model: state.processingModel).reasoning == .none else {
            throw failure("A saved reasoning effort changed without the user's choice")
        }
        state.setRouterOptions(.init(), model: state.processingModel)
        let reasoningFrame = reasoning.convert(reasoning.bounds, to: pane.view)
        let modelFrame = pane.controls["cleanup.choice"]!.convert(pane.controls["cleanup.choice"]!.bounds, to: pane.view)
        let hostFrame = hostMenu.convert(hostMenu.bounds, to: pane.view)
        guard !reasoningFrame.intersects(modelFrame), !reasoningFrame.intersects(hostFrame),
              reasoningFrame.maxY < hostFrame.minY, hostFrame.maxY < modelFrame.minY,
              abs(reasoningFrame.maxX - modelFrame.maxX) < 1, abs(hostFrame.maxX - modelFrame.maxX) < 1 else {
            throw failure("Model, Host and Reasoning must be separate right-aligned rows in that order")
        }
        let originalChoice = state.processingModel
        let originalHost = state.routerEndpoint
        try ModelChoiceProbe.choose("cleanup.choice", "openai/gpt-oss-20b", in: pane)
        guard state.processingModel == "openai/gpt-oss-20b",
              pane.controls["cleanup.choice"] is NSPopUpButton else { throw failure("Native model selection failed") }
        state.processingModel = originalChoice
        state.routerEndpoint = originalHost
        pane.rebuild()
        let fixture = Data(#"{"models":[{"slug":"fixture-reasoning","display_name":"Fixture reasoning","visibility":"list","supported_reasoning_levels":[{"effort":"low","description":"Quick"},{"effort":"high","description":"Deep"}],"service_tiers":[{"id":"priority","name":"Fast"}],"input_modalities":["text","image"]},{"slug":"fixture-text","display_name":"Fixture text","visibility":"list","supported_reasoning_levels":[],"input_modalities":["text"]}]}"#.utf8)
        pane.setCatalog(try CodexModelCatalog.decode(fixture))
        func choose(_ id: String, _ value: String) throws {
            try ModelChoiceProbe.choose(id, value, in: pane)
        }
        let previousSpeechProvider = state.transcriptionProvider
        let previousSpeechModel = state.routerTranscriptionModel
        state.transcriptionProvider = .openRouter
        state.routerTranscriptionModel = "fixture/custom-speech"
        pane.rebuild()
        guard pane.controls["speech.choice"] is NSPopUpButton,
              (pane.controls["speech.model"] as? NSTextField)?.stringValue == "fixture/custom-speech" else {
            throw failure("Catalog refresh must preserve the custom model")
        }
        try choose("speech.model", "nvidia/parakeet-tdt-0.6b-v3")
        guard state.routerTranscriptionModel == "nvidia/parakeet-tdt-0.6b-v3" else {
            throw failure("Custom speech model did not persist")
        }
        state.transcriptionProvider = previousSpeechProvider
        state.routerTranscriptionModel = previousSpeechModel
        pane.rebuild()
        let savedHost = state.routerEndpoint
        let savedModel = state.processingModel
        state.routerEndpoint = ""
        pane.rebuild()
        try choose("cleanup.reasoning", "high")
        try choose("cleanup.host", ModelsPane.fastestHost)
        guard state.routerEndpoint.isEmpty,
              state.routerOptions(model: savedModel) == OpenRouterOptions(reasoning: .high, fast: true),
              AppState(preview: true).routerOptions(model: savedModel) == OpenRouterOptions(reasoning: .high, fast: true) else {
            throw failure("OpenRouter options do not persist independently per task")
        }
        state.processingModel = "fixture/other"
        pane.rebuild()
        guard (pane.controls["cleanup.reasoning"] as? NSPopUpButton)?.selectedItem?.representedObject as? String == "",
              (pane.controls["cleanup.host"] as? NSPopUpButton)?.selectedItem?.representedObject as? String == "" else {
            throw failure("OpenRouter options leaked between models")
        }
        state.processingModel = savedModel
        state.routerEndpoint = savedHost
        let originalCreditModel = state.creditCleanupModel
        for model in ["openai/gpt-5.6-luna", "meta/muse-spark-1.3-contributor", "openai/gpt-4.1-mini", "fixture/unknown"] {
            let levels = OpenRouterReasoningCatalog.shared.efforts(for: model).map(\.rawValue)
            for credits in [false, true] {
                state.cleanupUsesCredits = credits
                state.processingModel = model; state.creditCleanupModel = model
                state.setRouterOptions(.init(reasoning: .minimal), model: model)
                state.creditCleanupOptions = .init(reasoning: .minimal)
                pane.rebuild()
                for prefix in ["cleanup"] {
                    guard let popup = pane.controls[prefix + ".reasoning"] as? NSPopUpButton,
                          popup.itemArray.compactMap({ $0.representedObject as? String }) == levels,
                          popup.isEnabled == (levels.count > 1),
                          popup.isHiddenOrHasHiddenAncestor == (levels.count <= 1),
                          let selected = popup.selectedItem?.representedObject as? String, levels.contains(selected) else {
                        throw failure("\(prefix) reasoning choices do not match \(model), credits=\(credits)")
                    }
                }
            }
        }
        state.processingModel = savedModel; state.creditCleanupModel = originalCreditModel
        state.cleanupUsesCredits = true
        state.creditCleanupProvider = .openRouter
        state.creditCleanupModel = CreditModel.defaults[0].model
        state.creditCleanupHost = ""
        pane.rebuild()
        guard pane.controls["cleanup.reasoning"] is NSPopUpButton, pane.controls["cleanup.host"] is NSPopUpButton else {
            throw failure("S2T must share OpenRouter request options")
        }
        guard let creditHosts = pane.controls["cleanup.host"] as? NSPopUpButton,
              !creditHosts.isHiddenOrHasHiddenAncestor,
              creditHosts.itemArray.contains(where: { $0.representedObject as? String == "cerebras/fp16" && $0.title == "Cerebras" }) else {
            throw failure("S2T credits must expose the authorized Cerebras host beside Model")
        }
        try choose("cleanup.host", "cerebras/fp16")
        guard state.creditCleanupHost == "cerebras/fp16" else {
            throw failure("Selecting Cerebras did not save the S2T credit host")
        }
        let creditCatalog = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test","openRouterCatalog":true,"models":[{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-120b","host":"","title":"GPT-OSS 120B"},{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-120b","host":"cerebras/fp16","title":"GPT-OSS 120B"},{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-20b","host":"","title":"GPT-OSS 20B"}]}"#
        state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(creditCatalog.utf8)))
        state.creditCleanupModel = "openai/gpt-oss-20b"
        state.creditCleanupHost = ""
        pane.rebuild()
        guard (pane.controls["cleanup.host"] as? NSPopUpButton)?.itemArray.contains(where: { $0.representedObject as? String == ModelsPane.fastestHost }) == true else {
            throw failure("S2T automatic hosting must offer Fastest available")
        }
        try choose("cleanup.choice", "openai/gpt-oss-120b")
        guard state.creditCleanupModel == "openai/gpt-oss-120b", state.creditCleanupHost == "cerebras/fp16" else {
            throw failure("Choosing GPT-OSS 120B with S2T credits must retain its Cerebras route")
        }
        state.cleanupUsesCredits = false
        pane.rebuild()
        try choose("cleanup.provider", "codex")
        try choose("cleanup.model", "fixture-reasoning")
        guard pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["codex.executable"]?.isHiddenOrHasHiddenAncestor == false else {
            throw failure("Codex connection must be directly available")
        }
        pane.showSettings(containing: "codex.executable")
        guard pane.controls["codex.executable"]?.isHiddenOrHasHiddenAncestor == false else {
            throw failure("Codex connection is unreachable")
        }
        try choose("cleanup.reasoning", "high")
        guard let fast = pane.controls["cleanup.fast"] as? NSSwitch, fast.isEnabled else { throw failure("Fast option missing") }
        try choose("cleanup.fast", "fast")
        guard state.codexOptions(model: "fixture-reasoning") == CodexOptions(reasoning: "high", fast: true),
              AppState(preview: true).codexOptions(model: "fixture-reasoning") == CodexOptions(reasoning: "high", fast: true) else { throw failure("Codex options did not persist") }
        try choose("cleanup.model", "fixture-text")
        guard pane.controls["cleanup.fast"] == nil,
              pane.controls["cleanup.reasoning"] == nil else { throw failure("Unsupported Codex reasoning and fast mode must be absent") }
        try choose("cleanup.model", "fixture-reasoning")
        guard (pane.controls["cleanup.fast"] as? NSSwitch)?.state == .on else { throw failure("Switching models lost options") }
        try choose("cleanup.provider", "openrouter")
        try ModelChoiceProbe.beginCustom("cleanup", in: pane)
        guard let field = pane.controls["cleanup.model"] as? NSTextField else { throw failure("Model editor missing") }
        window.contentView?.layoutSubtreeIfNeeded()
        guard (pane.controls["cleanup.provider"] as? NSPopUpButton)?.bezelStyle == .rounded,
              field.isBezeled, field.bezelStyle == .roundedBezel, field.focusRingType == .default,
              field.bounds.height >= field.intrinsicContentSize.height - 1 else {
            throw failure("Model controls must use native dropdowns, text fields and focus rings")
        }
        guard window.makeFirstResponder(field), let editor = field.currentEditor() else {
            throw failure("Native model field cannot receive keyboard focus")
        }
        editor.selectedRange = NSRange(location: 0, length: field.stringValue.utf16.count)
        guard editor.selectedRange.length == field.stringValue.utf16.count else { throw failure("Text selection stopped working") }
        window.makeFirstResponder(nil)
        guard let editingWindow = window as? SettingsEditorWindow else { throw failure("Missing shared settings editing behavior") }
        func focusDraft() throws {
            guard window.makeFirstResponder(field), let editor = field.currentEditor() else { throw failure("Cannot focus model editor") }
            editor.string = "fixture/unsaved"
        }
        let savedBeforeDraft = state.processingModel
        try focusDraft()
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        editingWindow.sendEvent(escape)
        guard field.currentEditor() == nil, field.stringValue == "fixture/unsaved", state.processingModel == savedBeforeDraft else {
            throw failure("Escape must end editing without silently activating a draft")
        }
        try focusDraft()
        let inside = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        func click(_ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        guard !editingWindow.handleEditingEvent(click(inside)), field.currentEditor() != nil else {
            throw failure("Clicking inside the field must retain editing")
        }
        window.makeFirstResponder(nil)
        guard field.currentEditor() == nil,
              field.stringValue == "fixture/unsaved", state.processingModel == savedBeforeDraft else {
            throw failure("Click-away must preserve the draft without saving or consuming the click")
        }
        try focusDraft()
        field.currentEditor()?.string = "fixture/return"
        (field.currentEditor() as? NSTextView)?.insertNewline(nil)
        guard state.processingModel == "fixture/return" else { throw failure("Return must perform the same explicit save as the Save button") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let field = pane.controls["cleanup.model"] as? NSTextField else { throw failure("Autosave lost the model editor") }
        let savedAfterReturn = state.processingModel
        field.stringValue = "cerebras/fp16"; field.sendAction(field.action, to: field.target)
        guard state.processingModel == savedAfterReturn else { throw failure("Hosting endpoint accepted as model") }
        field.stringValue = "fixture/selected"; field.sendAction(field.action, to: field.target)
        guard state.processingModel == "fixture/selected", AppState(preview: true).processingModel == "fixture/selected" else { throw failure("Model autosave failed") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let hosts = try OpenRouterHost.decode(Data(#"{"data":{"endpoints":[{"tag":"fixture/host","provider_name":"Fixture host","status":0,"pricing":{"prompt":"0.000001","completion":"0.000002"},"throughput_last_30m":{"p50":120}}]}}"#.utf8))
        pane.setHosts(hosts, model: state.processingModel)
        try choose("cleanup.host", "fixture/host")
        guard state.routerEndpoint == "fixture/host", AppState(preview: true).routerEndpoint == "fixture/host" else { throw failure("Host menu did not persist the selected endpoint") }
        try choose("cleanup.host", "")
        guard state.routerEndpoint.isEmpty, !state.routerOptions(model: state.processingModel).fast else { throw failure("Automatic hosting retained a provider pin or fastest routing") }
        // Real GPT-OSS 120B hosts share titles (two Amazon Bedrock, two DeepInfra bf16). A shifted
        // menu displayed CoreWeave after choosing Cerebras.
        func endpoint(_ tag: String, _ name: String, _ quantization: String?) -> String {
            #"{"tag":"\#(tag)","provider_name":"\#(name)","status":0,"#
                + (quantization.map { #""quantization":"\#($0)","# } ?? "") + #""pricing":{"prompt":"0.000001","completion":"0.000002"}}"#
        }
        let sharedTitles = [endpoint("amazon-bedrock", "Amazon Bedrock", "unknown"), endpoint("amazon-bedrock/eu-west-1", "Amazon Bedrock", "unknown"),
                            endpoint("akashml/bf16", "AkashML", "bf16"), endpoint("coreweave/fp4", "CoreWeave", "fp4"),
                            endpoint("deepinfra/bf16", "DeepInfra", "bf16"), endpoint("deepinfra/turbo", "DeepInfra", "bf16"),
                            endpoint("cerebras/fp16", "Cerebras", "fp16")]
        pane.setHosts(try OpenRouterHost.decode(Data((#"{"data":{"endpoints":["# + sharedTitles.joined(separator: ",") + "]}}").utf8)),
                      model: state.processingModel)
        for tag in ["cerebras/fp16", "amazon-bedrock/eu-west-1", "amazon-bedrock", "deepinfra/turbo", "coreweave/fp4"] {
            try choose("cleanup.host", tag)
            pane.rebuild()
            pane.setHosts(try OpenRouterHost.decode(Data((#"{"data":{"endpoints":["# + sharedTitles.joined(separator: ",") + "]}}").utf8)),
                          model: state.processingModel)
            guard let menu = pane.controls["cleanup.host"] as? NSPopUpButton, state.routerEndpoint == tag,
                  menu.selectedItem?.representedObject as? String == tag,
                  menu.numberOfItems == sharedTitles.count + 2,
                  Set(menu.itemArray.map(\.title)).count == menu.numberOfItems else {
                throw failure("Host menu must keep every host and show the saved \(tag) after rebuilding")
            }
        }
        try choose("cleanup.host", "")
        state.routerEndpoint = "fixture/host"
        guard state.saveProcessingModel("fixture/fable-5.1", for: .openRouter) == nil,
              state.routerEndpoint.isEmpty else { throw failure("Changing a model carried its old hosting provider") }
        pane.rebuild()
        guard let draftField = pane.controls["cleanup.model"] as? NSTextField,
              window.makeFirstResponder(draftField), let editor = draftField.currentEditor() else { throw failure("Could not edit model draft") }
        editor.string = "fixture/unsaved-draft"
        pane.setHosts(hosts, model: "fixture/fable-5.1")
        guard draftField.currentEditor()?.string == "fixture/unsaved-draft" else { throw failure("Provider refresh discarded an active model draft") }
        window.makeFirstResponder(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.refresh()
        window.contentView?.layoutSubtreeIfNeeded()
        guard !window.isVisible, controller.showingModels, !controller.preview.running,
              controller.sectionBar.isHiddenOrHasHiddenAncestor,
              controller.sidebar.table.numberOfRows == 7, pane.view.bounds.width > 400,
              pane.view.bounds.height > 450, state.phase == .idle else { throw failure("Models window geometry or isolation failed: visible=\(window.isVisible), showing=\(controller.showingModels), preview=\(controller.preview.running), sectionHidden=\(controller.sectionBar.isHiddenOrHasHiddenAncestor), rows=\(controller.sidebar.table.numberOfRows), bounds=\(pane.view.bounds), phase=\(state.phase)") }
        for (id, control) in pane.controls where !control.isHiddenOrHasHiddenAncestor {
            let frame = control.convert(control.bounds, to: pane.view)
            guard control.bounds.width >= (id.hasSuffix(".dismiss") ? 24 : 25), frame.minX >= 0, frame.maxX <= pane.view.bounds.width else { throw failure("Clipped model control: \(id) \(frame)") }
        }
        func verifyNativeControls(_ view: NSView) throws {
            if let button = view as? SettingsFormButton {
                guard button.bezelStyle == .rounded, button.bezelColor == nil,
                      button.contentTintColor == nil, button.appearance == nil else {
                    throw failure("Settings actions override native shape or contrast")
                }
            }
            for child in view.subviews { try verifyNativeControls(child) }
        }
        try verifyNativeControls(pane.view)
        state.phase = .recording
        pane.rebuild()
        guard pane.controls.filter({ !$0.key.hasPrefix("models.") }).values.allSatisfy({ !$0.isEnabled }) else { throw failure("Models can change during dictation") }
        state.phase = .idle
        pane.rebuild()
        window.contentView?.layoutSubtreeIfNeeded()
        guard let document = pane.scroll.documentView,
              document.bounds.height > 0, pane.scroll.hasVerticalScroller else { throw failure("Model controls need a scroll container for expanded settings") }
        controller.showAPIKeys()
        let keys = controller.apiKeysPane
        for theme in ["light", "dark", "light", "system"] {
            state.menuAppearance = theme
            controller.refresh()
            window.contentView?.layoutSubtreeIfNeeded()
            try verifyButtonTitles(pane.view)
            let expected = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            for root in [pane.view, pane.scroll, keys.view] {
                guard root.appearance == nil else { throw failure("Model/key pane overrides the window theme") }
                func check(_ view: NSView) throws {
                    guard view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected else {
                        throw failure("Model/key control \(type(of: view)) failed to inherit \(theme) appearance")
                    }
                    for child in view.subviews { try check(child) }
                }
                try check(root)
                if let scroll = root as? SettingsScrollView {
                    guard !scroll.drawsBackground, !scroll.contentView.drawsBackground else {
                        throw failure("Model scroll view must expose the shared SwiftUI background")
                    }
                }
            }
        }
        guard keys.editing.account == nil, !window.isVisible else {
            throw failure("Theme checks exposed keys or showed the window")
        }
        controller.sidebar.selectAppearance()
        guard !controller.showingModels, pane.view.isHidden, controller.previewHost?.isHidden == false else { throw failure("Return to Appearance failed") }
        print("Models window verified: one settings page for every task, provider submenus with bounded OpenRouter recommendations and Custom model ID, Local models and Compare models sub-pages, provider/model controls, reasoning and fast capability checks, per-model persistence, scroll layout, light/dark/system inheritance, masked key fields and appearance navigation. No live providers or screen capture.")
    }

    /// The page shows all tasks at once, in order, as right-aligned native rows without a task switcher.
    private static func verifySinglePage(_ pane: ModelsPane, window: NSWindow) throws {
        window.contentView?.layoutSubtreeIfNeeded()
        func contains(_ type: AnyClass, in view: NSView) -> Bool {
            view.isKind(of: type) || view.subviews.contains { contains(type, in: $0) }
        }
        guard !contains(NSSegmentedControl.self, in: pane.scroll) else { throw failure("The Models page must not hide tasks behind a task switcher") }
        let anchors = [ModelsSection.speech, .cleanup].compactMap { pane.sectionAnchors[$0] }
        guard anchors.count == 2, zip(anchors, anchors.dropFirst()).allSatisfy({ $0.frame.minY < $1.frame.minY }) else {
            throw failure("Speech and cleanup sections must appear in order on one page")
        }
        for section in [ModelsSection.speech, .cleanup] {
            pane.navigation.select(section)
            window.contentView?.layoutSubtreeIfNeeded()
            guard let anchor = pane.sectionAnchors[section], pane.scroll.documentVisibleRect.intersects(anchor.frame) else {
                throw failure("Selecting a task must reveal its section")
            }
        }
        pane.navigation.showOverview()
        for prefix in ["speech", "cleanup"] {
            guard let menu = pane.controls[prefix + ".choice"] as? NSPopUpButton ?? pane.controls[prefix + ".mode"] as? NSPopUpButton,
                  let provider = pane.controls[prefix + ".provider"] else { throw failure("Missing \(prefix) provider or model menu") }
            let branches = menu.itemArray.filter { !$0.isHidden }
            guard !branches.isEmpty, branches.allSatisfy({ $0.submenu != nil && $0.title != "More models" }),
                  branches.contains(where: { $0.title == "Local" }) else {
                throw failure("\(prefix) model menu must contain provider submenus, including Local")
            }
            let modelFrame = menu.convert(menu.bounds, to: pane.view)
            let providerFrame = provider.convert(provider.bounds, to: pane.view)
            guard abs(modelFrame.maxX - providerFrame.maxX) < 1, providerFrame.minY > modelFrame.maxY else {
                throw failure("\(prefix) Provider and Model must be right-aligned rows, Provider first")
            }
        }
        guard (5...8).contains(ModelRecommendations.cleanup.count),
              (5...8).contains(ModelRecommendations.openRouterSpeech.count),
              !(ModelRecommendations.cleanup).contains(where: { $0.model == OpenRouterOptions.contributorModel }),
              (ModelRecommendations.cleanup + ModelRecommendations.creditSpeech).allSatisfy({ !$0.detail.isEmpty }) else {
            throw failure("Recommendations must be short, explain themselves and never require data-sharing consent")
        }
        for id in ["models.local", "models.compare"] {
            guard let row = pane.controls[id] as? NSButton, !row.isHiddenOrHasHiddenAncestor, row.bounds.width > 200 else {
                throw failure("Missing visible " + id + " row")
            }
        }
    }

    private static func verifyProviderSubmenus() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let before = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(before, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        let balance = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test","openRouterCatalog":true,"models":[{"provider":"assemblyai","operation":"transcription","model":"universal-3-5-pro","host":"","title":"Universal 3.5 Pro"},{"provider":"xai","operation":"transcription","model":"grok-voice-transcribe-2.0","host":"","title":"Grok Voice 2.0"},{"provider":"xai","operation":"transcription","model":"grok-voice-transcribe-1.0","host":"","title":"Grok Voice 1.0"}]}"#
        state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(balance.utf8)))
        state.speechUsesCredits = true
        let pane = ModelsPane(state: state)
        _ = pane.view
        func menu(_ prefix: String, _ provider: String) -> NSMenu? {
            (pane.controls[prefix + ".choice"] as? NSPopUpButton)?.menu?.items.first { $0.identifier?.rawValue == provider }?.submenu
        }
        guard let speech = pane.controls["speech.choice"] as? NSPopUpButton,
              speech.itemArray.filter({ !$0.isHidden }).map(\.title) == ["OpenRouter", "AssemblyAI", "Local", "xAI"],
              ModelChoiceProbe.values(in: menu("speech", "openrouter")).count == ModelRecommendations.openRouterSpeech.count + 1,
              ModelChoiceProbe.values(in: menu("speech", "xai")) == TranscriptionProvider.xaiModels + [ModelsPane.personalXAI] else {
            throw failure("S2T must group each actual provider, list all xAI models and bound OpenRouter to recommendations plus Custom")
        }
        let cleanupBefore = state.processingModel
        let stale = ModelChoiceProbe.item("grok-voice-transcribe-1.0", in: menu("speech", "xai"))!
        try ModelChoiceProbe.choose("speech.choice", "microsoft/mai-transcribe-2", in: pane)
        guard state.speechUsesCredits, state.creditSpeechProvider == .openRouter,
              state.creditTranscriptionModel == "microsoft/mai-transcribe-2",
              state.processingModel == cleanupBefore else {
            throw failure("A nested model choice changed funding or another task")
        }
        stale.menu?.performActionForItem(at: stale.menu!.index(of: stale))
        guard state.creditSpeechProvider == .openRouter else { throw failure("A stale submenu action changed the selected service") }
        try ModelChoiceProbe.choose("speech.choice", "grok-voice-transcribe-1.0", in: pane)
        guard state.speechUsesCredits, state.creditSpeechProvider == .xai else { throw failure("Nested xAI selection lost S2T routing") }
        try ModelChoiceProbe.choose("speech.choice", "endpoint", in: pane)
        guard !state.speechUsesCredits, state.transcriptionProvider == .local, pane.controls["speech.url"] != nil else {
            throw failure("Local submenu selection must use the local connection and expose its endpoint")
        }
        try ModelChoiceProbe.choose("cleanup.choice", "grok-4.6", in: pane)
        guard state.processingProvider == .xai, pane.controls["cleanup.reasoning"] == nil, pane.controls["cleanup.host"] == nil else {
            throw failure("Direct provider submenu selection must refresh applicable options")
        }
        try ModelChoiceProbe.choose("cleanup.choice", "anthropic/claude-haiku-4.5", in: pane)
        guard state.processingProvider == .openRouter,
              pane.controls["cleanup.reasoning"]?.isHiddenOrHasHiddenAncestor == true else {
            throw failure("A model without adjustable reasoning must hide its reasoning row")
        }
        try ModelChoiceProbe.choose("cleanup.choice", "openai/gpt-oss-120b", in: pane)
        guard pane.controls["cleanup.reasoning"]?.isHiddenOrHasHiddenAncestor == false,
              ModelChoiceProbe.values(in: (pane.controls["cleanup.reasoning"] as? NSPopUpButton)?.menu) == ["", "low", "medium", "high"] else {
            throw failure("Switching to GPT-OSS must restore only its advertised reasoning efforts")
        }
        let retained = ModelChoiceProbe.item("grok-4.6", in: menu("cleanup", "xai"))!
        state.phase = .recording
        retained.menu?.performActionForItem(at: retained.menu!.index(of: retained))
        guard state.processingProvider == .openRouter else { throw failure("A nested action changed models during recording") }
        state.phase = .idle
        pane.rebuild()
        try ModelChoiceProbe.choose("cleanup.provider", "s2t", in: pane)
        try ModelChoiceProbe.choose("cleanup.choice", "openai/gpt-oss-120b", in: pane)
        try ModelChoiceProbe.choose("cleanup.reasoning", "high", in: pane)
        try ModelChoiceProbe.choose("cleanup.choice", "google/gemini-3.8-flash", in: pane)
        try ModelChoiceProbe.choose("cleanup.choice", "openai/gpt-oss-120b", in: pane)
        guard state.creditCleanupOptions.reasoning == .high else { throw failure("A recommendation replaced the saved S2T reasoning level") }
        state.speechUsesCredits = true
        pane.rebuild()
        let removed = ModelChoiceProbe.item("grok-voice-transcribe-2.0", in: menu("speech", "xai"))!
        let savedSpeech = state.creditTranscriptionModel
        let empty = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test","models":[]}"#
        state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(empty.utf8)))
        removed.menu?.performActionForItem(at: removed.menu!.index(of: removed))
        guard state.creditTranscriptionModel == savedSpeech else { throw failure("A submenu action accepted a model after catalog authorization was removed") }
        print("PASS: provider submenus, bounded OpenRouter choices, nested routing, task/funding isolation, conditional reasoning, stale actions and recording guards.")
    }

    private static func verifyXAIVisibility() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let before = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(before, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        let pane = ModelsPane(state: state)
        state.xaiKey = "isolated-xai-key"
        _ = pane.view
        let empty = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test","models":[]}"#
        // Cover the bundled catalog and an empty authenticated catalog: neither offers xAI.
        for emptyCatalog in [false, true] {
            if emptyCatalog { state.applyCreditBalance(try JSONDecoder().decode(CreditBalance.self, from: Data(empty.utf8))) }
            state.speechUsesCredits = true; state.cleanupUsesCredits = true
            pane.rebuild()
            for (prefix, category) in [("speech", "speech"), ("cleanup", "text")] {
                let routes = [state.speechUsesCredits, state.cleanupUsesCredits]
                let models = [state.creditTranscriptionModel, state.creditCleanupModel]
                guard let picker = pane.controls[prefix + ".choice"] as? NSPopUpButton,
                      let branch = picker.menu?.items.first(where: { $0.identifier?.rawValue == "xai" }),
                      branch.title == "xAI", !branch.isHidden, branch.isEnabled, let menu = branch.submenu,
                      let personal = ModelChoiceProbe.item(ModelsPane.personalXAI, in: menu), personal.isEnabled else {
                    throw failure("xAI must stay visible with a personal-key action for \(prefix), empty catalog=\(emptyCatalog)")
                }
                let xaiModels = menu.items.filter { ($0.representedObject as? String)?.hasPrefix("grok-") == true }
                guard xaiModels.count == (prefix == "speech" ? 2 : 1), xaiModels.allSatisfy({ !$0.isEnabled && $0.toolTip?.contains("S2T credits") == true }) else {
                    throw failure("Unconfigured S2T xAI models must explain their personal-key requirement")
                }
                menu.performActionForItem(at: menu.index(of: xaiModels[0]))
                guard state.usesCredits(for: category), models == [state.creditTranscriptionModel, state.creditCleanupModel] else {
                    throw failure("An unavailable xAI model changed the S2T route")
                }
                menu.performActionForItem(at: menu.index(of: personal))
                let index = prefix == "speech" ? 0 : prefix == "cleanup" ? 1 : 2
                let after = [state.speechUsesCredits, state.cleanupUsesCredits]
                guard !state.usesCredits(for: category), after.enumerated().allSatisfy({ $0.offset == index || $0.element == routes[$0.offset] }),
                      models == [state.creditTranscriptionModel, state.creditCleanupModel],
                      (pane.controls[prefix + ".provider"] as? ModelProviderPicker)?.currentValue == "xai",
                      pane.controls[prefix + ".host"] == nil,
                      prefix != "speech" || state.transcriptionKey == "isolated-xai-key",
                      prefix != "cleanup" || state.processingKey == "isolated-xai-key" else {
                    throw failure("Use xAI API key must switch only its own task and retain the S2T model")
                }
            }
        }
        print("PASS: xAI remains visible for every task with bundled/empty S2T catalogs, unavailable models stay disabled, and the explicit personal-key action preserves other tasks and saved credit settings.")
    }

    /// Recommended choices save their model, host and a fast default reasoning level together.
    private static func verifyRecommendations() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let before = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(before, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        guard state.processingProvider == .openRouter,
              state.processingModel == "openai/gpt-oss-120b",
              state.routerEndpoint == "cerebras/fp16",
              state.routerOptions(model: state.processingModel).reasoning == .low else {
            throw failure("Fresh model defaults must use GPT-OSS 120B on Cerebras with low reasoning")
        }
        defaults.setPersistentDomain(["fallbackModel": "openai/gpt-oss-120b"], forName: "com.s2t.preview")
        let existing = AppState(preview: true)
        guard existing.routerEndpoint.isEmpty,
              existing.routerOptions(model: existing.processingModel).reasoning == .automatic else {
            throw failure("New defaults changed an existing automatic-host choice")
        }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let pane = ModelsPane(state: state)
        _ = pane.view
        func choose(_ id: String, _ value: String) throws { try ModelChoiceProbe.choose(id, value, in: pane) }
        let cleanupMenu = pane.controls["cleanup.choice"] as? NSPopUpButton
        guard ModelRecommendations.cleanup.allSatisfy({ choice in ModelChoiceProbe.item(choice.model, in: cleanupMenu?.menu?.items.first { $0.title == "OpenRouter" }?.submenu) != nil }) else {
            throw failure("Cleanup recommendations must be listed first")
        }
        try choose("cleanup.choice", "google/gemini-3.8-flash")
        guard state.processingModel == "google/gemini-3.8-flash", state.routerEndpoint.isEmpty,
              state.routerOptions(model: state.processingModel).reasoning == .low else {
            throw failure("A recommended cleanup model must save automatic hosting and low reasoning")
        }
        try choose("cleanup.reasoning", "high")
        try choose("cleanup.choice", "openai/gpt-oss-120b")
        guard state.processingModel == "openai/gpt-oss-120b", state.routerEndpoint == "cerebras/fp16" else {
            throw failure("GPT-OSS 120B must keep its Cerebras host")
        }
        try choose("cleanup.choice", "google/gemini-3.8-flash")
        guard state.routerOptions(model: state.processingModel).reasoning == .high else {
            throw failure("Choosing a recommendation again replaced a saved reasoning level")
        }
        try choose("cleanup.provider", "xai")
        guard state.processingProvider == .xai, state.processingModel == "grok-4.6",
              state.processingEndpoint == nil else { throw failure("xAI cleanup mixed provider routes") }
        try choose("speech.provider", "xai")
        try choose("speech.choice", "grok-voice-transcribe-2.0")
        guard state.transcriptionProvider == .xai, state.transcriptionModel == "grok-voice-transcribe-2.0" else {
            throw failure("Grok Voice 2 did not select xAI speech")
        }
        try choose("speech.provider", "assemblyai")
        try choose("speech.mode", TranscriptionMode.fast.rawValue)
        guard state.transcriptionProvider == .assemblyAI, state.transcriptionMode == .fast else {
            throw failure("AssemblyAI did not select fast speech")
        }
        let host = NSHostingView(rootView: ModelBenchmarkView(presentation: ModelBenchmarkPresentation(), local: [], compact: true))
        for width: CGFloat in [420, 600] {
            host.frame = CGRect(x: 0, y: 0, width: width - 48, height: 360)
            host.layoutSubtreeIfNeeded()
            guard host.fittingSize.height <= 360 else { throw failure("Compact comparison exceeds the top section at \(width) points") }
        }
    }

    private static func verifyLocalProvider() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let before = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-quick-local-" + UUID().uuidString)
        defer {
            defaults.setPersistentDomain(before, forName: "com.s2t.preview")
            try? FileManager.default.removeItem(at: fixture)
        }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        state.localModels = LocalModels(preview: true, root: fixture)
        let pane = ModelsPane(state: state)
        _ = pane.view
        func choose(_ id: String, _ value: String) throws { try ModelChoiceProbe.choose(id, value, in: pane) }
        func save(_ id: String, _ value: String) {
            (pane.controls[id] as? NSTextField)?.stringValue = value
            (pane.controls[id + ".save"] as? NSButton)?.performClick(nil)
        }
        let originalSpeech = state.transcriptionProvider
        try choose("cleanup.provider", "local")
        guard state.processingProvider == .local, state.managedLocalModelID(for: "text") == nil,
              (pane.controls["cleanup.choice"] as? LocalModelChoicePicker)?.installed.isEmpty == true,
              pane.controls["cleanup.url"] != nil, pane.controls["cleanup.model"] != nil,
              state.transcriptionProvider == originalSpeech else {
            throw failure("Local models without installs must offer a custom endpoint without changing other tasks")
        }
        let customURL = "http://localhost:1239/v1/chat/completions"
        save("cleanup.url", customURL)
        save("cleanup.model", "fixture-model")
        save("cleanup.url", "https://user:secret@example.test/v1")
        guard state.localProcessingURL == customURL, state.processingModel == "fixture-model" else {
            throw failure("Local endpoint validation or saving failed")
        }
        for category in ["speech", "text"] {
            let model = state.localModels.catalog.first { $0.category == category && state.localModels.memoryFits($0) }!
            let directory = fixture.appendingPathComponent("models/" + model.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["revision": model.revision]).write(to: directory.appendingPathComponent("installed.json"))
        }
        state.localModels.refreshInstalled()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        for (category, prefix) in [("text", "cleanup"), ("speech", "speech")] {
            try choose(prefix + ".provider", "openrouter")
            let otherSpeech = state.transcriptionProvider
            let otherCleanup = state.processingProvider
            try choose(prefix + ".provider", "local")
            guard let picker = pane.controls[prefix + ".choice"] as? LocalModelChoicePicker,
                  picker.installed.count == 1, picker.installed.allSatisfy({ $0.category == category }),
                  state.managedLocalModelID(for: category) == picker.installed.first?.id,
                  pane.controls[prefix + ".url"] == nil, pane.controls[prefix + ".model"] == nil,
                  prefix == "speech" || state.transcriptionProvider == otherSpeech,
                  prefix == "cleanup" || state.processingProvider == otherCleanup else {
                throw failure("Local models must list installed models for only its own task and hide endpoint editors")
            }
            try choose(prefix + ".choice", "endpoint")
            guard pane.controls[prefix + ".url"] != nil, state.managedLocalModelID(for: category) == nil else {
                throw failure("Custom endpoint must return from an installed model")
            }
            state.phase = .recording
            guard !state.chooseModelProvider("openrouter", category: category, personal: ["openrouter"], change: { _ in }) else {
                throw failure("Model provider changed during recording")
            }
            state.phase = .idle
        }
        guard state.localProcessingURL == customURL, state.processingModel == "fixture-model" else {
            throw failure("Switching installed models lost the custom endpoint configuration")
        }
        let hidden = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        hidden.contentView = pane.view
        defer { hidden.contentView = nil; hidden.close() }
        for width: CGFloat in [420, 600] {
            hidden.setContentSize(NSSize(width: width, height: 700))
            pane.view.layoutSubtreeIfNeeded()
            guard pane.view.bounds.width == width, !hidden.isVisible else { throw failure("Local provider settings must remain hidden and resizable: \(width) → \(pane.view.bounds.width)") }
        }
        print("PASS: one Local models provider, installed-only task lists, custom endpoint restoration, endpoint validation and recording guards.")
    }

    private static func verifyBenchmark(_ state: AppState) throws {
        let presentation = ModelBenchmarkPresentation()
        let local = state.localModels.catalog + ["en-US", "en-GB", "de-DE", "fr-FR", "ja-JP"].map(LocalModel.appleSpeech)
        let root = ModelBenchmarkView(presentation: presentation, local: local)
        let host = NSHostingView(rootView: ScrollView { root.padding(24) })
        let fixture = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        fixture.contentView = host
        defer { fixture.contentView = nil; fixture.close() }
        for width: CGFloat in [420, 600, 950] {
            fixture.setContentSize(NSSize(width: width, height: 700))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            guard let controls = presentation.layout["controls"], let plot = presentation.layout["plot"],
                  let chart = presentation.layout["chart"], abs(chart.width - plot.width) < 1,
                  controls.minX >= 0, controls.maxX <= plot.maxX, controls.maxY <= plot.minY, plot.width >= 120,
                  plot.maxX <= width - 48 + 1, presentation.selected == nil else {
                throw failure("Benchmark switches and chart overlap or clip at \(width): \(presentation.layout)")
            }
            let anchors = presentation.layout.filter { $0.key.hasPrefix("anchor.") }.map(\.value)
            let switches = BenchmarkCategory.allCases.compactMap { presentation.layout["switch." + $0.rawValue] }
            guard switches.count == 3,
                  zip(switches, switches.dropFirst()).allSatisfy({ $0.maxX < $1.minX }),
                  switches.allSatisfy({ abs($0.midY - controls.midY) < 1 }) else {
                throw failure("Scoring switches must sit in one compact row above the chart")
            }
            guard !anchors.isEmpty, anchors.allSatisfy({
                $0.width <= 1.1 && $0.height <= 1.1 && chart.insetBy(dx: -1, dy: -1).contains($0)
            }) else { throw failure("Popover point anchors must stay inside the chart at \(width) points") }
        }
        let speech = BenchmarkCatalog.models(local: local).filter { $0.task == "speech" }
        let ranked = BenchmarkRanking.rank(speech, enabled: presentation.enabled, quality: .speech)
        let expectedProviders: Set<String> = state.localModels.catalog.isEmpty
            ? ["xAI", "AssemblyAI", "OpenRouter"]
            : ["xAI", "AssemblyAI", "Local", "OpenRouter"]
        guard Set(ranked.map { $0.model.provider }).isSuperset(of: expectedProviders) else {
            throw failure("Default benchmark must include cloud and local results")
        }
        let top = BenchmarkRanking.top(ranked)
        let anchors = top.compactMap { presentation.layout["anchor." + $0.id] }
        guard anchors.count == top.count, top.count == 5,
              anchors.allSatisfy({ $0.width <= 1.1 && $0.height <= 1.1 }),
              zip(anchors, anchors.dropFirst()).allSatisfy({ $0.midY < $1.midY }) else {
            throw failure("Each score popover must have its own point anchor on its model row")
        }
        presentation.toggle(.speed).wrappedValue = true
        guard presentation.enabled == [.quality, .speed] else { throw failure("Benchmark switch did not change scoring inputs") }
        for row in BenchmarkRanking.rank(speech, enabled: presentation.enabled, quality: .speech) {
            let ticks = root.ticks(row)
            guard Set(ticks.map(\.category)).count <= 3,
                  ticks.count == Int((row.total / 3.3).rounded()),
                  ticks.allSatisfy({ $0.start >= 0 && $0.end > $0.start }),
                  zip(ticks, ticks.dropFirst()).allSatisfy({ $0.end <= $1.start }),
                  ticks.enumerated().allSatisfy({ abs($0.element.start - Double($0.offset) * 3.3) < 0.000001 }),
                  ticks.allSatisfy({ abs(($0.end - $0.start) - 2.6) < 0.000001 }) else {
                throw failure("Every benchmark stroke, including the top stroke, must be full height with a rounded stroke count")
            }
        }
        let roundingCases: [(Double, Int)] = [(0, 0), (1.64, 0), (1.66, 1), (3.3, 1), (4.94, 1), (4.96, 2), (100, 30)]
        let roundingModels = roundingCases.enumerated().map { index, fixture in
            BenchmarkModel(id: String(index), name: "Rounding fixture", provider: "Fixture", task: "text",
                           speed: BenchmarkMeasurement(fixture.0, source: "fixture", note: ""))
        }
        for row in BenchmarkRanking.rank(roundingModels, enabled: [.speed], quality: .intelligence) {
            let fixture = roundingCases[Int(row.id)!]
            let ticks = root.ticks(row)
            guard ticks.count == fixture.1,
                  ticks.allSatisfy({ abs(($0.end - $0.start) - 2.6) < 0.000001 }),
                  abs(row.total - fixture.0) < 0.000001 else {
                throw failure("Bar rounding must cross half-bar boundaries without changing the exact score")
            }
        }
        for category in BenchmarkCategory.allCases { presentation.toggle(category).wrappedValue = false }
        host.layoutSubtreeIfNeeded()
        guard BenchmarkRanking.rank(speech, enabled: presentation.enabled, quality: .speech).isEmpty,
              !fixture.isVisible else { throw failure("Disabled scores remained ranked or benchmark fixture became visible") }
        print("Benchmark verified: cloud/local coverage, scoring switches, whole horizontal strokes, individual row popovers, category sections and hidden 420/600/950-point layout.")
    }

    private static func verifyButtonTitles(_ view: NSView) throws {
        if let button = view as? SettingsActionButton, !button.prominentTitle {
            for title in [button.attributedTitle, button.attributedAlternateTitle] where title.length > 0 {
                var overridesColor = false
                title.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                    if value != nil { overridesColor = true }
                }
                guard !overridesColor else { throw failure("Secondary button overrides native label contrast: " + button.title) }
            }
        }
        if let button = view as? NSButton, !(button is NSPopUpButton), !button.title.isEmpty,
           button.contentTintColor == .white {
            let enabled = button.isEnabled
            let state = button.state
            defer { button.isEnabled = enabled; button.state = state; button.highlight(false) }
            button.isEnabled = true
            for selected in [NSControl.StateValue.off, .on] {
                button.state = selected
                for pressed in [false, true] {
                    button.highlight(pressed)
                    for title in [button.attributedTitle, button.attributedAlternateTitle] {
                        guard title.length > 0 else { throw failure("Missing normal or pressed button title: " + button.title) }
                        var white = true
                        title.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                            guard let color = (value as? NSColor)?.usingColorSpace(.deviceRGB) else { white = false; return }
                            if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.99 { white = false }
                        }
                        guard white else { throw failure("Button title glyphs are not white: " + button.title) }
                    }
                }
            }
        }
        for child in view.subviews { try verifyButtonTitles(child) }
    }

    private static func benchmark(_ controller: AppearanceWindowController, window: NSWindow) throws {
        let pane = controller.modelsPane
        func measure(_ name: String, action: (Int) -> Void) {
            var samples: [Double] = []
            for index in 0..<80 {
                let start = CFAbsoluteTimeGetCurrent()
                action(index)
                window.contentView?.layoutSubtreeIfNeeded()
                samples.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
            }
            let sorted = samples.sorted()
            print(String(format: "BENCH %@: 80 switches, total %.1f ms, median %.2f ms, p95 %.2f ms, max %.2f ms", name,
                samples.reduce(0, +), sorted[40], sorted[75], sorted.last!))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        measure("model tabs") { pane.navigation.select($0.isMultiple(of: 2) ? .speech : .cleanup) }
        measure("settings pages") { index in
            if index.isMultiple(of: 2) { controller.showAPIKeys() } else { controller.showModels() }
        }
        guard !window.isVisible else { throw failure("Switching benchmark showed a window") }
    }

    private static func failure(_ text: String) -> NSError { NSError(domain: "ModelsWindowProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
