import AppKit
import AVFoundation
import Combine
import Speech
import S2TCore

enum AppPage: String, CaseIterable {
    case dictation = "Dictation", settings = "General", connections = "API keys", models = "Models", appearance = "Appearance"
}

enum DictationPhase: Equatable {
    case idle, preparing, recording, transcribing, processing, complete, failed, preview, monitoring
    var label: String {
        switch self {
        case .idle: return "Ready when you are"
        case .preparing: return "Connecting microphone"
        case .recording: return "Listening to you"
        case .transcribing: return "Transcribing your words"
        case .processing: return "Refining your words"
        case .complete: return "Your words are ready"
        case .failed: return "Needs your attention"
        case .preview: return "Previewing the glow"
        case .monitoring: return "Testing microphone"
        }
    }
    var busy: Bool { [.preparing, .transcribing, .processing].contains(self) }
    var processingAudio: Bool { self == .transcribing || self == .processing }
}

@MainActor final class AppState: ObservableObject {
    let recentRecordings: RecentRecordings
    var recentRecordingID = UUID()
    let localUsage: LocalUsageLedger
    func usageTransport(credits: Bool = false) -> LocalUsageTransport {
        LocalUsageTransport(base: credits ? CreditTransport() : SessionTransport(), ledger: localUsage, credits: credits)
    }
    lazy var meetings = MeetingRecorder(directory: isPreview ? FileManager.default.temporaryDirectory.appendingPathComponent("S2T-meeting-preview-" + UUID().uuidString) : nil, defaults: preferences, transcriber: MeetingTranscriber(transport: usageTransport()), processingAPI: DictationAPI(transport: usageTransport()))
    @Published private(set) var meetingRecordingActive = false
    func reserveMeetingRecording() throws {
        guard !meetingRecordingActive, !writingPromptDictationActive, !phase.busy, phase != .recording, phase != .monitoring else {
            throw ServiceError.message("Finish the current recording before starting a meeting.")
        }
        guard !needsInstallation else { throw ServiceError.message(setupSummary) }
        meetingRecordingActive = true
    }
    func releaseMeetingRecording() { meetingRecordingActive = false }

    @Published var speechUsesCredits = false { didSet { preferences.set(speechUsesCredits, forKey: "speechUsesCredits") } }
    @Published var earlyTranscriptionEnabled = true { didSet { preferences.set(earlyTranscriptionEnabled, forKey: "earlyTranscriptionEnabled") } }
    @Published var cleanupUsesCredits = false { didSet { preferences.set(cleanupUsesCredits, forKey: "cleanupUsesCredits") } }
    @Published var creditsAddress = Bundle.main.object(forInfoDictionaryKey: "S2TCreditsURL") as? String ?? ""
    @Published var creditsKey = "" { didSet { keyEdited("s2t") } }
    @Published var creditConnection: CreditConnection?
    @Published var creditBalance: CreditBalance?
    @Published var creditModels = CreditModel.defaults
    @Published var creditOpenRouterCatalog = false
    @Published var creditSpeechProvider = TranscriptionProvider.assemblyAI { didSet { preferences.set(creditSpeechProvider.rawValue, forKey: "creditSpeechProvider") } }
    @Published var creditXAISpeechModel = TranscriptionProvider.xai.defaultModel { didSet { preferences.set(creditXAISpeechModel, forKey: "creditXAISpeechModel") } }
    var creditTranscriptionModel: String {
        get { creditSpeechProvider == .xai ? creditXAISpeechModel : creditSpeechProvider == .assemblyAI ? creditSpeechProvider.defaultModel : creditSpeechModel }
        set { if creditSpeechProvider == .xai { creditXAISpeechModel = newValue } else { creditSpeechModel = newValue } }
    }
    @Published var creditSpeechModel = "openai/whisper-large-v3-turbo" { didSet { preferences.set(creditSpeechModel, forKey: "creditSpeechModel") } }
    @Published var creditCleanupProvider = ProcessingProvider.openRouter { didSet { preferences.set(creditCleanupProvider.rawValue, forKey: "creditCleanupProvider") } }
    @Published var creditCleanupModel = "openai/gpt-oss-120b" { didSet { preferences.set(creditCleanupModel, forKey: "creditCleanupModel") } }
    @Published var creditCleanupHost = CreditModel.defaults[0].host { didSet { preferences.set(creditCleanupHost, forKey: "creditCleanupHost") } }
    @Published private var creditOptionsByModel: [String: OpenRouterOptions] = [:] { didSet { preferences.set(try? JSONEncoder().encode(creditOptionsByModel), forKey: "creditOptionsByModel") } }
    var creditCleanupOptions: OpenRouterOptions {
        get { (creditOptionsByModel[creditCleanupModel] ?? OpenRouterOptions()).normalized(for: creditCleanupModel) }
        set { creditOptionsByModel[creditCleanupModel] = newValue }
    }
    func hasSavedCreditCleanupOptions(for model: String) -> Bool { creditOptionsByModel[model] != nil }
    var creditBalanceLabel: String? {
        guard let balance = creditBalance else { return nil }
        let available = balance.available.formatted(.number.precision(.fractionLength(0...2)))
        let pending = balance.reserved > 0 ? " · \(balance.reserved.formatted(.number.precision(.fractionLength(0...2)))) pending" : ""
        return "\(available) credits" + pending
    }
    var creditStatusRefreshable = false
    let creditsAPI: CreditsAPI
    let creditsChecksEnabled: Bool
    var dictationSession: DictationSession?
    var creditRequestID: String {
        get { dictationSession?.requestID ?? "" }
        set { dictationSession?.requestID = newValue }
    }
    var interruptionTask: Task<Bool, Never>?
    @Published var isPreservingRecording = false
    var earlyTranscription: EarlyCreditTranscription?
    var earlyCancellation: Task<Void, Never>?
    var earlyTranscriptionWait: Double = 0

    @Published var promptModeEnabled: Bool { didSet { preferences.set(promptModeEnabled, forKey: "promptModeEnabled"); shortcutSettingsChanged?() } }
    @Published var promptShortcutKey: ShortcutKey { didSet { preferences.set(try? JSONEncoder().encode(promptShortcutKey), forKey: "promptShortcutKey"); shortcutSettingsChanged?() } }
    @Published var promptHoldEnabled: Bool { didSet { preferences.set(promptHoldEnabled, forKey: "promptHoldEnabled"); shortcutSettingsChanged?() } }
    @Published var promptTapEnabled: Bool { didSet { preferences.set(promptTapEnabled, forKey: "promptTapEnabled"); shortcutSettingsChanged?() } }
    var beginPromptShortcutCapture: (() -> Void)?
    var sessionIsPrompt = false
    var promptShortcutConflict: Bool { promptShortcutKey.matchesBinding(shortcutKey) }
    func saveShortcut(_ key: ShortcutKey, prompt: Bool) {
        guard !key.matchesBinding(prompt ? shortcutKey : promptShortcutKey) else {
            notice = "Choose different shortcuts for dictation and Prompt mode. That key is already assigned."; return
        }
        if prompt { promptShortcutKey = key } else { shortcutKey = key }
    }
    @Published var routerModelOptions: [String: OpenRouterOptions] {
        didSet { preferences.set(try? JSONEncoder().encode(routerModelOptions), forKey: "routerModelOptions") }
    }
    func routerOptions(model: String) -> OpenRouterOptions {
        (routerModelOptions["cleanup:" + model] ?? OpenRouterOptions()).normalized(for: model)
    }
    func setRouterOptions(_ options: OpenRouterOptions, model: String) {
        routerModelOptions["cleanup:" + model] = options
    }
    @Published var codexModelOptions: [String: CodexOptions] {
        didSet { preferences.set(try? JSONEncoder().encode(codexModelOptions), forKey: "codexModelOptions") }
    }
    func codexOptions(model: String) -> CodexOptions {
        codexModelOptions["cleanup:" + model] ?? CodexOptions()
    }
    func setCodexOptions(_ options: CodexOptions, model: String) {
        guard options.isValid else { return }
        codexModelOptions["cleanup:" + model] = options
    }
    @Published var codexExecutable: String { didSet { preferences.set(codexExecutable, forKey: "codexExecutable") } }
    @Published var promptLanguage: String { didSet { preferences.set(promptLanguage, forKey: "promptLanguage") } }
    @Published var promptStatus = "Experimental beta · Off by default"
    @Published var promptImages: [URL] = []
    let promptListener = PromptSpeechListener()
    var promptSession: PromptModeSession?
    let promptCaptureFeedback = PromptCaptureFeedback()
    /// Drawn from the event-tap thread during ⌘-drag.
    var promptSelectionBorder: PromptCaptureBorder { promptCaptureFeedback.border }
    let promptRegionCapture = PromptRegionCapture()

    var promptSetupTitle: String {
        if !PromptSpeechListener.permissionGranted { return "Allow Speech Recognition…" }
        if !PromptScreenshot.permissionGranted { return "Allow Screen Recording…" }
        return "Permissions ready"
    }
    func setUpPromptMode() {
        guard !isPreview, !needsInstallation else { return }
        if !PromptSpeechListener.permissionGranted {
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                Task { promptStatus = await PromptSpeechListener.requestPermission() ? "Speech Recognition allowed. Set up Screen Recording next." : "Allow Speech Recognition in System Settings." }
            } else { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!) }
        } else if !PromptScreenshot.permissionGranted {
            if preferences.bool(forKey: "promptScreenAccessRequested") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            } else {
                preferences.set(true, forKey: "promptScreenAccessRequested")
                _ = CGRequestScreenCaptureAccess()
            }
            promptStatus = "Allow S2T in Screen Recording settings. Prompt mode keeps a temporary local frame history and saves only the referenced images. You may need to relaunch S2T."
        }
    }
    func revealSavedPromptReferences() {
        guard FileManager.default.fileExists(atPath: promptStorageDirectory.path) else {
            promptStatus = "No reference images have been saved yet."; return
        }
        NSWorkspace.shared.activateFileViewerSelecting([promptStorageDirectory])
    }
    func revealPromptImages() {
        guard !promptImages.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(promptImages)
    }
    func copyPromptImage(_ url: URL) {
        guard promptImages.contains(url), let data = try? Data(contentsOf: url) else { return }
        outputPasteboard.clearContents()
        outputPasteboard.setData(Data(), forType: ClipboardMonitor.outputType)
        outputPasteboard.setData(data, forType: .png)
        promptStatus = "Reference image copied. Paste it into the same prompt as the matching image reference."
    }

    @Published var page: AppPage = .dictation
    @Published var phase: DictationPhase = .idle
    @Published private(set) var writingPromptDictationActive = false
    @Published var elapsed: TimeInterval = 0
    @Published var rawTranscript = ""
    @Published var output = ""
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var modelUsed = ""
    @Published var processingFailureModel: String?
    @Published var routeDescription = "Selected model"
    @Published var transcriptionProvider: TranscriptionProvider { didSet { preferences.set(transcriptionProvider.rawValue, forKey: "transcriptionProvider") } }
    @Published var xaiTranscriptionModel: String { didSet { preferences.set(xaiTranscriptionModel, forKey: "xaiTranscriptionModel") } }
    @Published var routerTranscriptionModel: String { didSet { preferences.set(routerTranscriptionModel, forKey: "routerTranscriptionModel") } }
    @Published private(set) var routerSpeechModels = SpeechModelCatalog.reference
    @Published private(set) var routerTextModels: [OpenRouterTextModel] = []
    private var speechCatalogRefreshedAt: Date?
    private var textCatalogRefreshedAt: Date?
    private var speechCatalogLoading = false
    private var textCatalogLoading = false
    private let speechCatalogLoader: (() async throws -> [SpeechModelCatalog])?
    func refreshSpeechCatalog(force: Bool = false) async {
        guard !speechCatalogLoading, !isPreview || speechCatalogLoader != nil,
              force || speechCatalogRefreshedAt.map({ Date().timeIntervalSince($0) >= 6 * 3600 }) ?? true else { return }
        speechCatalogLoading = true
        defer { speechCatalogLoading = false }
        do {
            let models: [SpeechModelCatalog]
            if let speechCatalogLoader { models = try await speechCatalogLoader() }
            else { models = try await SpeechModelCatalog.load() }
            try Task.checkCancellation()
            routerSpeechModels = models
            speechCatalogRefreshedAt = Date()
        } catch { }
    }
    func refreshTextCatalog(force: Bool = false) async {
        guard !textCatalogLoading, !isPreview,
              force || textCatalogRefreshedAt.map({ Date().timeIntervalSince($0) >= 6 * 3600 }) ?? true else { return }
        textCatalogLoading = true
        defer { textCatalogLoading = false }
        do {
            let models = try await OpenRouterTextModel.load()
            try Task.checkCancellation()
            routerTextModels = models
            textCatalogRefreshedAt = Date()
        } catch { }
    }

    @Published var artificialAnalysisKey = "" { didSet { keyEdited("artificialanalysis") } }
    @Published var assemblyKey = "" { didSet { keyEdited("assemblyai") } }
    @Published var xaiKey = "" { didSet { keyEdited("xai") } }
    @Published var routerKey = "" { didSet { keyEdited("openrouter") } }
    @Published var typeSafeKey = "" { didSet { keyEdited("typesafe") } }
    @Published var jevRoute: JevRoute { didSet { preferences.set(jevRoute.rawValue, forKey: "jevRoute") } }
    @Published var jevCleanupMode: JevCleanupMode { didSet { preferences.set(jevCleanupMode.rawValue, forKey: "jevCleanupMode") } }
    @Published var jevSummary = ""
    @Published var dictionaryCategorizationEnabled: Bool {
        didSet { preferences.set(dictionaryCategorizationEnabled, forKey: "dictionaryCategorizationEnabled"); dictionaryLearner.stop() }
    }
    @Published var dictionaryLearningRoute: DictionaryLearningRoute {
        didSet { preferences.set(dictionaryLearningRoute.rawValue, forKey: "dictionaryLearningRoute"); dictionaryLearner.stop() }
    }
    @Published private(set) var dictionaryLearningStatus = "Word corrections are detected and saved locally after dictation. No key or credits needed."
    @Published var keyStatuses: [String: APIKeyStatus] = [:]
    var keyChecks: [String: Task<Void, Never>] = [:]
    var keyRevisions: [String: UUID] = [:]
    @Published var processingProvider: ProcessingProvider? {
        didSet {
            preferences.set(processingProvider?.rawValue, forKey: "processingProvider")
            guard let processingProvider else { return }
            processingModel = preferences.string(forKey: processingProvider.modelPreferenceKey) ?? processingProvider.defaultModel
        }
    }
    @Published var credentialsSaved = false
    @Published var showOriginal = false
    @Published var overlayVisible = false
    @Published var copied = false
    @Published var pasteHint: String?
    @Published var isWaitingToPaste = false
    @Published var clipboardContextEnabled: Bool {
        didSet {
            preferences.set(clipboardContextEnabled, forKey: "clipboardContextEnabled")
            if clipboardContextEnabled && !isPreview { clipboardMonitor.start() }
            else { clipboardMonitor.stop() }
        }
    }
    let clipboardMonitor: ClipboardMonitor
    @Published var transcriptionMode: TranscriptionMode { didSet { preferences.set(transcriptionMode.rawValue, forKey: "transcriptionMode") } }
    @Published var shortcutAvailable = false
    @Published var shortcutAccessGranted = false
    @Published var shortcutStatus = "Accessibility access is required."
    @Published var microphoneAccess: AVAuthorizationStatus = .notDetermined
    @Published var shortcutTestActive = false
    @Published var shortcutTestPassed = false
    @Published var shortcutTestStatus = "Test your shortcut without recording."
    var testShortcut: (() -> Void)?
    var stopShortcutTest: (() -> Void)?
    var repairFnShortcut: (() -> Void)?
    var refreshShortcut: (() -> Void)?
    var needsInstallation: Bool { !isPreview && Self.needsInstallation(path: Bundle.main.bundlePath) }
    static func needsInstallation(path: String) -> Bool {
        path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }
    @Published private(set) var settingUpPermissions = false
    var dictationPermissionsReady: Bool {
        shortcutAccessGranted && microphoneAccess == .authorized
    }
    var setupReady: Bool { !needsInstallation && dictationPermissionsReady && setupKeysReady && (shortcutAvailable || (!holdEnabled && !tapEnabled)) }
    var setupKeysReady: Bool {
        let accounts = [speechUsesCredits ? "s2t" : transcriptionProvider.rawValue]
            + (mode == .verbatim ? [] : cleanupUsesCredits ? ["s2t"] : processingProvider.map { [$0.rawValue] } ?? [])
        return canRecord && accounts.filter { $0 != "local" && $0 != "codex" }.allSatisfy { savedKeyAccounts.contains($0) && keyStatuses[$0]?.needsAttention != true && keyStatuses[$0] != .checking }
    }
    var setupSummary: String {
        if needsInstallation { return "Drag S2T into Applications, then open that copy before granting access." }
        if !dictationPermissionsReady { return "Allow the two permissions below. S2T checks again when you return." }
        if !setupKeysReady { return "Configure your provider keys, local endpoints or Codex below. Verbatim needs only speech recognition." }
        if !shortcutAvailable && (holdEnabled || tapEnabled) { return shortcutStatus }
        if !holdEnabled && !tapEnabled { return "Shortcut behaviors are off. Use Start dictation in Settings, then Finish dictation." }
        if !holdEnabled { return "Click a text field. Tap \(shortcutKey.displayName) to start, then tap again to finish." }
        return "Click a text field, then hold \(shortcutKey.displayName) and speak. Release to finish."
    }
    var permissionActionTitle: String {
        if settingUpPermissions { return "Waiting for microphone access…" }
        if microphoneAccess == .denied { return "Open Microphone settings…" }
        if microphoneAccess == .restricted { return "Microphone access is restricted" }
        if microphoneAccess != .authorized { return "Allow microphone…" }
        return "Enable Accessibility…"
    }
    func refreshSetup() {
        guard !isPreview else { return }
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneAccess != permission { microphoneAccess = permission }
        if !needsInstallation { refreshShortcut?() }
    }
    var requestShortcutAccess: (() -> Void)?

    func setUpDictation() {
        guard !isPreview, !needsInstallation, !settingUpPermissions, !dictationPermissionsReady else { return }
        settingUpPermissions = true
        Task { [self] in
            defer { settingUpPermissions = false; refreshSetup() }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .audio) else {
                    notice = "Microphone access is off. Choose Set up dictation to enable it in System Settings."
                    return
                }
                notice = nil
                return
            case .denied:
                notice = "Enable S2T under Microphone, then choose Set up dictation to continue."
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                return
            case .restricted:
                notice = "Microphone access is restricted by this Mac's administrator."
                return
            case .authorized: break
            @unknown default: return
            }
            if !AXIsProcessTrusted() {
                notice = "Enable S2T under Accessibility for the activation key, text insertion, and dictionary learning."
                requestShortcutAccess?()
            } else {
                shortcutAccessGranted = true
                notice = nil
            }
        }
    }
    var beginShortcutCapture: (() -> Void)?
    var cancelShortcutCapture: (() -> Void)?
    var shortcutSettingsChanged: (() -> Void)?
    @Published var isCapturingShortcut = false
    let inputs = AudioInputs()
    @Published var microphoneUID: String { didSet { preferences.set(microphoneUID, forKey: "microphoneUID") } }
    @Published var shortcutKey: ShortcutKey {
        didSet {
            preferences.set(try? JSONEncoder().encode(shortcutKey), forKey: "shortcutKey")
            shortcutSettingsChanged?()
        }
    }
    @Published var holdEnabled: Bool { didSet { preferences.set(holdEnabled, forKey: "holdEnabled"); shortcutSettingsChanged?() } }
    @Published var tapEnabled: Bool { didSet { preferences.set(tapEnabled, forKey: "tapEnabled"); shortcutSettingsChanged?() } }
    @Published var savedKeyAccounts: Set<String> = []
    @Published var mode: WritingMode { didSet { preferences.set(mode.rawValue, forKey: "writingMode") } }
    @Published var processingModel: String { didSet { guard let processingProvider else { return }; preferences.set(processingModel, forKey: processingProvider.modelPreferenceKey) } }
    @Published var localProcessingURL: String { didSet { preferences.set(localProcessingURL, forKey: "localProcessingURL") } }
    @Published var localTranscriptionURL: String { didSet { preferences.set(localTranscriptionURL, forKey: "localTranscriptionURL") } }
    @Published var localTranscriptionModel: String { didSet { preferences.set(localTranscriptionModel, forKey: "localTranscriptionModel") } }
    func localConfiguration(for category: String) -> (url: String, model: String) {
        switch category {
        case "speech": return (localTranscriptionURL, localTranscriptionModel)
        case "text": return (localProcessingURL, preferences.string(forKey: ProcessingProvider.local.modelPreferenceKey) ?? ProcessingProvider.local.defaultModel)
        default: preconditionFailure("Unsupported local model category")
        }
    }

    func managedLocalModelID(for category: String) -> String? {
        let isLocal = category == "speech" ? transcriptionProvider == .local : processingProvider == .local
        let configuration = localConfiguration(for: category)
        return isLocal && configuration.url == LocalModels.managedEndpoint ? configuration.model : nil
    }

    func rememberCustomLocalEndpoint(for category: String) {
        let configuration = localConfiguration(for: category)
        guard configuration.url != LocalModels.managedEndpoint else { return }
        preferences.set(["url": configuration.url, "model": configuration.model], forKey: "customLocalEndpoint." + category)
    }

    func selectLocalEndpoint(for category: String) {
        guard !phase.busy, phase != .recording else { return }
        var configuration = localConfiguration(for: category)
        if configuration.url == LocalModels.managedEndpoint {
            let saved = preferences.dictionary(forKey: "customLocalEndpoint." + category) as? [String: String] ?? [:]
            let defaultModel = category == "speech" ? TranscriptionProvider.local.defaultModel : ProcessingProvider.local.defaultModel
            configuration = (saved["url"] ?? (category == "speech" ? LocalEndpoint.defaultTranscriptionURL : LocalEndpoint.defaultProcessingURL), saved["model"] ?? defaultModel)
        }
        switch category {
        case "speech":
            speechUsesCredits = false
            transcriptionProvider = .local
            localTranscriptionURL = configuration.url
            localTranscriptionModel = configuration.model
        case "text":
            cleanupUsesCredits = false
            processingProvider = .local
            localProcessingURL = configuration.url
            processingModel = configuration.model
        default: return
        }
    }

    @Published var routerEndpoint: String { didSet { preferences.set(routerEndpoint, forKey: "routerEndpoint") } }
    var processingSelectionLabel: String {
        guard let processingProvider else { return "Choose a text processing provider." }
        let host = processingProvider == .openRouter && !routerEndpoint.isEmpty ? " · Host: " + routerEndpoint : ""
        return "Model: " + processingModel + host
    }
    static var instructionsFile: InstructionsFile {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return InstructionsFile(url: directory.appendingPathComponent("S2T").appendingPathComponent(InstructionsFile.filename))
    }
    static var dictionaryFile: DictionaryFile {
        DictionaryFile(url: instructionsFile.url.deletingLastPathComponent().appendingPathComponent("dictionary.md"))
    }
    let dictionaryLearner = DictionaryLearner()
    func startDictionaryLearning(output: String, recipient: pid_t?, expectedField: AXUIElement?, insertionSelection: CFRange?, insertionBaseline: String?) {
        let route = dictionaryLearningRoute
        let key = (route == .typeSafe ? typeSafeKey : routerKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let connection = creditConnection
        let api = api, credits = creditsAPI, requestID = UUID().uuidString
        let judge: DictionaryLearningController.Judge = { [weak self] plan in
            do {
                if route == .s2t {
                    guard let connection else { throw ServiceError.message("Connect S2T credits in Settings to add categories.") }
                    return try await credits.learnDictionaryCorrection(plan, connection: connection, requestID: requestID)
                }
                guard !key.isEmpty else { throw ServiceError.message("Add your \(route.title) in Settings → API keys to add categories.") }
                return try await api.learnDictionaryCorrection(plan, apiKey: key, route: route)
            } catch {
                await self?.dictionaryLearningFailed(error, key: route == .s2t ? connection?.key ?? "" : key)
                throw error
            }
        }
        dictionaryLearner.start(output: output, file: Self.dictionaryFile, recipient: recipient, expectedField: expectedField,
            insertionSelection: insertionSelection.map { NSRange(location: $0.location, length: $0.length) },
            insertionBaseline: insertionBaseline,
            judge: dictionaryCategorizationEnabled ? judge : nil, onStatus: { [weak self] status in
            self?.dictionaryLearningStatus = status
            self?.preferences.set(status, forKey: "lastDictionaryLearningStatus")
        }, onError: { [weak self] error in
            self?.dictionaryLearningStatus = error
            self?.preferences.set(error, forKey: "lastDictionaryLearningStatus")
            self?.errorMessage = error
        })
    }
    private func dictionaryLearningFailed(_ error: Error, key: String) {
        guard !(error is CancellationError) else { return }
        _ = recordKeyFailure(error, using: key)
    }
    func revealDictionaryInFinder() {
        do {
            _ = try Self.dictionaryFile.read()
            NSWorkspace.shared.activateFileViewerSelecting([Self.dictionaryFile.url])
        } catch { errorMessage = "Could not reveal dictionary in Finder. " + error.localizedDescription }
    }
    func openInstructionsInFinder() {
        do {
            try Self.instructionsFile.ensureExists()
            NSWorkspace.shared.activateFileViewerSelecting([Self.instructionsFile.url])
        } catch { errorMessage = "Could not open the instructions file. " + error.localizedDescription }
    }
    func saveProcessingModel(_ value: String, for provider: ProcessingProvider) -> String? {
        guard processingProvider == provider else { return "Provider changed. Reopen Models before saving." }
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.validModelID(model) else { return "Enter a valid \(provider.title) model ID." }
        if provider == .openRouter && processingModel != model { routerEndpoint = "" }
        processingModel = model
        return nil
    }
    func useCerebrasThroughOpenRouter() {
        processingProvider = .openRouter
        processingModel = ProcessingProvider.defaultOpenRouterModel
        routerEndpoint = "cerebras/fp16"
    }
    var processingEndpoint: String? { processingProvider == .openRouter ? routerEndpoint : nil }
    @Published var menuAppearance: String { didSet { preferences.set(menuAppearance, forKey: "menuAppearance") } }
    @Published var inputOutlineNotice: String?
    @Published var disabledInputPresets: Set<String> {
        didSet { preferences.set(disabledInputPresets.sorted(), forKey: "disabledInputPresets") }
    }
    @Published var glowAppearance: GlowAppearance { didSet { preferences.set(glowAppearance.rawValue, forKey: "glowAppearance") } }
    @Published var classicAnchor: GlassCapsuleAnchor? {
        didSet {
            if let classicAnchor, let data = try? JSONEncoder().encode(classicAnchor) {
                preferences.set(data, forKey: "liquidGlassPlacement.v1")
            }
        }
    }
    @Published var bezelVerticalPosition: Double { didSet { preferences.set(bezelVerticalPosition, forKey: "bezelVerticalPosition") } }
    @Published var bezelSide: BezelSide { didSet { preferences.set(bezelSide.rawValue, forKey: "bezelSide") } }
    @Published var glowWidth: Double { didSet { preferences.set(glowWidth, forKey: "glowWidth") } }
    @Published var glowMinimum: Double { didSet { preferences.set(glowMinimum, forKey: "glowMinimum") } }
    @Published var glowMaximum: Double { didSet { preferences.set(glowMaximum, forKey: "glowMaximum") } }
    @Published var glowTuning: GlowTuning {
        didSet { if let data = try? JSONEncoder().encode(glowTuning.normalized) { preferences.set(data, forKey: "glowTuning") } }
    }
    var glowResponseSettings: GlowResponseSettings { .init(width: glowWidth, minimum: glowMinimum, maximum: glowMaximum, tuning: glowTuning) }
    @Published var glowStrength: Double { didSet { preferences.set(glowStrength, forKey: "glowStrength") } }

    let focusHistory: AppFocusHistory
    let preferences: UserDefaults
    static let optionalProviders = [(id: "s2t", title: "S2T credits"), (id: "openrouter", title: "OpenRouter"), (id: "xai", title: "xAI"), (id: "local", title: "Local")]
    @Published private(set) var hiddenProviders = Set<String>() {
        didSet { preferences.set(hiddenProviders.sorted(), forKey: "hiddenProviders") }
    }

    func isProviderVisible(_ id: String) -> Bool {
        !hiddenProviders.contains(id.lowercased())
    }

    func setProviderVisible(_ id: String, _ visible: Bool) {
        if visible { hiddenProviders.remove(id) }
        else { hiddenProviders.insert(id) }
    }

    func isModelProviderVisible(for category: String) -> Bool {
        let credits = usesCredits(for: category)
        guard !credits || isProviderVisible("s2t") else { return false }
        let provider = category == "speech" ? (credits ? creditSpeechProvider : transcriptionProvider).rawValue
            : credits ? creditCleanupProvider.rawValue : processingProvider?.rawValue ?? ""
        return isProviderVisible(provider)
    }
    let api: DictationAPI
    let microphone: Microphone
    let requestMicrophoneAccess: () async -> Bool
    var work: Task<Void, Never>?
    var connectionTask: Task<Void, Never>?
    var hideTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    var meterTimer: Timer?
    var startedAt = Date()
    var finishRequestedAt: TimeInterval?
    private var previewStartedAt: Double = 0
    var recording: Data? {
        get { dictationSession?.audio }
        set { dictationSession?.audio = newValue }
    }
    let recoveryStore: RecordingRecoveryStore?
    var recovery: RecordingRecovery? {
        get { dictationSession?.recovery }
        set { dictationSession?.recovery = newValue }
    }
    var recoveryIsSaved: Bool {
        get { dictationSession?.isSaved ?? true }
        set { dictationSession?.isSaved = newValue }
    }
    @Published var recoveredRecordings: [RecordingRecovery] = []
    @Published var historicalStreamingReceiptCount = 0
    var historicalReceiptNotice: String? {
        historicalStreamingReceiptCount > 0
            ? "Saved legacy streaming receipts need confirmation from S2T support. They may already have been reconciled; local receipt metadata is preserved."
            : nil
    }
    var canSaveRecording: Bool { recording != nil && !phase.busy && phase != .recording }

    var finishTargetTask: Task<TextInsertion.Target?, Never>?
    var promptDeliveryTarget: Task<TextInsertion.Target?, Never>? {
        phase != .preparing && phase != .recording ? finishTargetTask : nil
    }
    let bottomWindowTracker = WindowBottomTracker()
    var insertionTarget: TextInsertion.Target?
    var sessionMode: WritingMode { dictationSession?.configuration.mode ?? mode }
    private var audioChangeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    let isPreview: Bool
    let outputPasteboard: NSPasteboard
    let insertText: (String, TextInsertion.Target?, TextInsertion.BeforePaste?) async throws -> TextInsertion.Outcome
    let insertPromptImages: ([URL], pid_t?, NSPasteboard, Bool, TextInsertion.Target?) async throws -> PromptImageInsertion.Result
    let promptStorageDirectory: URL

    init(preview: Bool = false, previewPreferences: UserDefaults? = nil, microphone: Microphone = Microphone(), microphoneAccess: (() async -> Bool)? = nil, speechCatalogLoader: (() async throws -> [SpeechModelCatalog])? = nil, recoveryStore: RecordingRecoveryStore? = nil, api: DictationAPI? = nil, creditsAPI: CreditsAPI? = nil, clipboardMonitor: ClipboardMonitor? = nil, outputPasteboard: NSPasteboard? = nil, promptSession: PromptModeSession? = nil, insertPromptImages: (([URL], pid_t?, NSPasteboard, Bool) async throws -> PromptImageInsertion.Result)? = nil, insertText: ((String, TextInsertion.Target?) async throws -> TextInsertion.Outcome)? = nil) {
        self.speechCatalogLoader = speechCatalogLoader
        self.microphone = microphone
        self.requestMicrophoneAccess = microphoneAccess ?? {
            guard !preview else { return false }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        self.insertText = { text, target, beforePaste in
            if let insertText {
                if let beforePaste, !(try await beforePaste()) { return .noTarget }
                return try await insertText(text, target)
            }
            return try await TextInsertion.insert(text, into: target, beforePaste: beforePaste)
        }
        self.insertPromptImages = { images, recipient, board, beforeText, target in
            if let insertPromptImages { return try await insertPromptImages(images, recipient, board, beforeText) }
            guard !preview else { return .init(sentCount: 0, issue: "Image insertion is disabled in preview.", clipboardChange: board.changeCount) }
            let pinned = target?.promptDestination != nil
            let command = await target?.pasteCommand?.value
            return try await PromptImageInsertion.handOver(images, recipient: recipient, board: board,
                currentRecipient: { pinned ? target?.app.processIdentifier : NSWorkspace.shared.frontmostApplication?.processIdentifier },
                destinationIsCurrent: { if !pinned { return true }; return await TextInsertion.promptDestinationIsCurrent(target) },
                nativePaste: command.map { command in { await Task.detached { AXUIElementPerformAction(command, kAXPressAction as CFString) }.value } },
                textPastedAt: target?.textPastedAt)
        }
        self.recoveryStore = recoveryStore ?? (preview ? nil : RecordingRecoveryStorage.makeStore())
        self.promptSession = preview ? promptSession : nil
        promptStorageDirectory = preview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("s2t-prompt-preview-" + UUID().uuidString)
            : Self.instructionsFile.url.deletingLastPathComponent().appendingPathComponent("Prompt references")
        self.outputPasteboard = outputPasteboard ?? (preview ? NSPasteboard(name: NSPasteboard.Name("com.s2t.preview.output.\(UUID().uuidString)")) : .general)
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor(persistence: preview ? nil : ClipboardStorage.makeStore())
        self.recentRecordings = RecentRecordings(store: preview ? nil : TranscriptHistoryStorage.makeStore())
        self.isPreview = preview
        focusHistory = AppFocusHistory(observe: !preview)
        let ledger = LocalUsageLedger(file: preview ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T/local-usage.json"))
        self.localUsage = ledger
        self.api = api ?? DictationAPI(transport: LocalUsageTransport(ledger: ledger))
        self.creditsAPI = creditsAPI ?? CreditsAPI(transport: LocalUsageTransport(base: CreditTransport(), ledger: ledger, credits: true), device: preview ? nil : CreditDeviceIdentity.current())
        creditsChecksEnabled = !preview || creditsAPI != nil
        preferences = preview ? (previewPreferences ?? UserDefaults(suiteName: "com.s2t.preview")!) : .standard
        hiddenProviders = Set(preferences.stringArray(forKey: "hiddenProviders") ?? [])
        preferences.removeObject(forKey: "hideExtraProviders")
        if !preview, !preferences.bool(forKey: "legacyPreferencesImported") {
            if let previous = UserDefaults(suiteName: "com.sotto.dictation") {
                for key in ["writingMode", "fallbackModel", "autoCopy", "pasteToApp", "glowStrength"] where preferences.object(forKey: key) == nil {
                    if let value = previous.object(forKey: key) { preferences.set(value, forKey: key) }
                }
            }
            preferences.set(true, forKey: "legacyPreferencesImported")
        }
        let savedCreditSpeechProvider = preferences.string(forKey: "creditSpeechProvider")
        creditSpeechProvider = savedCreditSpeechProvider == "xai" ? .xai : savedCreditSpeechProvider == TranscriptionProvider.openRouter.rawValue ? .openRouter : .assemblyAI
        creditXAISpeechModel = preferences.string(forKey: "creditXAISpeechModel") ?? TranscriptionProvider.xai.defaultModel
        creditSpeechModel = preferences.string(forKey: "creditSpeechModel") ?? "openai/whisper-large-v3-turbo"
        let savedCreditCleanupModel = preferences.string(forKey: "creditCleanupModel") ?? "openai/gpt-oss-120b"
        let savedCreditCleanupProvider: ProcessingProvider = preferences.string(forKey: "creditCleanupProvider") == "xai" ? .xai : .openRouter
        creditCleanupModel = savedCreditCleanupModel
        creditCleanupProvider = savedCreditCleanupProvider
        creditCleanupHost = preferences.string(forKey: "creditCleanupHost") ?? (savedCreditCleanupProvider == .openRouter && savedCreditCleanupModel == CreditModel.defaults[0].model ? CreditModel.defaults[0].host : "")
        creditOptionsByModel = preferences.data(forKey: "creditOptionsByModel").flatMap { try? JSONDecoder().decode([String: OpenRouterOptions].self, from: $0) } ?? [:]
        speechUsesCredits = preferences.object(forKey: "speechUsesCredits") as? Bool ?? preferences.bool(forKey: "creditsEnabled")
        earlyTranscriptionEnabled = preferences.object(forKey: "earlyTranscriptionEnabled") as? Bool ?? !preview
        cleanupUsesCredits = preferences.object(forKey: "cleanupUsesCredits") as? Bool ?? preferences.bool(forKey: "creditsEnabled")
        promptModeEnabled = preferences.bool(forKey: "promptModeEnabled")
        promptShortcutKey = preferences.data(forKey: "promptShortcutKey").flatMap { try? JSONDecoder().decode(ShortcutKey.self, from: $0) } ?? .rightCommand
        promptHoldEnabled = preferences.object(forKey: "promptHoldEnabled") as? Bool ?? true
        promptTapEnabled = preferences.object(forKey: "promptTapEnabled") as? Bool ?? true
        let savedRouterOptions = preferences.data(forKey: "routerModelOptions")
        var initialRouterOptions = savedRouterOptions.flatMap { try? JSONDecoder().decode([String: OpenRouterOptions].self, from: $0) } ?? [:]
        if preferences.object(forKey: "fallbackModel") == nil,
           savedRouterOptions == nil {
            initialRouterOptions["cleanup:" + ProcessingProvider.defaultOpenRouterModel] = .init(reasoning: .low)
        }
        routerModelOptions = initialRouterOptions
        codexModelOptions = preferences.data(forKey: "codexModelOptions").flatMap { try? JSONDecoder().decode([String: CodexOptions].self, from: $0) } ?? [:]
        codexExecutable = preferences.string(forKey: "codexExecutable") ?? ""
        promptLanguage = preferences.string(forKey: "promptLanguage") ?? "en-US"
        clipboardContextEnabled = preferences.object(forKey: "clipboardContextEnabled") as? Bool ?? false
        localProcessingURL = preferences.string(forKey: "localProcessingURL") ?? LocalEndpoint.defaultProcessingURL
        localTranscriptionURL = preferences.string(forKey: "localTranscriptionURL") ?? LocalEndpoint.defaultTranscriptionURL
        localTranscriptionModel = preferences.string(forKey: "localTranscriptionModel") ?? TranscriptionProvider.local.defaultModel
        transcriptionProvider = TranscriptionProvider(rawValue: preferences.string(forKey: "transcriptionProvider") ?? "") ?? .assemblyAI
        xaiTranscriptionModel = preferences.string(forKey: "xaiTranscriptionModel") ?? TranscriptionProvider.xai.defaultModel
        routerTranscriptionModel = preferences.string(forKey: "routerTranscriptionModel") ?? TranscriptionProvider.openRouter.defaultModel
        transcriptionMode = TranscriptionMode(rawValue: preferences.string(forKey: "transcriptionMode") ?? "") ?? .fast
        mode = WritingMode(rawValue: preferences.string(forKey: "writingMode") ?? "") ?? .clean
        jevRoute = JevRoute(rawValue: preferences.string(forKey: "jevRoute") ?? "") ?? .typeSafe
        jevCleanupMode = JevCleanupMode(rawValue: preferences.string(forKey: "jevCleanupMode") ?? "") ?? .off
        dictionaryCategorizationEnabled = preferences.bool(forKey: "dictionaryCategorizationEnabled")
        dictionaryLearningRoute = DictionaryLearningRoute(rawValue: preferences.string(forKey: "dictionaryLearningRoute") ?? "")
            ?? .typeSafe
        let provider = ProcessingProvider(rawValue: preferences.string(forKey: "processingProvider") ?? "") ?? .openRouter
        processingProvider = provider
        let savedModel = preferences.string(forKey: provider.modelPreferenceKey) ?? provider.defaultModel
        let misplacedEndpoint = provider == .openRouter && savedModel == "cerebras/fp16"
        processingModel = misplacedEndpoint ? ProcessingProvider.defaultOpenRouterModel : savedModel
        routerEndpoint = misplacedEndpoint ? "cerebras/fp16"
            : preferences.string(forKey: "routerEndpoint")
                ?? (preferences.object(forKey: "fallbackModel") == nil && savedModel == ProcessingProvider.defaultOpenRouterModel ? "cerebras/fp16" : "")
        if misplacedEndpoint {
            preferences.set(ProcessingProvider.defaultOpenRouterModel, forKey: "fallbackModel")
        }
        disabledInputPresets = Set(preferences.stringArray(forKey: "disabledInputPresets") ?? [])
        menuAppearance = preferences.string(forKey: "menuAppearance") ?? "system"
        classicAnchor = preferences.data(forKey: "liquidGlassPlacement.v1").flatMap { try? JSONDecoder().decode(GlassCapsuleAnchor.self, from: $0) }
        glowAppearance = GlowAppearance(rawValue: preferences.string(forKey: "glowAppearance") ?? "") ?? .bottom
        let savedBezelPosition = preferences.object(forKey: "bezelVerticalPosition") as? Double ?? 0.5
        bezelVerticalPosition = savedBezelPosition.isFinite ? min(1, max(0, savedBezelPosition)) : 0.5
        bezelSide = BezelSide(rawValue: preferences.string(forKey: "bezelSide") ?? "") ?? .right
        glowWidth = min(1, max(0.25, preferences.object(forKey: "glowWidth") as? Double ?? 1))
        let savedGlowMinimum = min(2, max(0, preferences.object(forKey: "glowMinimum") as? Double ?? 0.3))
        glowMinimum = savedGlowMinimum
        glowMaximum = min(5, max(savedGlowMinimum, preferences.object(forKey: "glowMaximum") as? Double ?? 2))
        glowStrength = preferences.object(forKey: "glowStrength") as? Double ?? 0.8
        glowTuning = (preferences.data(forKey: "glowTuning").flatMap { try? JSONDecoder().decode(GlowTuning.self, from: $0) } ?? .init()).normalized
        microphoneUID = preferences.string(forKey: "microphoneUID") ?? ""
        shortcutKey = preferences.data(forKey: "shortcutKey").flatMap { try? JSONDecoder().decode(ShortcutKey.self, from: $0) } ?? .function
        holdEnabled = preferences.object(forKey: "holdEnabled") as? Bool ?? true
        tapEnabled = preferences.object(forKey: "tapEnabled") as? Bool ?? true
        if classicAnchor == nil, glowAppearance == .bezel, let screen = NSScreen.screens.first {
            let placement = BezelGeometry.frame(screen: screen.frame, side: bezelSide, verticalPosition: bezelVerticalPosition)
            let anchor = GlassCapsuleAnchor(center: CGPoint(x: placement.midX, y: placement.midY),
                visibleFrame: screen.visibleFrame, displayID: GlassCapsulePlacementStore.identifier(for: screen), side: bezelSide)
            classicAnchor = anchor
            if let data = try? JSONEncoder().encode(anchor) { preferences.set(data, forKey: "liquidGlassPlacement.v1") }
        }
        preferences.set(transcriptionProvider.rawValue, forKey: "transcriptionProvider")
        self.clipboardMonitor.onChange = { [weak self] in self?.objectWillChange.send() }
        if !preview {
            if clipboardContextEnabled { self.clipboardMonitor.start() }
            if processingProvider == nil { page = .connections }
            loadSavedKeys()
            let reasoningModels = Set([processingModel, creditCleanupModel])
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for model in reasoningModels { group.addTask { await OpenRouterReasoningCatalog.shared.refresh(model: model) } }
                }
            }
            Task { await refreshRecoveredRecordings() }
            audioChangeObserver = NotificationCenter.default.addObserver(forName: Microphone.configurationChanged, object: microphone, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.phase == .monitoring { self.cancel(); self.notice = "The microphone changed. Start the test again."; return }
                    guard self.phase == .recording else { return }
                    self.stopRecording()
                    self.notice = "The microphone changed. Processing the audio recorded so far."
                }
            }
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in _ = await self?.preserveForInterruption() }
            }
        }
    }

    @Published var savedKeysLocked = false

    var transcriptionKey: String { keyValue(transcriptionProvider.rawValue) }
    var transcriptionModel: String {
        switch transcriptionProvider {
        case .xai: return xaiTranscriptionModel
        case .local: return localTranscriptionModel
        case .assemblyAI: return transcriptionProvider.defaultModel
        case .openRouter: return routerTranscriptionModel
        }
    }

    func reserveWritingPromptDictation() throws {
        guard !meetingRecordingActive, !writingPromptDictationActive, !phase.busy, phase != .recording else {
            throw ServiceError.message("Finish the current dictation before recording an editing request.")
        }
        guard !needsInstallation else { throw ServiceError.message(setupSummary) }
        writingPromptDictationActive = true
    }

    func releaseWritingPromptDictation() {
        writingPromptDictationActive = false
    }

    func transcribeWritingPrompt(_ audio: Data) async throws -> String {
        let connection = speechUsesCredits ? creditConnection : nil
        let provider = connection == nil ? transcriptionProvider : creditSpeechProvider
        let key = connection?.key ?? transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = connection == nil ? transcriptionModel : creditTranscriptionModel
        let mode = connection == nil ? transcriptionMode : .fast
        var localURL = localTranscriptionURL

        if speechUsesCredits, connection == nil {
            throw ServiceError.message("Add your S2T key under API keys before dictating an editing request.")
        }
        if provider != .local && connection == nil && key.isEmpty {
            throw ServiceError.message("Add the key for your selected speech provider before dictating an editing request.")
        }
        if provider == .local, localURL == LocalModels.managedEndpoint, !model.hasPrefix("apple-speech-") {
            localURL = try await localModels.url(for: model, path: "/audio/transcriptions")
        }

        let transcription: TimedTranscription
        if let connection {
            guard mode == .fast else { throw ServiceError.message("S2T credits support Fast recognition. Select Fast under Models.") }
            transcription = try await creditsAPI.transcribe(audio: audio, provider: provider, model: model,
                endpoint: nil, connection: connection, requestID: UUID().uuidString + "-writing")
            Task { await refreshCredits() }
        } else if provider == .local, localURL == LocalModels.managedEndpoint, model.hasPrefix("apple-speech-") {
            guard #available(macOS 26, *) else { throw ServiceError.message("Apple Speech requires macOS 26 or newer.") }
            transcription = try await NativeSpeechModels.transcribe(audio: audio, modelID: model)
        } else {
            transcription = try await api.transcribeDetailed(audio: audio, apiKey: key, mode: mode,
                provider: provider, model: model, localURL: localURL)
        }
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Check your microphone and try again.") }
        recordKeySuccess(account: connection == nil ? provider.rawValue : "s2t", using: key)
        return text
    }
    var selectedLocalRuntimeIsRepairing: Bool {
        guard localModels.isRepairing else { return false }
        let speech = !speechUsesCredits && transcriptionProvider == .local &&
            localTranscriptionURL == LocalModels.managedEndpoint && !localTranscriptionModel.hasPrefix("apple-speech-")
        let cleanup = mode != .verbatim && !cleanupUsesCredits && processingProvider == .local &&
            localProcessingURL == LocalModels.managedEndpoint
        return speech || cleanup
    }

    var canRecord: Bool {
        guard !selectedLocalRuntimeIsRepairing else { return false }
        guard !isPreservingRecording else { return false }
        let speechReady: Bool
        if speechUsesCredits {
            speechReady = creditConnection != nil
        } else {
            speechReady = transcriptionProvider == .local
                ? (try? LocalEndpoint.url(localTranscriptionURL)) != nil && TranscriptionProvider.local.validModelID(localTranscriptionModel)
                : !transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard speechReady else { return false }
        if mode == .verbatim { return true }
        if cleanupUsesCredits { return creditConnection != nil }
        guard let provider = processingProvider else { return false }
        switch provider {
        case .local: return (try? LocalEndpoint.url(localProcessingURL)) != nil && provider.validModelID(processingModel)
        case .codex: return provider.validModelID(processingModel)
        case .openRouter, .xai: return !processingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var displayText: String { showOriginal ? rawTranscript : output }
    var timeLabel: String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    var wordCount: Int { output.split(whereSeparator: \.isWhitespace).count }
    var glowLevel: Double {
        if phase == .preview {
            let t = ProcessInfo.processInfo.systemUptime - previewStartedAt
            return max(0, min(1, 0.35 + sin(t * 4.5) * 0.4 + sin(t * 11) * 0.2))
        }
        return microphone.meter
    }

    var speechSpectrum: [Double] {
        if phase == .preview {
            let t = ProcessInfo.processInfo.systemUptime - previewStartedAt
            return (0..<AudioSpectrum.bandCount).map { index in
                let band = Double(index)
                let phrase = max(0, sin(t * 2.4 - band * 0.38))
                return min(1, phrase * (0.35 + 0.55 * abs(sin(t * (3.1 + band * 0.43) + band))))
            }
        }
        return microphone.spectrum
    }

    func handleActivation(_ action: ActivationAction, prompt: Bool = false) {
        if (phase == .recording || phase == .preparing), sessionIsPrompt != prompt { return }
        switch action {
        case .none: break
        case .start: if phase != .recording && !phase.busy { toggleRecording(prompt: prompt) }
        case .stop:
            if phase == .preparing { cancel() }
            else if phase == .recording { stopRecording() }
        case .toggle: toggleRecording(prompt: prompt)
        case .cancel: if phase == .preparing || phase == .recording { cancel() }
        }
    }

    func toggleRecording(prompt: Bool = false) {
        guard !meetingRecordingActive else { notice = "Stop the meeting before starting dictation."; return }
        guard !writingPromptDictationActive else {
            notice = "Finish the editing request dictation first."
            return
        }
        if phase == .recording { if !prompt || sessionIsPrompt { stopRecording() }; return }
        guard !phase.busy else { return }
        stopShortcutTest?()
        guard !needsInstallation else { notice = setupSummary; return }
        guard !isPreservingRecording else { notice = "Saving your previous recording. Try again when it has finished."; return }
        guard !selectedLocalRuntimeIsRepairing else { notice = "The selected local model is being repaired. Wait for repair to finish or choose another provider."; return }
        guard canRecord else { page = .connections; notice = "Add the key for your selected provider under API keys, or configure its local endpoint under Models."; return }
        if prompt, let blocker = promptStartBlocker {
            notice = blocker
            promptStatus = blocker
            return
        }
        startRecording(prompt: prompt)
    }

    /// Why a Prompt mode recording cannot start, or nil when it can.
    var promptStartBlocker: String? {
        guard promptModeEnabled else { return "Enable Prompt mode in Settings → Dictation first." }
        guard PromptSpeechListener.permissionGranted else { return "Prompt mode needs Speech Recognition. Allow it under Settings → Dictation → Prompt mode." }
        guard PromptScreenshot.permissionGranted else { return "Prompt mode needs Screen Recording. Allow S2T in System Settings → Privacy & Security → Screen & System Audio Recording, then reopen S2T." }
        return nil
    }


    lazy var localModels = LocalModels(preview: isPreview)

    func clearClipboardHistory() {
        recentRecordings.clearClipboardContent(clipboardMonitor.snapshot().entries.map(\.text))
        clipboardMonitor.clear()
    }

    func copyResult() { copyText(displayText) }

    func copyText(_ text: String) {
        guard !text.isEmpty else { return }
        copied = TextInsertion.copy(text, to: outputPasteboard)
        guard copied else { notice = "Couldn't copy the text. Use Copy to try again."; return }
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            copied = false
        }
    }

    func previewGlow() {
        guard !phase.busy, phase != .recording else { return }
        hideTask?.cancel()
        if phase == .monitoring { work?.cancel(); microphone.cancel() }
        phase = .preview
        previewStartedAt = ProcessInfo.processInfo.systemUptime
        overlayVisible = true
    }

    func testMicrophone() {
        guard !meetingRecordingActive else { notice = "Stop the meeting before testing the microphone."; return }
        guard !needsInstallation else { notice = setupSummary; return }
        stopShortcutTest?()
        if phase == .monitoring { cancel(); return }
        guard !phase.busy, phase != .recording else { return }
        cancel()
        phase = .preparing
        errorMessage = nil
        work = Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard allowed else { fail(ServiceError.message("Allow microphone access in macOS Privacy & Security settings to test this input.")); return }
            do {
                try await microphone.start(deviceUID: microphoneUID, captureAudio: false)
                guard !Task.isCancelled else { return }
                phase = .monitoring
                overlayVisible = true
                try await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                cancel()
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func fail(_ error: Error) {
        promptRegionCapture.stop()
        promptCaptureFeedback.hide()
        insertionTarget?.stopTracking()
        phase = .failed
        if recovery != nil {
            let location = recoveryIsSaved && recoveryStore != nil ? "Your recording is saved on this Mac." : "Your recording is still in memory. Save it before quitting."
            errorMessage = error.localizedDescription + "\n" + location + " Use Retry recording or Save recording."
        } else { errorMessage = error.localizedDescription }
        hideOverlay(after: 2)
    }

    func hideOverlay(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }
}
