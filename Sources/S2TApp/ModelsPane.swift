import AppKit
import Combine
import SwiftUI
import S2TCore

/// Speech and cleanup share the main page. Provider visibility, the local library and comparisons open as sub-pages.
@MainActor final class ModelsPane: NSViewController {
    let state: AppState
    private(set) var catalog: [CodexModel] = []
    private(set) var controls: [String: NSControl] = [:]
    private var actions: [String: (NSControl) -> Void] = [:]
    /// Model choices inside provider submenus, keyed by their popup's identifier.
    private var menuChoices: [String: (String) -> Void] = [:]
    private var groupedMenuActions: [ObjectIdentifier: () -> Void] = [:]
    private var groupedActionIDs: [String: [ObjectIdentifier]] = [:]
    private var modelMenuSources: [String: (items: [NSMenuItem], current: NSMenuItem?)] = [:]
    private var reasoningRows: [String: NSView] = [:]
    private var stack = SettingsDocumentStack()
    private var group: SettingsGroup?
    private var groupRows = 0
    private(set) var sectionAnchors: [ModelsSection: NSView] = [:]
    private var customEditors = Set<String>()
    private var modelDrafts: [String: String] = [:]
    private var modelEditors: [(key: String, field: NSTextField, row: NSView)] = []
    var openAPIKeys: ((String) -> Void)?
    private var configurationChanged = false
    private var showingProviderSettings = false
    private var subscriptions: [AnyCancellable] = []
    private var catalogRequested = false
    private let choicePreferences: UserDefaults
    let navigation = ModelsNavigation()
    let scroll = SettingsScrollView(frame: .zero)
    private(set) var comparison: NSHostingView<ModelsComparisonView>!
    private(set) lazy var localPane = LocalModelsPane(state: state)
    private var catalogMessage = ""
    private var message = ""
    private var hostsByModel: [String: [OpenRouterHost]] = [:]
    private var hostsLoadedAt: [String: Date] = [:]
    private var hostsLoading = Set<String>()
    private var hostErrors = Set<String>()
    private var loading = false
    private var generation = 0
    static let fastestHost = "~fastest"
    static let personalXAI = "~personal-xai"
    private static let pageInset: CGFloat = 44

    init(state: AppState) {
        self.state = state
        choicePreferences = state.isPreview ? UserDefaults(suiteName: "com.s2t.preview")! : .standard
        super.init(nibName: nil, bundle: nil)
        subscriptions = [
            state.objectWillChange.sink { [weak self] _ in self?.configurationChanged = true },
            state.$hiddenProviders.dropFirst().removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                if !self.state.isProviderVisible("local") && self.navigation.page == .local { self.navigation.showOverview() }
                self.rebuild()
            },
            NotificationCenter.default.publisher(for: OpenRouterReasoningCatalog.updated)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshReasoningControls() },
            state.$creditModels.dropFirst().removeDuplicates().sink { [weak self] _ in self?.refreshAfterEditing() },
            state.$routerSpeechModels.dropFirst().removeDuplicates().sink { [weak self] _ in self?.refreshAfterEditing() },
            state.$routerTextModels.dropFirst().removeDuplicates().sink { [weak self] _ in self?.refreshAfterEditing() },
            state.$keyStatuses.combineLatest(state.$savedKeyAccounts).dropFirst().sink { [weak self] _ in self?.refreshAfterEditing() },
            state.localModels.$installed.combineLatest(state.localModels.$catalog).dropFirst()
                .receive(on: RunLoop.main).sink { [weak self] _ in
                    guard let self, self.isViewLoaded else { return }
                    self.configureProviderModelMenus(prefixes: ["speech", "cleanup"].filter { !(self.controls[$0 + ".choice"] is LocalModelChoicePicker) })
                },
            state.$phase.dropFirst().removeDuplicates().sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.rebuild() }
            }
        ]
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        let background = NSHostingView(rootView: SettingsPageBackground())
        background.sizingOptions = []
        comparison = NSHostingView(rootView: ModelsComparisonView(state: state, navigation: navigation))
        comparison.sizingOptions = []
        for child in [background, scroll, localPane.view, comparison!] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.topAnchor.constraint(equalTo: view.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: Self.pageInset, bottom: 28, right: Self.pageInset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        navigation.onChange = { [weak self] section in
            guard let self else { return }
            if !self.state.isProviderVisible("local") && self.navigation.page == .local {
                self.navigation.showOverview()
                return
            }
            if let editor = self.view.window?.firstResponder as? NSTextView, editor.isFieldEditor {
                self.view.window?.makeFirstResponder(nil)
            }
            if !self.message.isEmpty { self.configurationChanged = true }
            self.message = ""
            self.refreshForPresentation()
            self.updateVisibility()
            switch self.navigation.page {
            case .settings:
                self.localPane.showOverview()
                self.reveal(self.navigation.takeScrollTarget())
            case .local:
                self.localPane.refresh()
            case .compare:
                break
            case .providers:
                self.reveal(nil)
            }
        }
        rebuild()
    }

    func refreshForPresentation() {
        if configurationChanged || showingProviderSettings != (navigation.page == .providers) { rebuild() }
        if !catalogRequested { loadCatalog() }
    }

    /// Loads catalogs once for the first presentation; the toolbar's refresh forces every source again.
    func loadCatalog(force: Bool = false) {
        catalogRequested = true
        guard !loading, !state.isPreview else { return }
        loading = true
        Task { [state] in await state.refreshCredits(force: force) }
        Task { [state] in await state.refreshTextCatalog(force: force) }
        if force {
            for model in [cleanupModel] where ProcessingProvider.openRouter.validModelID(model) { loadHosts(model: model, force: true) }
        }
        Task { [weak self] in
            let result = await Task.detached { Result { try CodexModelCatalog.read() } }.value
            guard let self else { return }
            self.loading = false
            switch result {
            case .success(let models): self.setCatalog(models)
            case .failure:
                self.catalogMessage = "Codex model choices appear after you open Codex once. Refresh to check again."
                self.rebuild()
            }
        }
    }

    func setCatalog(_ models: [CodexModel]) {
        catalog = models
        catalogMessage = ""
        rebuild()
    }

    func rebuild() {
        guard isViewLoaded else { return }
        defer { configurationChanged = false; updateVisibility() }
        for editor in modelEditors where !editor.row.isHidden {
            modelDrafts[editor.key] = editor.field.currentEditor()?.string ?? editor.field.stringValue
        }
        modelEditors = []
        generation += 1
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
        controls = [:]; actions = [:]; menuChoices = [:]; sectionAnchors = [:]; reasoningRows = [:]
        groupedMenuActions = [:]
        groupedActionIDs = [:]; modelMenuSources = [:]
        group = nil; groupRows = 0
        showingProviderSettings = navigation.page == .providers
        if showingProviderSettings {
            visibilitySection()
            return
        }
        let busy = state.phase.busy || state.phase == .recording
        if busy || !message.isEmpty {
            let feedback = SettingsGroup(grouped: true)
            feedback.identifier = .init("models.feedback")
            let label = NSTextField(wrappingLabelWithString: busy ? "Finish or cancel dictation to change models." : message)
            label.textColor = busy ? .secondaryLabelColor : .systemRed
            feedback.add(label)
            add(feedback)
        }
        speechSection()
        cleanupSection()
        codexSection()
        pagesSection()
        configureProviderModelMenus()
        if busy { for control in controls.values where control.identifier?.rawValue.hasPrefix("models.") != true { control.isEnabled = false } }
    }

    // MARK: Sections

    private func visibilitySection() {
        heading("Show providers", section: nil)
        beginGroup("visibility")
        for provider in AppState.optionalProviders {
            let toggle = NSSwitch()
            toggle.state = state.isProviderVisible(provider.id) ? .on : .off
            toggle.setAccessibilityLabel("Show " + provider.title)
            register(toggle, id: "models.providerVisibility." + provider.id) { [weak self] control in
                self?.state.setProviderVisible(provider.id, (control as? NSSwitch)?.state == .on)
            }
            row(provider.title, toggle)
        }
        note("Turn off a provider to hide it throughout S2T. Saved keys and active connections stay unchanged.")
    }

    private func speechSection() {
        heading("Speech to text", section: .speech)
        beginGroup("speech")
        providerPopup("speech.provider", category: "speech",
                      choices: TranscriptionProvider.allCases.filter { $0 != .local }.map { ($0.rawValue, $0.title) },
                      selected: { [state] in state.transcriptionProvider.rawValue }) { [weak self] value in
            self?.state.transcriptionProvider = TranscriptionProvider(rawValue: value) ?? .assemblyAI
        }
        let speech = state.transcriptionProvider
        guard state.isModelProviderVisible(for: "speech") else {
            note("Your current provider is hidden. Choose a visible provider above to change it.")
            return
        }
        if state.speechUsesCredits {
            let catalog = state.creditModels.filter { $0.operation == "transcription" }
            let recommended = (ModelRecommendations.creditSpeech + ModelRecommendations.openRouterSpeech).filter { choice in
                catalog.contains { $0.model == choice.model } || (state.creditOpenRouterCatalog && choice.model.contains("/"))
            }
            modelChoices("speech", recommended: recommended, more: catalog.map { ModelSuggestion(model: $0.model, title: $0.title) },
                         model: state.creditTranscriptionModel) { [weak self] value, _ in
                guard let self else { return nil }
                if let choice = self.state.creditModels.first(where: { $0.operation == "transcription" && $0.model == value }),
                   let provider = TranscriptionProvider(rawValue: choice.provider) {
                    self.state.creditSpeechProvider = provider
                } else if self.state.creditOpenRouterCatalog && TranscriptionProvider.openRouter.validModelID(value) {
                    self.state.creditSpeechProvider = .openRouter
                } else { return "This model is not available with S2T credits. Refresh the model list." }
                self.state.creditTranscriptionModel = value
                return nil
            }
        } else if speech == .assemblyAI {
            popup("speech.mode", title: "Model", choices: TranscriptionMode.allCases.map { ($0.rawValue, $0 == .fast ? "Universal 3.5 Pro" : "Universal · Extended languages") },
                  selected: state.transcriptionMode.rawValue) { [weak self] value in
                if let mode = TranscriptionMode(rawValue: value) { self?.state.transcriptionMode = mode }
            }
            controls["speech.mode"]?.toolTip = "Universal 3.5 Pro uses fast transcription for supported clips. Extended languages use the batch service."
        } else if speech == .local {
            localModelSettings(category: "speech", prefix: "speech")
        } else {
            let recommended = speech == .xai ? ModelRecommendations.xaiSpeech : ModelRecommendations.openRouterSpeech
            let more = speech == .xai
                ? TranscriptionProvider.xaiModels.map { ModelSuggestion(model: $0, title: $0 == "grok-voice-transcribe-2.0" ? "Grok Voice 2.0" : "Grok Voice 1.0") }
                : state.routerSpeechModels.map { ModelSuggestion(model: $0.id, title: $0.name) }
            modelChoices("speech", recommended: recommended, more: more, model: state.transcriptionModel) { [weak self] value, _ in
                guard let self, !self.state.speechUsesCredits, self.state.transcriptionProvider == speech else { return "Provider changed. Try again." }
                guard speech.validModelID(value) else { return "Enter a valid speech model ID." }
                if speech == .xai { self.state.xaiTranscriptionModel = value } else { self.state.routerTranscriptionModel = value }
                return nil
            }
        }
        if state.speechUsesCredits ? state.creditSpeechProvider == .openRouter : speech == .openRouter {
            let hosting = NSTextField(labelWithString: "Automatic")
            hosting.textColor = .secondaryLabelColor
            hosting.toolTip = "OpenRouter does not support choosing a speech host."
            row("Host", hosting)
        }
        accountRow(category: "speech", prefix: "speech")
    }

    private func cleanupSection() {
        heading("Text cleanup", section: .cleanup)
        beginGroup("cleanup")
        providerPopup("cleanup.provider", category: "text",
                      choices: ProcessingProvider.allCases.filter { $0 != .local }.map { ($0.rawValue, $0.title) },
                      selected: { [state] in state.processingProvider?.rawValue ?? "" }) { [weak self] value in
            self?.state.processingProvider = ProcessingProvider(rawValue: value)
        }
        guard state.isModelProviderVisible(for: "text") else {
            note("Your current provider is hidden. Choose a visible provider above to change it.")
            jevSettings()
            return
        }
        if state.cleanupUsesCredits { openRouterCleanupSettings(credits: true) }
        else if let provider = state.processingProvider {
            switch provider {
            case .openRouter: openRouterCleanupSettings(credits: false)
            case .codex: codexSettings()
            case .local: localModelSettings(category: "text", prefix: "cleanup")
            case .xai:
                modelChoices("cleanup", recommended: [ModelSuggestion(model: provider.defaultModel, title: "Grok 4.6", detail: "xAI default")], more: [],
                             model: state.processingModel) { [weak self] value, _ in self?.state.saveProcessingModel(value, for: provider) }
            }
        }
        accountRow(category: "text", prefix: "cleanup")
        jevSettings()
    }


    private func codexSettings() {
        let prefix = "cleanup"
        let model = state.processingModel
        let options = state.codexOptions(model: model)
        let available = catalog.filter { $0.visibility == "list" || $0.slug == model }
        let choices = [ModelSuggestion(model: "default", title: "Codex default", detail: "The model Codex uses by default")]
            + available.map { ModelSuggestion(model: $0.slug, title: $0.display_name) }
        modelChoices(prefix, recommended: choices, more: [], model: model) { [weak self] value, _ in
            guard let self, ProcessingProvider.codex.validModelID(value) else { return "Enter a valid Codex model ID." }
            self.state.processingModel = value
            return nil
        }
        let entry = available.first { $0.slug == model }
        let efforts = [""] + (entry?.supported_reasoning_levels.map(\.effort) ?? [])
        if efforts.count > 1 {
            popup(prefix + ".reasoning", title: "Reasoning",
                  choices: efforts.map { ($0, $0.isEmpty ? "Model default" : $0.capitalized) },
                  selected: options.reasoning) { [weak self] value in
                guard let self else { return }
                var selected = self.state.codexOptions(model: model); selected.reasoning = value
                self.state.setCodexOptions(selected, model: model)
            }
        }
        guard entry?.supportsFast == true else { return }
        let control = NSSwitch()
        control.state = options.fast ? .on : .off
        control.setAccessibilityLabel("Fast mode")
        control.toolTip = "Codex checks fast mode against your account and selected model when you use it."
        register(control, id: prefix + ".fast") { [weak self] item in
            guard let self else { return }
            var selected = self.state.codexOptions(model: model)
            selected.fast = (item as? NSSwitch)?.state == .on
            self.state.setCodexOptions(selected, model: model)
        }
        row("Fast mode", control)
    }

    /// The executable applies to every Codex cleanup model.
    private func codexSection() {
        guard !state.cleanupUsesCredits && state.processingProvider == .codex else { return }
        heading("Codex", section: nil)
        beginGroup("codex")
        editor("codex.executable", title: "Executable", value: state.codexExecutable, placeholder: "Find automatically") { [weak self] value in
            guard value.isEmpty || CodexCLI.executableURL(value) != nil else { return "No executable Codex binary was found at this path." }
            self?.state.codexExecutable = value; return nil
        }
        controls["codex.executable"]?.toolTip = "Leave empty to find Codex automatically. Uses your Codex login."
        if !catalogMessage.isEmpty { note(catalogMessage) }
    }

    private func pagesSection() {
        heading("", section: nil)
        beginGroup("pages")
        let providers = SettingsLinkRow(title: "Providers", symbol: "switch.2")
        register(providers, id: "models.providers") { [weak self] _ in self?.navigation.showProviders() }
        add(providers)
        groupRows += 1
        separator()
        if state.isProviderVisible("local") {
            let local = SettingsLinkRow(title: "Local models", symbol: "desktopcomputer")
            local.observe(state.localModels)
            register(local, id: "models.local") { [weak self] _ in self?.navigation.select(.local) }
            add(local)
            groupRows += 1
            separator()
        }
        let compare = SettingsLinkRow(title: "Compare models", symbol: "chart.bar")
        register(compare, id: "models.compare") { [weak self] _ in self?.navigation.showComparison() }
        add(compare)
    }

    // MARK: Cleanup

    private var cleanupModel: String { state.cleanupUsesCredits ? state.creditCleanupModel : state.processingModel }

    private func openRouterCleanupSettings(credits: Bool) {
        let model = cleanupModel
        let catalog = state.creditModels.filter { $0.operation == "cleanup" }
        let recommended = ModelRecommendations.cleanup.filter { choice in
            !credits || state.creditOpenRouterCatalog || catalog.contains { $0.model == choice.model }
        }
        var more = credits ? catalog.map { ModelSuggestion(model: $0.model, title: $0.title, host: $0.host) } : CreditModel.suggestions.map { ModelSuggestion(model: $0.model, title: $0.title, host: $0.host) }
        if !credits || state.creditOpenRouterCatalog { more += state.routerTextModels.map { ModelSuggestion(model: $0.id, title: $0.name) } }
        modelChoices("cleanup", recommended: recommended, more: more, model: model) { [weak self] value, host in
            guard let self else { return nil }
            if let error = self.selectCleanupModel(value) { return error }
            if !credits, let host { self.state.routerEndpoint = host }
            if ModelRecommendations.cleanup.contains(where: { $0.model == value }) { self.applyRecommendedReasoning(model: value, credits: credits) }
            return nil
        }
        if !credits || state.creditCleanupProvider == .openRouter {
            hostPopup()
            routerReasoning()
        }
        contributorConsent(model: model)
    }

    /// Recommended cleanup models start at low reasoning for speed, unless this model already has a saved level.
    private func applyRecommendedReasoning(model: String, credits: Bool) {
        if credits {
            guard !state.hasSavedCreditCleanupOptions(for: model) else { return }
            var options = state.creditCleanupOptions
            options.reasoning = OpenRouterReasoningCatalog.shared.efforts(for: model).contains(ModelRecommendations.cleanupReasoning) ? ModelRecommendations.cleanupReasoning : .automatic
            state.creditCleanupOptions = options
        } else if state.routerModelOptions["cleanup:" + model] == nil {
            var options = state.routerOptions(model: model)
            options.reasoning = OpenRouterReasoningCatalog.shared.efforts(for: model).contains(ModelRecommendations.cleanupReasoning) ? ModelRecommendations.cleanupReasoning : .automatic
            state.setRouterOptions(options, model: model)
        }
    }

    private func selectCleanupModel(_ value: String) -> String? {
        guard !state.phase.busy, state.phase != .recording else { return "Finish dictation before changing models." }
        if state.cleanupUsesCredits {
            let choices = state.creditModels.filter { $0.operation == "cleanup" && $0.model == value }
            if choices.isEmpty {
                guard state.creditOpenRouterCatalog, ProcessingProvider.openRouter.validModelID(value) else {
                    return "Refresh the model list to update the S2T catalog, then choose the model."
                }
                state.creditCleanupProvider = .openRouter
                state.creditCleanupModel = value
                state.creditCleanupHost = ModelRecommendations.cleanup.first { $0.model == value }?.host ?? ""
                return nil
            }
            guard let provider = choices.first.flatMap({ ProcessingProvider(rawValue: $0.provider) }) else { return "This provider is not available with S2T credits." }
            state.creditCleanupProvider = provider
            if state.creditCleanupModel != value {
                let preferred = value == CreditModel.defaults[0].model
                    ? choices.first(where: { $0.host == CreditModel.defaults[0].host }) : nil
                state.creditCleanupHost = preferred?.host
                    ?? (choices.contains(where: { $0.host == state.creditCleanupHost }) ? state.creditCleanupHost
                        : choices.contains(where: { $0.host.isEmpty }) ? "" : choices[0].host)
            }
            state.creditCleanupModel = value
            return nil
        }
        return state.saveProcessingModel(value, for: .openRouter)
    }

    private func jevSettings() {
        beginGroup("cleanup.extra")
        popup("cleanup.jev.mode", title: "Extra cleanup (beta)", choices: JevCleanupMode.allCases.map { ($0.rawValue, $0.title) }, selected: state.jevCleanupMode.rawValue) { [weak self] value in
            self?.state.jevCleanupMode = JevCleanupMode(rawValue: value) ?? .off
            self?.rebuild()
        }
        controls["cleanup.jev.mode"]?.toolTip = "Experimental Jev check for dictionary matches and hesitation sounds. Finish simple transcripts can skip the normal model with the default Clean up instructions and clipboard context off."
        guard state.jevCleanupMode != .off else { return }
        let routes = JevRoute.allCases.filter { state.isProviderVisible($0 == .s2t ? "s2t" : $0.account.rawValue) }
        let connection = popup("cleanup.jev.route", title: "Connection", choices: routes.map { ($0.rawValue, $0.title) }, selected: state.jevRoute.rawValue) { [weak self] value in
            self?.state.jevRoute = JevRoute(rawValue: value) ?? .typeSafe
            self?.rebuild()
        }
        if !routes.contains(state.jevRoute) {
            connection.insertItem(withTitle: "Current connection hidden", at: 0)
            connection.item(at: 0)?.isEnabled = false
            connection.selectItem(at: 0)
            return
        }
        controls["cleanup.jev.route"]?.toolTip = "Receives your transcript, instructions and dictionary spellings. Uses the selected connection's key and billing."
        let jevKey = state.jevRoute == .s2t ? (state.creditConnection?.key ?? "") : state.jevRoute.account == .typeSafe ? state.typeSafeKey : state.routerKey
        if jevKey.isEmpty { note("Add your \(state.jevRoute == .s2t ? "S2T" : state.jevRoute.account.title) key in API keys. Until then, normal cleanup is used.") }
        if !state.jevSummary.isEmpty { note(state.jevSummary) }
    }

    // MARK: Hosting and reasoning

    func setHosts(_ hosts: [OpenRouterHost], model: String) {
        if hostsByModel.count >= 64 { hostsByModel.removeAll(); hostsLoadedAt.removeAll() }
        hostsByModel[model] = hosts
        hostsLoadedAt[model] = Date()
        hostErrors.remove(model)
        hostsLoading.remove(model)
        refreshHostMenus()
    }

    private func loadHosts(model: String, force: Bool = false) {
        guard !state.isPreview, !hostsLoading.contains(model),
              force || Date().timeIntervalSince(hostsLoadedAt[model] ?? .distantPast) > 300 else { return }
        hostsLoading.insert(model)
        Task { [weak self] in
            do { self?.setHosts(try await OpenRouterHost.load(model: model), model: model) }
            catch {
                self?.hostsLoading.remove(model)
                self?.hostErrors.insert(model)
                self?.hostsLoadedAt[model] = Date()
                self?.refreshHostMenus()
            }
        }
    }

    private func hostState() -> (model: String, host: String, fast: Bool, credits: Bool) {
        let credits = state.cleanupUsesCredits
        let model = cleanupModel
        let host = credits ? state.creditCleanupHost : state.routerEndpoint
        let options = credits ? state.creditCleanupOptions : state.routerOptions(model: model)
        return (model, host, options.fast, credits)
    }

    /// Automatic lets OpenRouter pick; Fastest available sorts automatic routing by throughput; any other entry pins one host.
    private func hostChoices() -> [(String, String)] {
        let current = hostState()
        let hosts = hostsByModel[current.model] ?? []
        let operation = "cleanup"
        let configured = state.creditModels.filter { $0.operation == operation && $0.provider == "openrouter" && $0.model == current.model }
        let restricted = current.credits && !state.creditOpenRouterCatalog
        let available = hosts.filter { host in !restricted || configured.contains { $0.host == host.tag } }
        var choices: [(String, String)] = []
        if !restricted || configured.contains(where: { $0.host.isEmpty }) || configured.isEmpty {
            choices = [("", "Automatic"), (Self.fastestHost, "Fastest available")]
        }
        let titles = available.map { $0.provider_name + ($0.quantization.map { " · " + $0 } ?? "") }
        // Hosts can share a provider name and quantization (two Amazon Bedrock regions, two DeepInfra bf16 routes).
        choices += zip(available, titles).map { host, title in
            (host.tag, titles.filter { $0 == title }.count > 1 ? title + " · " + host.tag : title)
        }
        if restricted {
            for entry in configured where !entry.host.isEmpty && !choices.contains(where: { $0.0 == entry.host }) {
                choices.append((entry.host, entry.host == "cerebras/fp16" ? "Cerebras" : entry.host))
            }
        }
        let selected = selectedHostValue()
        if !choices.contains(where: { $0.0 == selected }) {
            choices.append((selected, selected == Self.fastestHost ? "Fastest available" : selected.isEmpty ? "Automatic" : selected == "cerebras/fp16" ? "Cerebras" : selected))
        }
        return choices
    }

    private func selectedHostValue() -> String {
        let current = hostState()
        return current.host.isEmpty ? (current.fast ? Self.fastestHost : "") : current.host
    }

    private func hostPopup() {
        let prefix = "cleanup"
        let model = hostState().model
        loadHosts(model: model)
        popup(prefix + ".host", title: "Host", choices: hostChoices(), selected: selectedHostValue()) { [weak self] value in
            guard let self, !self.state.phase.busy, self.state.phase != .recording else { return }
            self.saveHost(value)
            self.rebuild()
        }
        refreshHostMenus()
    }

    private func saveHost(_ value: String) {
        let current = hostState()
        let host = value == Self.fastestHost ? "" : value
        if value.isEmpty || value == Self.fastestHost {
            var options = current.credits ? state.creditCleanupOptions : state.routerOptions(model: current.model)
            options.fast = value == Self.fastestHost
            if current.credits {
                state.creditCleanupOptions = options
            } else { state.setRouterOptions(options, model: current.model) }
        }
        if current.credits { state.creditCleanupHost = host } else { state.routerEndpoint = host }
    }

    private func refreshHostMenus() {
        guard let control = controls["cleanup.host"] as? NSPopUpButton else { return }
        let current = hostState()
        control.removeAllItems()
        for (value, title) in hostChoices() { control.appendItem(title, value: value) }
        control.selectItem(value: selectedHostValue())
        for item in control.itemArray {
            guard let tag = item.representedObject as? String else { continue }
            if tag == Self.fastestHost { item.toolTip = "Lets OpenRouter choose the host with the highest recent throughput. This may cost more." }
            else if tag.isEmpty { item.toolTip = "Lets OpenRouter choose an available host." }
            else if let host = hostsByModel[current.model]?.first(where: { $0.tag == tag }) { item.toolTip = host.menuTitle(cheapest: nil) }
        }
        control.toolTip = hostErrors.contains(current.model) ? "Hosts could not be loaded. Refresh to try again."
            : hostsLoading.contains(current.model) ? "Loading hosts…"
            : "Prices are USD per million tokens." + (state.isProviderVisible("s2t") ? " S2T credits add their normal margin." : "")
    }

    private func routerReasoning() {
        let prefix = "cleanup"
        let model = cleanupModel
        let credits = state.cleanupUsesCredits
        if !state.isPreview { Task { await OpenRouterReasoningCatalog.shared.refresh(model: model) } }
        let options = credits ? state.creditCleanupOptions : state.routerOptions(model: model)
        let control = popup(prefix + ".reasoning", title: "Reasoning", choices: OpenRouterReasoningCatalog.shared.efforts(for: model).map { ($0.rawValue, $0.title) }, selected: options.reasoning.rawValue) { [weak self] value in
            guard let self, let effort = OpenRouterOptions.Effort(rawValue: value) else { return }
            let model = self.cleanupModel
            var options = credits ? self.state.creditCleanupOptions : self.state.routerOptions(model: model)
            options.reasoning = effort
            if credits {
                self.state.creditCleanupOptions = options
            } else { self.state.setRouterOptions(options, model: model) }
        }
        reasoningRows[prefix] = control.superview
        updateReasoningControl()
    }

    private func refreshReasoningControls() {
        updateReasoningControl()
    }

    private func updateReasoningControl() {
        guard let popup = controls["cleanup.reasoning"] as? NSPopUpButton else { return }
        let credits = state.cleanupUsesCredits
        let codex = !credits && (state.processingProvider == .codex)
        guard !codex else { return }
        let model = cleanupModel
        let choices = OpenRouterReasoningCatalog.shared.efforts(for: model)
        let options = credits ? state.creditCleanupOptions : state.routerOptions(model: model)
        popup.removeAllItems()
        for effort in choices { popup.appendItem(effort.title, value: effort.rawValue) }
        popup.selectItem(at: choices.firstIndex(of: options.reasoning) ?? 0)
        popup.toolTip = "Reasoning levels advertised by this model. Lower levels usually answer faster."
        popup.isEnabled = choices.count > 1 && !state.phase.busy && state.phase != .recording
        if let row = reasoningRows["cleanup"] {
            row.isHidden = choices.count <= 1
            separatorBefore(row)?.isHidden = row.isHidden
        }
    }

    private func contributorConsent(model: String) {
        guard model == OpenRouterOptions.contributorModel else { return }
        let credits = state.cleanupUsesCredits
        let options = credits ? state.creditCleanupOptions : state.routerOptions(model: model)
        let checkbox = NSButton(checkboxWithTitle: "Allow Meta to use prompts and responses", target: nil, action: nil)
        checkbox.state = options.allowDataCollection ? .on : .off
        checkbox.setAccessibilityLabel("Allow Meta to use prompts and responses to improve its products")
        register(checkbox, id: "cleanup.contributorConsent") { [weak self] control in
            guard let self, let checkbox = control as? NSButton else { return }
            var options = credits ? self.state.creditCleanupOptions : self.state.routerOptions(model: model)
            options.allowDataCollection = checkbox.state == .on
            if credits {
                self.state.creditCleanupOptions = options
            } else { self.state.setRouterOptions(options, model: model) }
        }
        if groupRows > 0 { separator() }
        add(checkbox)
        groupRows += 1
        note("Contributor is cheaper because Meta may use this content to improve its products. This permission applies only to this model.")
    }

    // MARK: Local models

    /// Installed models for this task, plus a custom endpoint for a server such as LM Studio or Ollama.
    private func localModelSettings(category: String, prefix: String) {
        let picker = LocalModelChoicePicker(state: state, category: category)
        picker.choose = { [weak self] value in
            guard let self else { return }
            guard !self.state.phase.busy, self.state.phase != .recording else { picker.refresh(); return }
            if value == "browse" {
                picker.refresh()
                self.openLocalModels(category: category)
                return
            }
            guard self.state.chooseModelProvider(value, category: category, personal: [], change: { _ in }) else {
                self.message = "This model is not installed or cannot run on this Mac."
                self.rebuild()
                return
            }
            self.rebuild()
        }
        register(picker, id: prefix + ".choice") { control in (control as? LocalModelChoicePicker)?.chooseSelected() }
        row("Model", picker)
        if let id = state.managedLocalModelID(for: category), let model = state.localModels.catalog.first(where: { $0.id == id }) {
            if !state.localModels.memoryFits(model) { note("Requires about " + model.memoryGB.formatted() + " GB of memory. Choose a smaller model.") }
            else if !model.isNative && !state.localModels.supported { note("Requires Apple silicon and macOS 26 or later.") }
            return
        }
        guard state.managedLocalModelID(for: category) == nil else { return }
        let configuration = state.localConfiguration(for: category)
        editor(prefix + ".model", title: "Model ID", value: configuration.model, placeholder: "Model name on your server") { [weak self] value in
            guard let self else { return nil }
            guard LocalEndpoint.validModelID(value) else { return "Enter a valid local model ID." }
            switch category {
            case "speech": self.state.localTranscriptionModel = value
            case "text": self.state.processingModel = value
            default: return "Unsupported local model category."
            }
            self.state.rememberCustomLocalEndpoint(for: category)
            return nil
        }
        editor(prefix + ".url", title: "Endpoint URL", value: configuration.url, placeholder: "http://localhost:1234/v1/…") { [weak self] value in
            guard let self else { return nil }
            do { _ = try LocalEndpoint.url(value) } catch { return error.localizedDescription }
            guard value != LocalModels.managedEndpoint else { return "Choose an installed model to use S2T’s managed runtime." }
            switch category {
            case "speech": self.state.localTranscriptionURL = value
            case "text": self.state.localProcessingURL = value
            default: return "Unsupported local model category."
            }
            self.state.rememberCustomLocalEndpoint(for: category)
            return nil
        }
        note("Use the full API URL of a running server, such as LM Studio or Ollama.")
    }

    private func openLocalModels(category: String) {
        localPane.selectCategory(category == "speech" ? 0 : 1)
        navigation.select(.local)
    }

    // MARK: Model menus

    private func modelChoiceKey(_ prefix: String) -> String {
        switch prefix {
        case "speech": return prefix + "." + (state.speechUsesCredits ? "s2t" : state.transcriptionProvider.rawValue)
        default: return prefix + "." + (state.cleanupUsesCredits ? "s2t" : state.processingProvider?.rawValue ?? "off")
        }
    }

    /// Build the current connection's model choices and custom editor. The popup is then grouped by
    /// provider; OpenRouter offers only the shortlist, the saved model and Custom model ID.
    private func modelChoices(_ prefix: String, recommended: [ModelSuggestion], more: [ModelSuggestion], model: String,
                              apply: @escaping (String, String?) -> String?) {
        var seen = Set<String>()
        let choices = (recommended + more).filter { seen.insert($0.model).inserted }
        let key = "models.custom." + modelChoiceKey(prefix)
        let legacyProvider = prefix == "speech" && state.speechUsesCredits ? state.creditSpeechProvider.rawValue
            : prefix == "cleanup" && state.cleanupUsesCredits ? state.creditCleanupProvider.rawValue : nil
        if let legacyProvider {
            for suffix in [".id", ".active"] where choicePreferences.object(forKey: key + suffix) == nil {
                if let value = choicePreferences.object(forKey: key + "." + legacyProvider + suffix) {
                    choicePreferences.set(value, forKey: key + suffix)
                }
            }
        }
        let custom = customEditors.contains(key) || choicePreferences.bool(forKey: key + ".active") || !choices.contains { $0.model == model }
        let savedCustom = choicePreferences.string(forKey: key + ".id")
        let field = NSTextField(string: modelDrafts[key] ?? (custom ? model : savedCustom ?? model))
        field.setAccessibilityLabel("Custom model ID")
        field.placeholderString = "Exact model ID"
        let feedback = NSTextField(wrappingLabelWithString: "")
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .secondaryLabelColor
        feedback.isHidden = true
        feedback.identifier = .init(prefix + ".model.feedback")
        controls[prefix + ".model.feedback"] = feedback

        let picker = NSPopUpButton()
        SettingsFormStyle.menuPicker(picker)
        picker.menu?.autoenablesItems = false
        picker.setAccessibilityLabel("Model")
        let id = prefix + ".choice"
        func item(_ choice: ModelSuggestion) -> NSMenuItem {
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.representedObject = choice.model
            item.toolTip = choice.host.isEmpty ? choice.model : choice.model + " · " + choice.host
            if !choice.detail.isEmpty, #available(macOS 14.4, *) { item.subtitle = choice.detail }
            return item
        }
        let category = prefix == "cleanup" ? "text" : prefix
        let credits = state.usesCredits(for: category)
        let operation = prefix == "speech" ? "transcription" : "cleanup"
        let openRouter = credits || (prefix == "speech" ? state.transcriptionProvider == .openRouter : state.processingProvider == .openRouter)
        let nonRouter = credits ? choices.filter { choice in
            state.creditModels.contains { $0.operation == operation && $0.model == choice.model && $0.provider != "openrouter" }
        } : []
        var top: [ModelSuggestion] = []
        for choice in (openRouter ? recommended + nonRouter : choices) where !top.contains(where: { $0.model == choice.model }) { top.append(choice) }
        if !custom, !top.contains(where: { $0.model == model }), let current = choices.first(where: { $0.model == model }) { top.append(current) }
        for choice in top { picker.menu?.addItem(item(choice)) }
        if picker.numberOfItems > 0 { picker.menu?.addItem(.separator()) }
        picker.appendItem("Custom model ID…", value: "custom")
        func selectCurrent() {
            if custom { picker.selectItem(value: "custom") } else { picker.selectItem(value: model) }
        }
        selectCurrent()

        let save = NSButton(title: "Save", target: nil, action: nil)
        styleAction(save)
        row("Model", picker)
        let customRow = row("Model ID", SettingsFormStyle.field(field), save)
        modelEditors.append((key, field, customRow))
        customRow.isHidden = !custom
        separatorBefore(customRow)?.isHidden = !custom
        func showFeedback(_ error: String?) {
            feedback.stringValue = error ?? ""
            feedback.textColor = error == nil ? .secondaryLabelColor : .systemRed
            feedback.isHidden = feedback.stringValue.isEmpty
            field.setAccessibilityHelp(error)
        }
        let choose: (String) -> Void = { [weak self] value in
            guard let self, !self.state.phase.busy, self.state.phase != .recording else { return }
            if value == "custom" {
                customRow.isHidden = false
                self.separatorBefore(customRow)?.isHidden = false
                self.customEditors.insert(key)
                if !custom { field.stringValue = self.modelDrafts[key] ?? savedCustom ?? model }
                self.view.window?.makeFirstResponder(field)
                return
            }
            guard let choice = choices.first(where: { $0.model == value }) else { return }
            let error = apply(choice.model, choice.host.isEmpty ? nil : choice.host)
            showFeedback(error)
            guard error == nil else {
                selectCurrent()
                return
            }
            self.customEditors.remove(key)
            self.choicePreferences.set(false, forKey: key + ".active")
            self.rebuild()
        }
        menuChoices[id] = choose
        register(picker, id: id) { control in
            if let value = (control as? NSPopUpButton)?.selectedItem?.representedObject as? String { choose(value) }
        }
        register(field, id: prefix + ".model") { [weak self, weak field] _ in
            guard let self, let field, self.controls[prefix + ".model"] === field,
                  !self.state.phase.busy, self.state.phase != .recording else { return }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if credits && !ProcessingProvider.openRouter.validModelID(value) {
                showFeedback("Enter a model ID such as provider/model, or choose a model from its submenu.")
                return
            }
            let error = apply(value, nil)
            showFeedback(error)
            guard error == nil else { return }
            self.modelDrafts[key] = value
            self.choicePreferences.set(value, forKey: key + ".id")
            self.choicePreferences.set(true, forKey: key + ".active")
            field.stringValue = value
            self.view.window?.makeFirstResponder(nil)
            self.rebuild()
        }
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        register(save, id: prefix + ".model.save") { [weak field] _ in
            guard let field else { return }
            field.sendAction(field.action, to: field.target)
        }
        add(feedback)
    }

    /// Keep the connection picker, but put service choices one level below Model. A model action
    /// reuses the task's existing save/validation path; merely opening a branch changes no settings.
    private func configureProviderModelMenus(prefixes: [String] = ["speech", "cleanup"]) {
        for prefix in prefixes {
            let id = controls[prefix + ".choice"] == nil ? prefix + ".mode" : prefix + ".choice"
            guard let picker = controls[id] as? NSPopUpButton else { continue }
            for key in groupedActionIDs[prefix] ?? [] { groupedMenuActions.removeValue(forKey: key) }
            groupedActionIDs[prefix] = []
            if modelMenuSources[prefix] == nil { modelMenuSources[prefix] = (picker.itemArray, picker.selectedItem) }
            guard let source = modelMenuSources[prefix] else { continue }
            let original = source.items
            let current = source.current?.copy() as? NSMenuItem
            let category = prefix == "cleanup" ? "text" : prefix
            let credits = state.usesCredits(for: category)
            let operation = prefix == "speech" ? "transcription" : "cleanup"
            let provider = prefix == "speech" ? (credits ? state.creditSpeechProvider : state.transcriptionProvider).rawValue
                : (credits ? state.creditCleanupProvider.rawValue : state.processingProvider?.rawValue ?? "")
            let menu = NSMenu()
            menu.autoenablesItems = false
            // NSPopUpButton displays a selected top-level item. Hide that summary in the open menu,
            // and keep the real checked choice in its provider submenu.
            if let current { current.isHidden = true; menu.addItem(current) }
            let providers = prefix == "speech" ? ["openrouter", "assemblyai", "local", "xai"] : ["openrouter", "local", "xai", "codex"]
            for service in providers where state.isProviderVisible(service) {
                let isLocal = service == "local"
                let active = service == provider
                let source: [NSMenuItem]
                if isLocal {
                    source = active ? original : LocalModelChoicePicker(state: state, category: category).itemArray
                } else if credits && service == "xai" {
                    source = creditXAIModelMenuItems(prefix: prefix)
                } else if credits {
                    guard service != "codex" else { continue }
                    source = original.filter { item in
                        guard let value = item.representedObject as? String else { return false }
                        if value == "custom" { return service == "openrouter" }
                        return state.creditModels.contains { $0.operation == operation && $0.provider == service && $0.model == value }
                            || (service == "openrouter" && state.creditOpenRouterCatalog && value.contains("/"))
                    }
                } else if active { source = original }
                else { source = personalModelMenuItems(prefix: prefix, provider: service) }
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for sourceItem in source {
                    guard !sourceItem.isSeparatorItem || !submenu.items.isEmpty else { continue }
                    let item = sourceItem.copy() as! NSMenuItem
                    item.state = .off
                    if let value = item.representedObject as? String {
                        if value == "custom", submenu.items.last?.isSeparatorItem == false { submenu.addItem(.separator()) }
                        item.state = active && value == (current?.representedObject as? String) ? .on : .off
                        item.target = self
                        item.action = #selector(chooseGroupedModel(_:))
                        groupedMenuActions[ObjectIdentifier(item)] = { [weak self] in
                            self?.selectGroupedModel(prefix: prefix, provider: service, value: value, credits: credits)
                        }
                        groupedActionIDs[prefix, default: []].append(ObjectIdentifier(item))
                    }
                    submenu.addItem(item)
                }
                guard !submenu.items.isEmpty else { continue }
                let title = service == "assemblyai" ? "AssemblyAI" : service == "openrouter" ? "OpenRouter" : service == "local" ? "Local" : service == "codex" ? "Codex" : "xAI"
                let branch = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                branch.identifier = .init(service)
                branch.state = active ? .on : .off
                branch.submenu = submenu
                if service == "local" { branch.toolTip = "Runs on this Mac or your own server." }
                menu.addItem(branch)
            }
            picker.menu = menu
            if let current { picker.select(current) }
            if let local = picker as? LocalModelChoicePicker {
                local.didRefresh = { [weak self, weak local] in
                    guard let self, let local, self.controls[id] === local else { return }
                    self.modelMenuSources[prefix] = (local.itemArray, local.selectedItem)
                    self.configureProviderModelMenus(prefixes: [prefix])
                }
            }
        }
    }

    /// Keep xAI discoverable even when this account's S2T catalog does not offer it. Disabled
    /// model rows explain the restriction; changing to personal billing requires its own action.
    private func creditXAIModelMenuItems(prefix: String) -> [NSMenuItem] {
        let operation = prefix == "speech" ? "transcription" : "cleanup"
        let available = state.creditModels.filter { $0.operation == operation && $0.provider == "xai" }
        var seen = Set<String>()
        var items = available.filter { seen.insert($0.model).inserted }.map { model in
            let item = NSMenuItem(title: model.title, action: nil, keyEquivalent: "")
            item.representedObject = model.model
            item.toolTip = model.model + " · Uses S2T credits"
            return item
        }
        for item in personalModelMenuItems(prefix: prefix, provider: "xai") {
            guard let value = item.representedObject as? String, value != "custom", seen.insert(value).inserted else { continue }
            item.isEnabled = false
            item.toolTip = "Not available with S2T credits. Choose Use xAI API key to use this model with your own account."
            if #available(macOS 14.4, *) { item.subtitle = "Requires your xAI API key" }
            items.append(item)
        }
        items.append(.separator())
        let personal = NSMenuItem(title: "Use xAI API key…", action: nil, keyEquivalent: "")
        personal.representedObject = Self.personalXAI
        personal.toolTip = "Switch this task to your personal xAI account. S2T credits will not be used."
        items.append(personal)
        return items
    }

    private func personalModelMenuItems(prefix: String, provider: String) -> [NSMenuItem] {
        var choices: [ModelSuggestion]
        switch provider {
        case "openrouter": choices = prefix == "speech" ? ModelRecommendations.openRouterSpeech : ModelRecommendations.cleanup
        case "assemblyai": choices = TranscriptionMode.allCases.map { .init(model: $0.rawValue, title: $0 == .fast ? "Universal 3.5 Pro" : "Universal · Extended languages") }
        case "xai": choices = prefix == "speech" ? TranscriptionProvider.xaiModels.map { .init(model: $0, title: $0.hasSuffix("2.0") ? "Grok Voice 2.0" : "Grok Voice 1.0") } : [.init(model: "grok-4.6", title: "Grok 4.6")]
        case "codex": choices = [.init(model: "default", title: "Codex default")] + catalog.filter { $0.visibility == "list" }.map { .init(model: $0.slug, title: $0.display_name) }
        default: choices = []
        }
        var items = choices.map { choice in
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.representedObject = choice.model
            item.toolTip = choice.model
            if !choice.detail.isEmpty, #available(macOS 14.4, *) { item.subtitle = choice.detail }
            return item
        }
        if provider != "assemblyai" {
            let custom = NSMenuItem(title: "Custom model ID…", action: nil, keyEquivalent: "")
            custom.representedObject = "custom"
            items.append(custom)
        }
        return items
    }

    @objc private func chooseGroupedModel(_ item: NSMenuItem) {
        guard item.isEnabled, !state.phase.busy, state.phase != .recording else { return }
        groupedMenuActions[ObjectIdentifier(item)]?()
    }

    private func selectGroupedModel(prefix: String, provider: String, value: String, credits: Bool) {
        guard (!credits || state.isProviderVisible("s2t")) && state.isProviderVisible(provider) else { return }
        let category = prefix == "cleanup" ? "text" : prefix
        guard state.usesCredits(for: category) == credits else { return }
        if provider == "xai", value == Self.personalXAI {
            (controls[prefix + ".provider"] as? ModelProviderPicker)?.choose("xai")
            return
        }
        if provider == "local" {
            if value == "browse" { openLocalModels(category: category); return }
            guard state.chooseModelProvider(value, category: category, personal: [], change: { _ in }) else { return }
            rebuild()
            return
        }
        if credits && value != "custom" {
            let operation = prefix == "speech" ? "transcription" : "cleanup"
            guard state.creditModels.contains(where: { $0.operation == operation && $0.provider == provider && $0.model == value })
                || (provider == "openrouter" && state.creditOpenRouterCatalog && ProcessingProvider.openRouter.validModelID(value)) else {
                message = "This model is no longer available with S2T credits. Refresh the model list."
                rebuild()
                return
            }
        }
        if !credits {
            let current = prefix == "speech" ? state.transcriptionProvider.rawValue : state.processingProvider?.rawValue
            if current != provider { (controls[prefix + ".provider"] as? ModelProviderPicker)?.choose(provider) }
        }
        if provider == "assemblyai", !credits, let mode = TranscriptionMode(rawValue: value) {
            state.transcriptionMode = mode
            rebuild()
        } else { menuChoices[prefix + ".choice"]?(value) }
    }

    // MARK: Accounts

    /// Appears only when the selected provider needs a key or its key needs attention.
    private func accountRow(category: String, prefix: String) {
        let value = state.usesCredits(for: category) ? "s2t" : prefix == "speech" ? state.transcriptionProvider.rawValue
            : state.processingProvider?.rawValue ?? ""
        guard ["s2t", "assemblyai", "openrouter", "xai"].contains(value) else { return }
        let issue = state.keyStatuses[value]?.needsAttention == true
        let checking = state.keyStatuses[value] == .checking
        let saved = state.savedKeyAccounts.contains(value)
        let operation = category == "speech" ? "transcription" : "cleanup"
        if value == "s2t", saved, !issue, !state.creditModels.contains(where: { $0.operation == operation }) {
            note("No S2T models have loaded yet. Use Refresh in the toolbar to try again.")
        }
        guard !saved || issue || checking else { return }
        let name = value == "s2t" ? "S2T" : value == "xai" ? "xAI" : value == "assemblyai" ? "AssemblyAI" : "OpenRouter"
        let status = NSTextField(labelWithString: checking ? "Checking…" : issue ? "Needs attention" : "Not added")
        status.textColor = issue ? .systemOrange : .secondaryLabelColor
        status.identifier = .init(prefix + ".accountStatus")
        controls[prefix + ".accountStatus"] = status
        let action = NSButton(title: issue ? "Fix key…" : "Add key…", target: nil, action: nil)
        styleAction(action)
        register(action, id: prefix + ".keys") { [weak self] _ in self?.openAPIKeys?(value) }
        row(name + " key", status, action)
        if issue, let explanation = state.keyStatuses[value]?.message { note(explanation) }
    }

    // MARK: Page structure

    /// Scrolls to a task's section, or to the top.
    private func reveal(_ section: ModelsSection?) {
        view.layoutSubtreeIfNeeded()
        let y = section.flatMap { sectionAnchors[$0] }.map { max(0, $0.frame.minY - 12) } ?? 0
        let limit = max(0, stack.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(y, limit)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func showSettings(containing controlID: String) {
        if navigation.page != .settings { navigation.showOverview() } else { refreshForPresentation() }
        guard let control = controls[controlID] else { return }
        view.layoutSubtreeIfNeeded()
        control.scrollToVisible(control.bounds.insetBy(dx: 0, dy: -24))
    }

    private func updateVisibility() {
        scroll.isHidden = navigation.page != .settings && navigation.page != .providers
        localPane.view.isHidden = navigation.page != .local
        comparison.isHidden = navigation.page != .compare
    }

    private func heading(_ title: String, section: ModelsSection?) {
        group = nil
        groupRows = 0
        let container = NSView()
        container.identifier = .init("models.heading." + (title.isEmpty ? "pages" : title))
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: title.isEmpty ? 4 : 14),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: title.isEmpty ? 0 : -2)
        ])
        add(container)
        if let section { sectionAnchors[section] = container }
    }

    private func beginGroup(_ id: String) {
        let card = SettingsGroup(grouped: true, verticalInset: 8, horizontalInset: 10)
        card.identifier = NSUserInterfaceItemIdentifier("models.group." + id)
        card.stack.spacing = 7
        group = nil
        add(card)
        group = card
        groupRows = 0
    }

    private func separator() {
        let line = NSBox()
        line.boxType = .separator
        add(line)
    }

    private func separatorBefore(_ row: NSView) -> NSView? {
        guard let rows = row.superview as? NSStackView, let index = rows.arrangedSubviews.firstIndex(of: row), index > 0,
              let line = rows.arrangedSubviews[index - 1] as? NSBox, line.boxType == .separator else { return nil }
        return line
    }

    private func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        add(label)
    }

    @discardableResult private func popup(_ id: String, title: String, choices: [(String, String)], selected: String, change: @escaping (String) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton()
        SettingsFormStyle.menuPicker(popup)
        for (value, label) in choices { popup.appendItem(label, value: value) }
        popup.selectItem(value: selected)
        popup.setAccessibilityLabel(title)
        register(popup, id: id) { control in
            if let value = (control as? NSPopUpButton)?.selectedItem?.representedObject as? String { change(value) }
        }
        row(title, popup)
        return popup
    }

    private func providerPopup(_ id: String, category: String, choices: [(String, String)], selected: @escaping () -> String, change: @escaping (String) -> Void) {
        let popup = ModelProviderPicker(state: state, category: category, providers: choices, selected: selected,
            change: change, changed: { [weak self] in self?.rebuild() })
        popup.identifier = .init(id)
        controls[id] = popup
        row("Provider", popup)
    }

    /// Saves on Return or when editing ends; Escape keeps the draft without saving.
    private func editor(_ id: String, title: String, value: String, placeholder: String = "", save: @escaping (String) -> String?) {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.setAccessibilityLabel(title)
        let feedback = NSTextField(wrappingLabelWithString: "")
        feedback.font = .systemFont(ofSize: 12)
        feedback.textColor = .systemRed
        feedback.isHidden = true
        let button = NSButton(title: "Save", target: self, action: #selector(invoke(_:)))
        styleAction(button)
        field.identifier = .init(id)
        controls[id] = field
        register(button, id: id + ".save") { [weak self, weak field, weak feedback] _ in
            guard let self, let field else { return }
            let error = save(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            self.message = ""
            if error == nil { self.rebuild() }
            else {
                field.toolTip = error
                field.setAccessibilityHelp(error)
                feedback?.stringValue = error ?? ""
                feedback?.isHidden = false
            }
        }
        SettingsFormStyle.submit(field, with: button)
        row(title, SettingsFormStyle.field(field), button)
        add(feedback)
    }

    private func refreshAfterEditing() {
        let generation = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == generation else { return }
            let editor = self.view.window?.firstResponder as? NSTextView
            let field = editor?.isFieldEditor == true ? editor?.delegate as? NSTextField : nil
            let id = field?.identifier?.rawValue
            let draft = editor?.string
            let selection = editor?.selectedRange
            self.rebuild()
            if let id, let field = self.controls[id] as? NSTextField,
               let draft, self.view.window?.makeFirstResponder(field) == true,
               let editor = field.currentEditor() {
                field.stringValue = draft
                editor.string = draft
                if let selection { editor.selectedRange = selection }
            }
        }
    }

    private func register(_ control: NSControl, id: String, action: @escaping (NSControl) -> Void) {
        control.identifier = NSUserInterfaceItemIdentifier(id)
        control.target = self; control.action = #selector(invoke(_:))
        controls[id] = control; actions[id] = action
    }
    @objc private func invoke(_ sender: NSControl) { if let id = sender.identifier?.rawValue, controls[id] === sender { actions[id]?(sender) } }
    private func styleAction(_ button: NSButton) {
        SettingsFormStyle.nativeAction(button)
    }

    /// A settings row like System Settings: the label on the left, its control on the right, a separator above.
    @discardableResult private func row(_ title: String, _ controls: NSView...) -> NSStackView {
        if groupRows > 0 { separator() }
        // Every priority stays below the window's size priority (500), so a narrow window truncates rows
        // instead of being pushed wider. Labels truncate last, then buttons, menus and text fields.
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.init(495), for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(200), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, spacer] + controls)
        row.detachesHiddenViews = false
        row.distribution = .fill
        row.spacing = 8
        row.alignment = .centerY
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        for control in controls {
            if let field = control as? NSTextField, field.isEditable {
                field.setContentHuggingPriority(.init(100), for: .horizontal)
                field.setContentCompressionResistancePriority(.init(480), for: .horizontal)
                let minimum = field.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
                minimum.priority = .init(470)
                minimum.isActive = true
            } else if control is NSPopUpButton {
                control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                control.setContentCompressionResistancePriority(.init(490), for: .horizontal)
            } else {
                control.setContentHuggingPriority(.required, for: .horizontal)
                control.setContentCompressionResistancePriority(.init(498), for: .horizontal)
            }
        }
        add(row)
        groupRows += 1
        return row
    }

    private func add(_ child: NSView) {
        if let group { group.add(child); return }
        stack.addArrangedSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * Self.pageInset).isActive = true
    }
}
