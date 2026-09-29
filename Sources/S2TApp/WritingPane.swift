import AppKit
import Combine
import SwiftUI
import S2TCore

enum WritingFunding: String, CaseIterable, Codable {
    case personal = "Your providers", credits = "S2T credits"
}

struct WritingCreditSettings: Codable, Equatable {
    var provider = "openrouter"
    var model = CreditModel.defaults[0].model
    var host = CreditModel.defaults[0].host
    var options: [String: OpenRouterOptions] = [:]
}

struct WritingAISettings: Codable, Equatable {
    var provider = "openrouter"
    var routerModel = ProcessingProvider.defaultOpenRouterModel
    var codexModel = "default"
    var host = "cerebras/fp16"
    var routerOptions: [String: OpenRouterOptions] = [:]
    var codexOptions: [String: CodexOptions] = [:]
    var extraModels: [String: String]?
    var localURL: String?
    // Optional additions preserve decoding of settings saved before credit-funded writing.
    var payment: WritingFunding?
    var credit: WritingCreditSettings?
    var funding: WritingFunding {
        get { payment ?? .personal }
        set { payment = newValue }
    }
    var usesCredits: Bool { funding == .credits }
    var creditSettings: WritingCreditSettings {
        get { credit ?? .init() }
        set { credit = newValue }
    }
    var selectedProvider: ProcessingProvider { ProcessingProvider(rawValue: usesCredits ? creditSettings.provider : provider) ?? .openRouter }
    var selectedHost: String {
        get { usesCredits ? creditSettings.host : host }
        set { if usesCredits { creditSettings.host = newValue } else { host = newValue } }
    }
    var isCodex: Bool { selectedProvider == .codex }
    var isOpenRouter: Bool { selectedProvider == .openRouter }
    var connectionDescription: String {
        if usesCredits { return "Uses your S2T credits. Requests allow up to 16 KB including the document and requested change. Stopping a submitted request may still use credits." }
        switch selectedProvider {
        case .openRouter: return "Uses your OpenRouter key. Leave Host empty for automatic hosting."
        case .xai: return "Uses your xAI key."
        case .local: return "Sends this document and request to your local endpoint."
        case .codex: return "Uses your Codex CLI login."
        }
    }
    var model: String {
        get { usesCredits ? creditSettings.model : isCodex ? codexModel : isOpenRouter ? routerModel : extraModels?[provider] ?? selectedProvider.defaultModel }
        set {
            if usesCredits { creditSettings.model = newValue }
            else if isCodex { codexModel = newValue }
            else if isOpenRouter { routerModel = newValue }
            else { var models = extraModels ?? [:]; models[provider] = newValue; extraModels = models }
        }
    }
    var router: OpenRouterOptions {
        get { ((usesCredits ? creditSettings.options[model] : routerOptions[routerModel]) ?? .init()).normalized(for: model) }
        set { if usesCredits { creditSettings.options[model] = newValue } else { routerOptions[routerModel] = newValue } }
    }
    var codex: CodexOptions {
        get { codexOptions[codexModel] ?? .init() }
        set { codexOptions[codexModel] = newValue }
    }
}

@MainActor final class WritingEditor: ObservableObject {
    let state: AppState
    let directory: URL
    let promptDocument = WritingTextDocument()
    let dictionaryDocument = WritingTextDocument()
    let suggestionDocument = WritingTextDocument()
    let promptPreview = MarkdownPreviewDocument()
    let dictionaryPreview = MarkdownPreviewDocument()
    let suggestionPreview = MarkdownPreviewDocument()
    var document: WritingTextDocument { selection == .instructions ? promptDocument : dictionaryDocument }
    var previewDocument: MarkdownPreviewDocument { selection == .instructions ? promptPreview : dictionaryPreview }
    enum Review: String, CaseIterable { case changes = "Changes", suggestion = "Suggestion", original = "Original" }
    @Published var review = Review.changes
    var showingOriginal: Bool { review == .original }
    @Published private(set) var diff: WritingDiff?
    @Published private(set) var diffPending = false
    @Published private(set) var startedAt: Date?
    @Published var confirmReload = false
    @Published var showingAssistant = false
    @Published var showingMarkdownPreview = true
    @Published var showingDictionaryMarkdown = false
    private let defaults: UserDefaults
    private let api: DictationAPI
    private let allowsAI: Bool
    @Published var selection = WritingDocumentKind.instructions { didSet { cancel() } }
    @Published private(set) var drafts: [WritingDocumentKind: String] = [:]
    @Published private(set) var originals: [WritingDocumentKind: String] = [:]
    @Published var settings: WritingAISettings { didSet {
        if settings != oldValue { stopTask() }
        if settings.model != oldValue.model || settings.selectedProvider != oldValue.selectedProvider { refreshReasoning() }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "writing.ai.settings") }
    } }
    @Published var instruction = ""
    @Published private(set) var dictationPhase = WritingPromptDictationPhase.idle
    @Published private(set) var busy = false
    @Published private(set) var error = ""
    @Published var suggestion: String? { didSet {
        if suggestion != oldValue { refreshDiff() }
    } }
    @Published private(set) var favorites: Set<String> = []
    @Published var catalog: [CodexModel] = []
    private var task: Task<Void, Never>?
    private var diffTask: Task<Void, Never>?
    private var reasoningSubscription: AnyCancellable?
    private var reasoningRefreshTask: Task<Void, Never>?
    private var dictationTask: Task<Void, Never>?
    private let promptCapture: WritingPromptCapturing
    private let promptTranscriber: (Data) async throws -> String
    private var dictationStartedAt = Date()
    private var dictationGeneration = 0
    private var generation = 0
    private var suggestionSource = ""
    private var suggestionKind = WritingDocumentKind.instructions

    init(state: AppState, directory: URL? = nil, api: DictationAPI? = nil,
         promptCapture: WritingPromptCapturing? = nil,
         promptTranscriber: ((Data) async throws -> String)? = nil) {
        self.state = state
        self.promptCapture = promptCapture ?? LiveWritingPromptCapture()
        self.promptTranscriber = promptTranscriber ?? { [weak state] audio in
            guard let state else { throw ServiceError.message("S2T is no longer available.") }
            return try await state.transcribeWritingPrompt(audio)
        }
        self.directory = directory ?? (state.isPreview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("S2T-writing-preview-" + UUID().uuidString)
            : AppState.instructionsFile.url.deletingLastPathComponent())
        defaults = state.isPreview ? UserDefaults(suiteName: "com.s2t.preview")! : .standard
        settings = defaults.data(forKey: "writing.ai.settings").flatMap { try? JSONDecoder().decode(WritingAISettings.self, from: $0) } ?? .init()
        favorites = Set(defaults.stringArray(forKey: "writing.ai.favorites") ?? [])
        self.api = api ?? DictationAPI(transport: state.usageTransport())
        allowsAI = !state.isPreview || api != nil
        reasoningSubscription = NotificationCenter.default.publisher(for: OpenRouterReasoningCatalog.updated)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }
        refresh()
        do {
            for (kind, draft) in try WritingDraftStore(directory: self.directory).load() where drafts[kind] != draft.text {
                originals[kind] = draft.original
                drafts[kind] = draft.text
            }
        } catch { self.error = "Saved drafts could not be restored: " + error.localizedDescription }
    }
    var text: String {
        get { drafts[selection] ?? "" }
        set { setText(newValue, for: selection) }
    }
    func setText(_ value: String, for kind: WritingDocumentKind) {
        drafts[kind] = value
        if kind == selection { cancel(); error = "" }
        persistDrafts()
    }
    private func persistDrafts() {
        let pending = Dictionary(uniqueKeysWithValues: WritingDocumentKind.allCases.compactMap { kind -> (WritingDocumentKind, WritingDraft)? in
            guard let original = originals[kind], let draft = drafts[kind], draft != original else { return nil }
            return (kind, WritingDraft(original: original, text: draft))
        })
        do { try WritingDraftStore(directory: directory).save(pending) }
        catch { self.error = "Draft recovery could not be saved. Keep this window open or save a copy before quitting. " + error.localizedDescription }
    }
    var dirty: Bool { drafts[selection] != originals[selection] }
    var enabled: Bool { originals[selection] != nil }
    var dictionaryEntries: [DictionaryListEntry] { DictionaryList.entries(in: drafts[.dictionary] ?? "") }
    @discardableResult func addDictionaryEntry(term: String, context: String, replaces: String = "") -> Bool {
        do {
            try commitQuickEdit(DictionaryList.adding(term: term, context: context, replaces: replaces, to: drafts[.dictionary] ?? ""), kind: .dictionary)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func updateDictionaryEntry(_ entry: DictionaryListEntry, term: String, context: String, replaces: String? = nil) {
        do { try commitQuickEdit(DictionaryList.updating(id: entry.id, term: term, context: context, replaces: replaces, in: drafts[.dictionary] ?? ""), kind: .dictionary) }
        catch { self.error = error.localizedDescription }
    }
    func removeDictionaryEntry(_ entry: DictionaryListEntry) {
        do { try commitQuickEdit(DictionaryList.removing(id: entry.id, from: drafts[.dictionary] ?? ""), kind: .dictionary) }
        catch { self.error = error.localizedDescription }
    }
    /// Quick edits save a clean document. Existing source drafts remain explicitly saveable.
    private func commitQuickEdit(_ value: String, kind: WritingDocumentKind) throws {
        guard let original = originals[kind] else { throw ServiceError.message("Reload this document before editing.") }
        try WritingDocumentFile.validate(value, kind: kind)
        let wasClean = drafts[kind] == original
        setText(value, for: kind)
        if wasClean {
            try WritingDocumentFile(directory: directory, kind: kind).save(value, replacing: original)
            originals[kind] = value
            persistDrafts()
        }
    }
    @discardableResult func addRules(_ rules: [String]) -> Bool {
        do {
            try commitQuickEdit(WritingRules.adding(rules, to: drafts[.instructions] ?? ""), kind: .instructions)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        defaults.set(favorites.sorted(), forKey: "writing.ai.favorites")
    }
    var codexEntry: CodexModel? { catalog.first { $0.slug == settings.codexModel } }
    var canUseFast: Bool { settings.isCodex ? codexEntry?.supportsFast == true : settings.isOpenRouter && settings.selectedHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var reasoning: String {
        get { settings.isCodex ? codexEntry?.normalized(settings.codex).reasoning ?? "" : settings.router.reasoning.rawValue }
        set {
            guard reasoningChoices.contains(where: { $0.0 == newValue }) else { return }
            if settings.isCodex { settings.codex.reasoning = newValue }
            else { settings.router.reasoning = OpenRouterOptions.Effort(rawValue: newValue) ?? .automatic }
        }
    }
    var fast: Bool {
        get { canUseFast && (settings.isCodex ? settings.codex.fast : settings.router.fast) }
        set { if settings.isCodex { settings.codex.fast = newValue } else { settings.router.fast = newValue } }
    }
    var reasoningChoices: [(String, String)] {
        if settings.isCodex {
            return [("", "Model default")] + (codexEntry?.supported_reasoning_levels ?? [])
                .filter { CodexOptions(reasoning: $0.effort).isValid }.map { ($0.effort, $0.effort.capitalized) }
        }
        return OpenRouterOptions.supportedEfforts(for: settings.model).map { ($0.rawValue, $0.title) }
    }
    func refresh() {
        for kind in WritingDocumentKind.allCases where originals[kind] == nil || drafts[kind] == originals[kind] {
            do {
                let value = try WritingDocumentFile(directory: directory, kind: kind).read()
                originals[kind] = value; drafts[kind] = value
            } catch { self.error = error.localizedDescription }
        }
    }
    func reload() {
        do {
            let value = try WritingDocumentFile(directory: directory, kind: selection).read()
            cancel(); drafts[selection] = value; originals[selection] = value; error = ""
            persistDrafts()
        } catch { self.error = error.localizedDescription }
    }
    func save() {
        guard enabled, let original = originals[selection] else { return }
        do {
            try WritingDocumentFile(directory: directory, kind: selection).save(text, replacing: original)
            originals[selection] = text; error = ""
            persistDrafts()
        } catch { self.error = error.localizedDescription }
    }
    func loadCatalog() async {
        guard !state.isPreview else { return }
        refreshReasoning()
        async let textCatalog: () = state.refreshTextCatalog()
        let models = await Task.detached { try? CodexModelCatalog.read() }.value
        if let models { catalog = models }
        await textCatalog
        if settings.usesCredits { await state.refreshCredits() }
    }
    private func refreshReasoning() {
        reasoningRefreshTask?.cancel()
        guard !state.isPreview, settings.isOpenRouter else { return }
        let model = settings.model
        reasoningRefreshTask = Task {
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            await OpenRouterReasoningCatalog.shared.refresh(model: model)
        }
    }
    func improve() {
        guard enabled, !busy, !dictationPhase.active else { return }
        guard allowsAI else { error = "AI writing is unavailable in preview."; return }
        stopTask()
        let baseline = text, source = suggestion ?? text, kind = selection, settings = settings, instruction = instruction
        let generation = generation
        let key = settings.usesCredits ? "" : settings.isOpenRouter ? state.routerKey : settings.selectedProvider == .xai ? state.xaiKey : ""
        let executable = state.codexExecutable
        let codex = codexEntry?.normalized(settings.codex) ?? CodexOptions()
        busy = true; startedAt = Date(); error = ""
        task = Task { [weak self, api] in
            do {
                var localURL = settings.localURL ?? LocalEndpoint.defaultProcessingURL
                if !settings.usesCredits, settings.selectedProvider == .local, localURL == LocalModels.managedEndpoint {
                    guard let self, let model = self.state.localModels.catalog.first(where: { $0.id == settings.model && $0.category == "text" }) else {
                        throw ServiceError.message("Choose an installed writing model.")
                    }
                    localURL = try await self.state.localModels.url(for: model.id, path: "/chat/completions")
                }
                try Task.checkCancellation()
                let result: String
                if settings.usesCredits {
                    guard let self else { return }
                    result = try await self.state.improveWritingWithCredits(source, kind: kind, instruction: instruction,
                        settings: settings, requestID: UUID().uuidString)
                } else {
                    result = try await api.improveWritingDocument(source, kind: kind, instruction: instruction,
                        model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: key,
                        provider: settings.selectedProvider, endpoint: settings.isOpenRouter ? settings.selectedHost : nil,
                        codexExecutable: executable, codexOptions: codex, routerOptions: settings.router, localURL: localURL)
                }
                guard let self, !Task.isCancelled, self.generation == generation, self.selection == kind, self.text == baseline else { return }
                self.suggestionSource = baseline; self.suggestionKind = kind
                self.review = .changes
                self.suggestion = result; self.busy = false; self.startedAt = nil; self.task = nil
            } catch {
                guard let self, !Task.isCancelled, self.generation == generation else { return }
                self.error = error.localizedDescription; self.busy = false; self.startedAt = nil; self.task = nil
            }
        }
    }

    func submitInstruction() {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        improve()
    }

    func togglePromptDictation() {
        switch dictationPhase {
        case .idle: startPromptDictation()
        case .preparing, .transcribing: cancelPromptDictation()
        case .recording: finishPromptDictation()
        }
    }

    private func startPromptDictation() {
        guard enabled, !busy else { return }
        do { try state.reserveWritingPromptDictation() }
        catch { self.error = error.localizedDescription; return }
        dictationGeneration += 1
        let generation = dictationGeneration
        dictationPhase = .preparing
        error = ""
        dictationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await promptCapture.start(deviceUID: state.microphoneUID)
                try Task.checkCancellation()
                guard dictationGeneration == generation else { return }
                dictationStartedAt = Date()
                dictationPhase = .recording
            } catch is CancellationError { }
            catch {
                guard dictationGeneration == generation else { return }
                self.error = error.localizedDescription
                dictationPhase = .idle
                state.releaseWritingPromptDictation()
            }
        }
    }

    private func finishPromptDictation() {
        guard dictationPhase == .recording else { return }
        let duration = Date().timeIntervalSince(dictationStartedAt)
        let generation = dictationGeneration
        dictationPhase = .transcribing
        dictationTask = Task { [weak self] in
            guard let self else { return }
            let audio = await promptCapture.finish()
            do {
                try Task.checkCancellation()
                guard duration >= 0.3, audio.count > 44 else {
                    throw ServiceError.message("Hold the microphone button a little longer and try again.")
                }
                let spoken = try await promptTranscriber(audio)
                try Task.checkCancellation()
                guard dictationGeneration == generation else { return }
                if instruction.isEmpty || instruction.last?.isWhitespace == true { instruction += spoken }
                else { instruction += " " + spoken }
                dictationPhase = .idle
                dictationTask = nil
                state.releaseWritingPromptDictation()
            } catch is CancellationError { }
            catch {
                guard dictationGeneration == generation else { return }
                self.error = error.localizedDescription
                dictationPhase = .idle
                dictationTask = nil
                state.releaseWritingPromptDictation()
            }
        }
    }

    func cancelPromptDictation() {
        guard dictationPhase.active || state.writingPromptDictationActive else { return }
        dictationGeneration += 1
        dictationTask?.cancel()
        dictationTask = nil
        promptCapture.cancel()
        dictationPhase = .idle
        state.releaseWritingPromptDictation()
    }
    func applySuggestion() {
        guard enabled, !busy, let suggestion, suggestionKind == selection, suggestionSource == text else { return }
        text = suggestion
        self.suggestion = nil
        save()
    }
    func stopTask() {
        generation += 1; task?.cancel(); task = nil; busy = false; startedAt = nil
    }
    func cancel() {
        cancelPromptDictation()
        stopTask(); suggestion = nil; diff = nil; review = .changes
    }
    private func refreshDiff() {
        diffTask?.cancel(); diff = nil; diffPending = false
        guard let suggestion else { return }
        let original = suggestionSource
        diffPending = true
        diffTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
            let computation = Task.detached(priority: .userInitiated) { WritingDiff(from: original, to: suggestion) }
            let result = await withTaskCancellationHandler(operation: { await computation.value }, onCancel: { computation.cancel() })
            guard !Task.isCancelled, let self, self.suggestion == suggestion, self.suggestionSource == original else { return }
            self.diff = result; self.diffPending = false
        }
    }
}

@MainActor final class WritingPane: NSViewController {
    let editing: WritingEditor
    private(set) lazy var nativeToolbar = WritingToolbar(editing: editing)
    init(state: AppState, directory: URL? = nil, api: DictationAPI? = nil,
         promptCapture: WritingPromptCapturing? = nil,
         promptTranscriber: ((Data) async throws -> String)? = nil) {
        editing = WritingEditor(state: state, directory: directory, api: api,
            promptCapture: promptCapture, promptTranscriber: promptTranscriber)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let host = NSHostingView(rootView: WritingView(editing: editing, state: editing.state))
        host.sizingOptions = []
        view = host
    }
}

struct WritingView: View {
    @ObservedObject var editing: WritingEditor
    @ObservedObject var state: AppState
    @State private var newRule = ""
    @State private var optionsOpen = false
    private var text: Binding<String> {
        let kind = editing.selection
        return Binding(get: { editing.drafts[kind] ?? "" }, set: { editing.setText($0, for: kind) })
    }
    private var reviewing: Bool { editing.suggestion != nil }
    private var reviewingSuggestion: Bool { reviewing && editing.review == .suggestion }
    private var showingDictionaryList: Bool {
        editing.selection == .dictionary && !reviewing && !editing.showingDictionaryMarkdown
    }
    private var previewing: Bool { editing.selection == .instructions && editing.showingMarkdownPreview && !reviewing }
    private var activeText: Binding<String> {
        reviewingSuggestion ? Binding(get: { editing.suggestion ?? "" }, set: { editing.suggestion = $0 }) : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reviewing { reviewBar }
            else if editing.selection == .instructions { quickRules }
            if showingDictionaryList {
                DictionaryListView(editing: editing).frame(minHeight: 180, maxHeight: .infinity).padding(.horizontal, 24)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Toggle("Categorize corrections with Jev", isOn: $state.dictionaryCategorizationEnabled)
                            .toggleStyle(.switch).controlSize(.small)
                            .accessibilityIdentifier("dictionary.learning.categorization")
                        Spacer(minLength: 0)
                        if state.dictionaryCategorizationEnabled {
                            Picker("Use", selection: $state.dictionaryLearningRoute) {
                                if !state.isProviderVisible(state.dictionaryLearningRoute == .s2t ? "s2t" : state.dictionaryLearningRoute.jevRoute.account.rawValue) {
                                    Text("Current connection hidden").tag(state.dictionaryLearningRoute).disabled(true)
                                }
                                ForEach(DictionaryLearningRoute.allCases.filter { state.isProviderVisible($0 == .s2t ? "s2t" : $0.jevRoute.account.rawValue) }, id: \.self) { Text($0.title).tag($0) }
                            }.pickerStyle(.menu).fixedSize().accessibilityIdentifier("dictionary.learning.connection")
                        }
                    }
                    Text(!state.isProviderVisible("s2t") ? "Corrections save automatically. Optional categorization uses your selected connection afterward." : "Corrections save automatically. Optional categorization uses your selected key or S2T credits afterward.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if state.isProviderVisible(state.dictionaryLearningRoute == .s2t ? "s2t" : state.dictionaryLearningRoute.jevRoute.account.rawValue) {
                        Text(state.dictionaryLearningStatus).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).help(state.dictionaryLearningStatus).accessibilityIdentifier("dictionary.learning.status")
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            } else if reviewing && editing.review == .changes {
                if let diff = editing.diff {
                    WritingChangesView(diff: diff).frame(minHeight: 180, maxHeight: .infinity).padding(.horizontal, 24)
                } else {
                    ProgressView("Comparing changes…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if previewing {
                WritingMarkdownPreview(document: editing.previewDocument, markdown: editing.text, label: "Rendered instructions")
                    .frame(minHeight: 180, maxHeight: .infinity).padding(.horizontal, 24)
            } else {
                WritingTextEditor(document: reviewingSuggestion ? editing.suggestionDocument : editing.document, text: activeText,
                    editable: editing.enabled && !editing.busy && (!reviewing || reviewingSuggestion),
                    label: reviewingSuggestion ? "Suggested \(editing.selection.title.lowercased())" : editing.selection.title,
                    identifier: reviewingSuggestion ? "writing.suggestion" : "writing.editor")
                    .id(reviewingSuggestion ? "suggestion" : editing.selection.rawValue)
                    .frame(minHeight: 180, maxHeight: .infinity).padding(.horizontal, 24)
            }
            HStack {
                Text(reviewing ? (editing.review == .original ? "Original · Read only" : editing.review == .changes ? "Additions underlined · Deletions struck through" : "Edit the suggestion before applying") : editing.dirty ? "Unsaved changes" : "Saved locally")
                    .accessibilityIdentifier("writing.status")
                Spacer()
                Text(showingDictionaryList ? "\(editing.dictionaryEntries.count) entries" : "\(activeText.wrappedValue.split(whereSeparator: \.isWhitespace).count) words").monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 9)
            if !editing.error.isEmpty {
                Label(editing.error, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.vertical, 8).accessibilityIdentifier("writing.error")
            }
            Divider()
            aiControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background).textFieldStyle(.roundedBorder)
        .task { await editing.loadCatalog() }
        .onDisappear { editing.cancel() }
        .onChange(of: editing.enabled) { _, enabled in if !enabled { editing.cancel() } }
        .background {
            Button("Save") { if reviewing { editing.applySuggestion() } else { editing.save() } }
                .keyboardShortcut("s", modifiers: .command).hidden().accessibilityHidden(true)
        }
        .confirmationDialog("Reload the saved file and discard this draft?", isPresented: $editing.confirmReload) {
            Button("Reload", role: .destructive) { editing.reload() }
        }
    }

    private var quickRules: some View {
        HStack(spacing: 8) {
            TextField("Add a rule, e.g. use British spelling", text: $newRule)
                .accessibilityLabel("New instruction").accessibilityIdentifier("writing.rule")
                .onSubmit { addRule() }
            Button("Add rule", action: addRule).disabled(newRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("writing.rule.add")
            Menu("Templates") {
                ForEach(WritingRules.templates) { template in
                    Button(template.title) { editing.addRules(template.rules) }.help(template.summary)
                }
            }.fixedSize().accessibilityIdentifier("writing.templates")
        }.disabled(!editing.enabled || editing.busy).padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
    }
    private func addRule() { if editing.addRules([newRule]) { newRule = "" } }

    private var reviewBar: some View {
        HStack(spacing: 8) {
            SettingsChoiceBar(titles: WritingEditor.Review.allCases.map(\.rawValue),
                              selected: WritingEditor.Review.allCases.firstIndex(of: editing.review)!,
                              label: "Review version") { editing.review = WritingEditor.Review.allCases[$0] }
                .frame(width: 238).accessibilityIdentifier("writing.review.version")
            if let diff = editing.diff {
                Text("+\(diff.insertedWords) −\(diff.removedWords)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("\(diff.insertedWords) words added, \(diff.removedWords) removed")
            }
            Spacer(minLength: 0)
            Button("Discard") { editing.cancel() }.accessibilityIdentifier("writing.discard")
            Button("Apply & save") { editing.applySuggestion() }.buttonStyle(.borderedProminent)
                .disabled(editing.busy).accessibilityIdentifier("writing.apply")
        }.padding(.horizontal, 24).padding(.vertical, 10)
    }

    private var aiControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Toggle("Edit with AI", isOn: $editing.showingAssistant).toggleStyle(.switch)
                    .accessibilityIdentifier("writing.assistant.toggle")
                Spacer()
                if reviewing { Text("Ask for another change before applying").font(.caption).foregroundStyle(.secondary) }
            }
            if editing.showingAssistant {
                if !editing.busy {
                    HStack(spacing: 6) {
                        ForEach(editing.selection == .instructions ? ["Make it clearer", "Make it shorter", "Organize my rules"] : ["Remove duplicates", "Check spelling", "Organize entries"], id: \.self) { title in
                            Button(title) { editing.instruction = title }.controlSize(.small)
                        }
                    }
                }
                WritingPromptComposer(text: $editing.instruction, enabled: editing.enabled, busy: editing.busy,
                    startedAt: editing.startedAt, modelTitle: editing.selectedModelTitle,
                    dictationPhase: editing.dictationPhase,
                    submit: { editing.submitInstruction() }, cancel: { editing.stopTask() },
                    toggleDictation: { editing.togglePromptDictation() }) {
                        if state.isProviderVisible("s2t") {
                            Picker("Connection", selection: Binding(get: { editing.settings.funding }, set: { editing.selectFunding($0) })) {
                                ForEach(WritingFunding.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }.labelsHidden().fixedSize().disabled(editing.busy)
                                .accessibilityLabel("Writing AI connection").accessibilityIdentifier("writing.funding")
                        }
                        WritingModelButton(editing: editing, state: state, localModels: state.localModels)
                        if editing.modelProviderVisible {
                            Button { optionsOpen.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                                .help("Writing model options").accessibilityLabel("Writing model options")
                                .accessibilityIdentifier("writing.model.options").disabled(editing.busy)
                                .popover(isPresented: $optionsOpen) { WritingModelOptions(editing: editing).frame(width: 360).padding(18) }
                        }
                    }
                if state.isProviderVisible("s2t") && editing.settings.usesCredits && state.creditConnection == nil {
                    Text("Connect your S2T account in API keys to use credits.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
        .onChange(of: editing.showingAssistant) { _, shown in
            if !shown { editing.stopTask(); editing.cancelPromptDictation() }
        }
    }
}

private struct WritingModelOptions: View {
    @ObservedObject var editing: WritingEditor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Writing model options").font(.headline)
            LabeledContent("Model ID") { TextField("Model ID", text: $editing.settings.model).accessibilityIdentifier("writing.model") }
            if editing.settings.isOpenRouter {
                LabeledContent("Host") { TextField("Automatic", text: $editing.settings.selectedHost).accessibilityIdentifier("writing.host") }
            }
            if editing.settings.selectedProvider == .local {
                LabeledContent("Endpoint") {
                    TextField(LocalEndpoint.defaultProcessingURL, text: Binding(get: { editing.settings.localURL ?? LocalEndpoint.defaultProcessingURL }, set: { editing.settings.localURL = $0 }))
                        .accessibilityIdentifier("writing.local.url")
                }
            }
            if editing.settings.isOpenRouter || editing.settings.isCodex {
                Picker("Reasoning", selection: Binding(get: { editing.reasoning }, set: { editing.reasoning = $0 })) {
                    ForEach(editing.reasoningChoices, id: \.0) { Text($0.1).tag($0.0) }
                }.disabled(editing.reasoningChoices.count <= 1).accessibilityIdentifier("writing.reasoning")
                if editing.canUseFast {
                    Toggle(editing.settings.isCodex ? "Fast mode" : "Fast routing", isOn: Binding(get: { editing.fast }, set: { editing.fast = $0 }))
                        .accessibilityIdentifier("writing.speed")
                }
            }
            if editing.settings.isOpenRouter && editing.settings.model == OpenRouterOptions.contributorModel {
                Toggle("Allow Meta to use prompts and responses", isOn: $editing.settings.router.allowDataCollection)
            }
            Text(editing.settings.connectionDescription).font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(.roundedBorder)
    }
}
