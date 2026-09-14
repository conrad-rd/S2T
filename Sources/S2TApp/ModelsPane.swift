import AppKit
import Combine
import S2TCore

@MainActor final class ModelsPane: NSViewController {
    let state: AppState
    private(set) var catalog: [CodexModel] = []
    private(set) var controls: [String: NSControl] = [:]
    private var actions: [String: (NSControl) -> Void] = [:]
    private var stack = SettingsDocumentStack()
    private var group: SettingsGroup?
    private var disclosureStack: NSStackView?
    private var expanded = Set<String>()
    private var catalogMessage = "Loading Codex model choices…"
    private var message = ""
    private var phaseSubscription: AnyCancellable?
    private var loading = false
    private var generation = 0
    private var validationTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        phaseSubscription = state.$phase.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.rebuild() }
        }
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let scroll = SettingsGlassScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = true
        view = scroll
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        rebuild()
    }

    func loadCatalog() {
        guard !loading, !state.isPreview else { return }
        loading = true
        Task { [weak self] in
            let result = await Task.detached { Result { try CodexModelCatalog.read() } }.value
            guard let self else { return }
            self.loading = false
            switch result {
            case .success(let models): self.setCatalog(models)
            case .failure:
                self.catalogMessage = "No local Codex catalog yet. Open Codex once, then reload. You can also save a model ID below."
                self.rebuild()
            }
        }
    }

    func setCatalog(_ models: [CodexModel]) {
        catalog = models
        catalogMessage = "Choices come from Codex's local catalog. Account access is checked by Codex when used."
        rebuild()
    }

    func rebuild() {
        guard isViewLoaded else { return }
        generation += 1
        validationTask?.cancel()
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        controls = [:]; actions = [:]
        group = nil; disclosureStack = nil
        add(SettingsFormStyle.pageHeading("Models"))
        if !message.isEmpty {
            let feedback = SettingsGroup()
            feedback.add(NSTextField(wrappingLabelWithString: message))
            add(feedback)
        }
        section("Speech to text")
        popup("speech.provider", title: "Provider", choices: TranscriptionProvider.allCases.map { ($0.rawValue, $0.title) }, selected: state.transcriptionProvider.rawValue) { [weak self] value in
            self?.state.transcriptionProvider = TranscriptionProvider(rawValue: value) ?? .assemblyAI; self?.rebuild()
        }
        let speech = state.transcriptionProvider
        if speech == .assemblyAI {
            popup("speech.mode", title: "Recognition", choices: TranscriptionMode.allCases.map { ($0.rawValue, $0.title) }, selected: state.transcriptionMode.rawValue) { [weak self] value in
                if let mode = TranscriptionMode(rawValue: value) { self?.state.transcriptionMode = mode }
            }
            note("Fast dictation uses Universal 3.5 Pro for supported clips. Extended recognition uses the batch service.")
        } else {
            editor("speech.model", title: "Model ID", value: state.transcriptionModel) { [weak self] value in
                guard let self, self.state.transcriptionProvider == speech else { return "Provider changed. Try again." }
                guard speech.validModelID(value) else { return "Enter a valid speech model ID." }
                if speech == .local { self.state.localTranscriptionModel = value }
                else if speech == .elevenLabs { self.state.elevenLabsModel = value }
                else { self.state.routerTranscriptionModel = value }
                return nil
            }
        }
        if speech == .local { endpoint("speech.url", value: state.localTranscriptionURL) { [weak self] in self?.state.localTranscriptionURL = $0 } }
        section("Text cleanup")
        popup("cleanup.provider", title: "Provider", choices: ProcessingProvider.allCases.map { ($0.rawValue, $0.title) }, selected: state.processingProvider?.rawValue ?? "") { [weak self] value in
            self?.state.processingProvider = ProcessingProvider(rawValue: value); self?.rebuild()
        }
        if let provider = state.processingProvider {
            if provider == .codex { codexSettings(vision: false) }
            else {
                editor("cleanup.model", title: "Model ID", value: state.processingModel) { [weak self] value in self?.state.saveProcessingModel(value, for: provider) }
                if provider == .openRouter {
                    disclosure("Hosting options", id: "cleanup.hosting") {
                        editor("cleanup.host", title: "Hosting endpoint", value: state.routerEndpoint) { [weak self] value in self?.state.routerEndpoint = value; return nil }
                        button("cleanup.preset", title: "Use Cerebras · GPT-OSS 120B") { [weak self] in self?.state.useCerebrasThroughOpenRouter(); self?.rebuild() }
                        note("Leave the endpoint empty for automatic hosting. Choosing a host disables fallback.")
                    }
                }
                if provider == .local { endpoint("cleanup.url", value: state.localProcessingURL) { [weak self] in self?.state.localProcessingURL = $0 } }
            }
        }
        section("Prompt vision")
        note("Used for image descriptions when Prompt mode is enabled.")
        popup("vision.provider", title: "Provider", choices: VisionProvider.allCases.map { ($0.rawValue, $0.title) }, selected: state.promptVisionProvider.rawValue) { [weak self] value in
            self?.state.promptVisionProvider = VisionProvider(rawValue: value) ?? .openRouter; self?.rebuild()
        }
        if state.promptVisionProvider == .codex { codexSettings(vision: true) }
        else {
            visionEditor()
            if state.promptVisionProvider == .local { endpoint("vision.url", value: state.localVisionURL) { [weak self] in self?.state.localVisionURL = $0 } }
        }
        if state.processingProvider == .codex || state.promptVisionProvider == .codex {
            section("Codex CLI")
            editor("codex.executable", title: "Executable path", value: state.codexExecutable) { [weak self] value in
                guard value.isEmpty || CodexCLI.executableURL(value) != nil else { return "No executable Codex binary was found at this path." }
                self?.state.codexExecutable = value; return nil
            }
            note("Leave the path empty to detect Codex. Uses your Codex login. S2T sets model options independently of Codex's config file.")
            note(catalogMessage)
            button("codex.reload", title: "Reload model choices") { [weak self] in self?.loadCatalog() }
        }
        section("Editing instructions")
        button("model.prompt.finder", title: "Reveal system prompt in Finder") { [weak self] in self?.state.openSystemPromptInFinder() }
        button("model.dictionary.finder", title: "Reveal dictionary in Finder") { [weak self] in self?.state.revealDictionaryInFinder() }
        if state.phase.busy || state.phase == .recording {
            for control in controls.values { control.isEnabled = false }
            note("Finish or cancel dictation to change models.")
        }
    }

    private func codexSettings(vision: Bool) {
        let prefix = vision ? "vision" : "cleanup"
        let model = vision ? state.promptVisionModel : state.processingModel
        let options = state.codexOptions(model: model, vision: vision)
        let available = catalog.filter { ($0.visibility == "list" || $0.slug == model) && (!vision || $0.input_modalities?.contains("image") == true) }
        var choices = [("default", "Codex default")] + available.map { ($0.slug, $0.display_name) }
        if !choices.contains(where: { $0.0 == model }) { choices.append((model, model + " · Saved")) }
        popup(prefix + ".model", title: "Model", choices: choices, selected: model) { [weak self] value in
            guard let self else { return }
            if vision { self.state.promptVisionModel = value } else { self.state.processingModel = value }
            self.rebuild()
        }
        disclosure("Custom model", id: prefix + ".advanced") {
            editor(prefix + ".custom", title: "Custom model ID", value: model) { [weak self] value in
                guard let self, ProcessingProvider.codex.validModelID(value) else { return "Enter a valid Codex model ID." }
                if vision, let entry = self.catalog.first(where: { $0.slug == value }), entry.input_modalities?.contains("image") != true { return "This Codex model does not accept images." }
                if vision { self.state.promptVisionModel = value } else { self.state.processingModel = value }
                return nil
            }
        }
        if let entry = catalog.first(where: { $0.slug == model }) {
            let normalized = entry.normalized(options)
            if normalized != options { state.setCodexOptions(normalized, model: model, vision: vision) }
            popup(prefix + ".reasoning", title: "Reasoning", choices: [("", "Model default")] + entry.supported_reasoning_levels.filter { CodexOptions(reasoning: $0.effort).isValid }.map { ($0.effort, $0.effort.capitalized) }, selected: normalized.reasoning) { [weak self] value in
                guard let self else { return }
                var selected = self.state.codexOptions(model: model, vision: vision); selected.reasoning = value
                self.state.setCodexOptions(selected, model: model, vision: vision)
            }
            let fast = NSButton(checkboxWithTitle: "Fast mode", target: self, action: #selector(invoke(_:)))
            fast.state = normalized.fast ? .on : .off
            fast.isEnabled = entry.supportsFast
            register(fast, id: prefix + ".fast") { [weak self] control in
                guard let self, let button = control as? NSButton else { return }
                var selected = self.state.codexOptions(model: model, vision: vision); selected.fast = button.state == .on
                self.state.setCodexOptions(selected, model: model, vision: vision)
            }
            add(fast)
            note(entry.supportsFast ? "Fast mode uses more of your Codex allowance. Availability depends on your account." : "Fast mode is not advertised for this model.")
        } else {
            note(model == "default" ? "Choose a specific model to adjust its supported reasoning and fast mode." : "Reasoning and fast mode need this model's local Codex catalog entry. Reload after opening Codex.")
        }
    }

    private func visionEditor() {
        let provider = state.promptVisionProvider
        let field = NSTextField(string: state.promptVisionModel)
        field.placeholderString = "Image-capable model ID"
        field.setAccessibilityLabel("Vision model ID")
        controls["vision.model"] = field
        let save = SettingsGlassButton(title: "Save", target: self, action: #selector(invoke(_:)))
        save.primary = true
        register(save, id: "vision.model.save") { [weak self, weak field, weak save] _ in
            guard let self, let field, let save else { return }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let generation = self.generation
            let localURL = self.state.localVisionURL
            save.isEnabled = false; save.title = "Checking…"
            self.validationTask = Task { [weak self] in
                guard let self else { return }
                let error = await self.state.validatePromptVisionModel(value)
                guard !Task.isCancelled, self.generation == generation, self.state.promptVisionProvider == provider, self.state.localVisionURL == localURL, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == value else { save.isEnabled = true; save.title = "Save"; return }
                if let error { self.message = error } else { self.state.promptVisionModel = value; self.message = "Vision model saved." }
                self.rebuild()
            }
        }
        row("Model ID", SettingsFormStyle.field(field), save)
    }

    private func endpoint(_ id: String, value: String, save: @escaping (String) -> Void) {
        editor(id, title: "Endpoint URL", value: value) { value in
            do { _ = try LocalEndpoint.url(value); save(value); return nil }
            catch { return error.localizedDescription }
        }
    }
    private func editor(_ id: String, title: String, value: String, save: @escaping (String) -> String?) {
        let field = NSTextField(string: value)
        field.setAccessibilityLabel(title)
        field.identifier = NSUserInterfaceItemIdentifier(id)
        controls[id] = field
        let feedback = NSTextField(wrappingLabelWithString: "")
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .systemRed
        feedback.isHidden = true
        let button = SettingsGlassButton(title: "Save", target: self, action: #selector(invoke(_:)))
        button.primary = true
        register(button, id: id + ".save") { [weak self, weak field, weak feedback] _ in
            guard let self, let field else { return }
            let error = save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            self.message = error ?? "\(title) saved."
            if error == nil { self.rebuild() }
            else {
                field.toolTip = error
                field.setAccessibilityHelp(error)
                feedback?.stringValue = error ?? ""
                feedback?.isHidden = false
            }
        }
        row(title, SettingsFormStyle.field(field), button)
        add(feedback)
    }
    private func popup(_ id: String, title: String, choices: [(String, String)], selected: String, change: @escaping (String) -> Void) {
        let popup = NSPopUpButton()
        SettingsFormStyle.popup(popup)
        for (value, label) in choices {
            popup.addItem(withTitle: label)
            popup.lastItem?.representedObject = value
        }
        if let index = choices.firstIndex(where: { $0.0 == selected }) { popup.selectItem(at: index) }
        popup.setAccessibilityLabel(title)
        register(popup, id: id) { control in
            if let value = (control as? NSPopUpButton)?.selectedItem?.representedObject as? String { change(value) }
        }
        row(title, popup)
    }
    private func button(_ id: String, title: String, action: @escaping () -> Void) {
        let button = SettingsGlassButton(title: title, target: self, action: #selector(invoke(_:)))
        register(button, id: id) { _ in action() }; add(button)
    }
    private func register(_ control: NSControl, id: String, action: @escaping (NSControl) -> Void) {
        control.identifier = NSUserInterfaceItemIdentifier(id)
        control.target = self; control.action = #selector(invoke(_:))
        controls[id] = control; actions[id] = action
    }
    @objc private func invoke(_ sender: NSControl) { if let id = sender.identifier?.rawValue { actions[id]?(sender) } }
    private func section(_ title: String) {
        group = nil
        let symbols: [String: (String, NSColor)] = [
            "Speech to text": ("waveform", .systemBlue),
            "Text cleanup": ("text.badge.checkmark", .systemPurple),
            "Prompt vision": ("eye", .systemTeal),
            "Codex CLI": ("terminal", .systemGray),
            "Editing instructions": ("text.book.closed", .systemOrange)
        ]
        let style = symbols[title] ?? ("gearshape", .systemGray)
        let card = SettingsGroup()
        card.identifier = NSUserInterfaceItemIdentifier("models.group." + title)
        add(card)
        group = card
        add(SettingsHeading.make(title, symbol: style.0, color: style.1))
    }

    private func disclosure(_ title: String, id: String, build: () -> Void) {
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 12
        let toggle = NSButton(title: "", target: self, action: #selector(invoke(_:)))
        toggle.bezelStyle = .disclosure
        toggle.widthAnchor.constraint(equalToConstant: 26).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: 26).isActive = true
        toggle.setButtonType(.onOff)
        toggle.state = expanded.contains(id) ? .on : .off
        toggle.setAccessibilityLabel(title)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let header = NSStackView(views: [toggle, label, NSView()])
        header.spacing = 5
        header.alignment = .centerY
        register(toggle, id: id + ".disclosure") { [weak self, weak body] control in
            guard let self, let toggle = control as? NSButton else { return }
            if toggle.state == .on { self.expanded.insert(id) } else { self.expanded.remove(id) }
            body?.isHidden = toggle.state != .on
        }
        add(header)
        add(body)
        disclosureStack = body
        build()
        disclosureStack = nil
        body.isHidden = !expanded.contains(id)
    }

    private func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; add(label)
    }
    private func row(_ title: String, _ controls: NSView...) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 94).isActive = true
        let row = NSStackView(views: [label] + controls)
        row.distribution = .fill
        row.spacing = 8; row.alignment = .centerY
        controls.first?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add(row)
    }
    private func add(_ child: NSView) {
        if let disclosureStack {
            child.translatesAutoresizingMaskIntoConstraints = false
            disclosureStack.addArrangedSubview(child)
            child.widthAnchor.constraint(equalTo: disclosureStack.widthAnchor).isActive = true
            return
        }
        if let group { group.add(child); return }
        stack.addArrangedSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
    }
}

