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
}

@MainActor final class AppState: ObservableObject {
    @Published var promptModeEnabled: Bool { didSet { preferences.set(promptModeEnabled, forKey: "promptModeEnabled"); shortcutSettingsChanged?() } }
    @Published var promptShortcutKey: ShortcutKey { didSet { preferences.set(try? JSONEncoder().encode(promptShortcutKey), forKey: "promptShortcutKey"); shortcutSettingsChanged?() } }
    @Published var promptHoldEnabled: Bool { didSet { preferences.set(promptHoldEnabled, forKey: "promptHoldEnabled"); shortcutSettingsChanged?() } }
    @Published var promptTapEnabled: Bool { didSet { preferences.set(promptTapEnabled, forKey: "promptTapEnabled"); shortcutSettingsChanged?() } }
    var beginPromptShortcutCapture: (() -> Void)?
    private(set) var sessionIsPrompt = false
    var promptShortcutConflict: Bool { promptShortcutKey.matchesBinding(shortcutKey) }
    func saveShortcut(_ key: ShortcutKey, prompt: Bool) {
        guard !key.matchesBinding(prompt ? shortcutKey : promptShortcutKey) else {
            notice = "Choose different shortcuts for dictation and Prompt mode. That key is already assigned."; return
        }
        if prompt { promptShortcutKey = key } else { shortcutKey = key }
    }
    @Published var promptVisionProvider: VisionProvider {
        didSet {
            preferences.set(promptVisionProvider.rawValue, forKey: "promptVisionProvider")
            promptVisionModel = preferences.string(forKey: promptVisionProvider.modelPreferenceKey) ?? promptVisionProvider.defaultModel
        }
    }
    @Published var promptVisionModel: String { didSet { preferences.set(promptVisionModel, forKey: promptVisionProvider.modelPreferenceKey) } }
    @Published var localVisionURL: String { didSet { preferences.set(localVisionURL, forKey: "localVisionURL") } }
    @Published var codexModelOptions: [String: CodexOptions] {
        didSet { preferences.set(try? JSONEncoder().encode(codexModelOptions), forKey: "codexModelOptions") }
    }
    func codexOptions(model: String, vision: Bool) -> CodexOptions {
        codexModelOptions[(vision ? "vision:" : "cleanup:") + model] ?? CodexOptions()
    }
    func setCodexOptions(_ options: CodexOptions, model: String, vision: Bool) {
        guard options.isValid else { return }
        codexModelOptions[(vision ? "vision:" : "cleanup:") + model] = options
    }
    @Published var codexExecutable: String { didSet { preferences.set(codexExecutable, forKey: "codexExecutable") } }
    func validatePromptVisionModel(_ value: String) async -> String? {
        do {
            try await api.validatePromptVisionModel(value.trimmingCharacters(in: .whitespacesAndNewlines), provider: promptVisionProvider, localURL: localVisionURL)
            return nil
        } catch { return error.localizedDescription }
    }
    @Published var promptLanguage: String { didSet { preferences.set(promptLanguage, forKey: "promptLanguage") } }
    @Published var promptStatus = "Experimental beta · Off by default"
    @Published var promptImages: [URL] = []
    private let promptListener = PromptSpeechListener()
    private var promptSession: PromptModeSession?

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
    @Published var elapsed: TimeInterval = 0
    @Published var rawTranscript = ""
    @Published var output = ""
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var modelUsed = ""
    @Published var processingFailureModel: String?
    @Published var routeDescription = "Selected model"
    @Published var elevenLabsKey = "" { didSet { keyEdited("elevenlabs") } }
    @Published var transcriptionProvider: TranscriptionProvider { didSet { preferences.set(transcriptionProvider.rawValue, forKey: "transcriptionProvider") } }
    @Published var elevenLabsModel: String { didSet { preferences.set(elevenLabsModel, forKey: "elevenLabsTranscriptionModel") } }
    @Published var routerTranscriptionModel: String { didSet { preferences.set(routerTranscriptionModel, forKey: "routerTranscriptionModel") } }
    @Published var assemblyKey = "" { didSet { keyEdited("assemblyai") } }
    @Published var routerKey = "" { didSet { keyEdited("openrouter") } }
    @Published var cerebrasKey = "" { didSet { keyEdited("cerebras") } }
    @Published private(set) var keyStatuses: [String: APIKeyStatus] = [:]
    private var keyChecks: [String: Task<Void, Never>] = [:]
    private var keyRevisions: [String: UUID] = [:]
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
        let accounts = [transcriptionProvider.rawValue] + (mode == .verbatim ? [] : processingProvider.map { [$0.rawValue] } ?? [])
        return canRecord && accounts.filter { $0 != "local" && $0 != "codex" }.allSatisfy { savedKeyAccounts.contains($0) && keyStatuses[$0]?.needsAttention != true && keyStatuses[$0] != .checking }
    }
    var setupSummary: String {
        if needsInstallation { return "Drag S2T into Applications, then open that copy before granting access." }
        if !dictationPermissionsReady { return "Allow the two permissions below. S2T checks again when you return." }
        if !setupKeysReady { return "Configure your provider keys, local endpoints or Codex below. Verbatim needs only speech recognition." }
        if !shortcutAvailable && (holdEnabled || tapEnabled) { return shortcutStatus }
        if !holdEnabled && !tapEnabled { return "Shortcut behaviors are off. Use Start dictation in the main menu, then Finish dictation." }
        if !holdEnabled { return "Close this menu and click a text field. Tap \(shortcutKey.displayName) to start, then tap again to finish." }
        return "Click a text field, then hold \(shortcutKey.displayName) and speak. Release to finish. Close this menu first."
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
    @Published private(set) var savedKeyAccounts: Set<String> = []
    @Published var mode: WritingMode { didSet { preferences.set(mode.rawValue, forKey: "writingMode") } }
    @Published var processingModel: String { didSet { guard let processingProvider else { return }; preferences.set(processingModel, forKey: processingProvider.modelPreferenceKey) } }
    @Published var localProcessingURL: String { didSet { preferences.set(localProcessingURL, forKey: "localProcessingURL") } }
    @Published var localTranscriptionURL: String { didSet { preferences.set(localTranscriptionURL, forKey: "localTranscriptionURL") } }
    @Published var localTranscriptionModel: String { didSet { preferences.set(localTranscriptionModel, forKey: "localTranscriptionModel") } }
    @Published var routerEndpoint: String { didSet { preferences.set(routerEndpoint, forKey: "routerEndpoint") } }
    var processingSelectionLabel: String {
        guard let processingProvider else { return "Choose a text processing provider." }
        let host = processingProvider == .openRouter && !routerEndpoint.isEmpty ? " · Host: " + routerEndpoint : ""
        return "Model: " + processingModel + host
    }
    static var systemPromptFile: SystemPromptFile {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return SystemPromptFile(url: directory.appendingPathComponent("S2T/system-prompt.txt"))
    }
    static var dictionaryFile: DictionaryFile {
        DictionaryFile(url: systemPromptFile.url.deletingLastPathComponent().appendingPathComponent("dictionary.md"))
    }
    private let dictionaryLearner = DictionaryLearner()
    func revealDictionaryInFinder() {
        do {
            _ = try Self.dictionaryFile.read()
            NSWorkspace.shared.activateFileViewerSelecting([Self.dictionaryFile.url])
        } catch { errorMessage = "Could not reveal dictionary in Finder. " + error.localizedDescription }
    }
    func openSystemPromptInFinder() {
        do {
            try Self.systemPromptFile.ensureExists()
            NSWorkspace.shared.activateFileViewerSelecting([Self.systemPromptFile.url])
        } catch { errorMessage = "Could not open the system prompt file. " + error.localizedDescription }
    }
    func saveProcessingModel(_ value: String, for provider: ProcessingProvider) -> String? {
        guard processingProvider == provider else { return "Provider changed. Reopen Models before saving." }
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .openRouter && model == "cerebras/fp16" { return "This is a hosting endpoint. Use the Cerebras preset under Models." }
        guard provider.validModelID(model) else { return "Enter a valid \(provider.title) model ID." }
        processingModel = model
        return nil
    }
    func useCerebrasThroughOpenRouter() {
        processingProvider = .openRouter
        processingModel = ProcessingProvider.cerebrasOpenRouterModel
        routerEndpoint = "cerebras/fp16"
    }
    var processingEndpoint: String? { processingProvider == .openRouter ? routerEndpoint : nil }
    @Published var menuAppearance: String { didSet { preferences.set(menuAppearance, forKey: "menuAppearance") } }
    @Published var inputOutlineNotice: String?
    @Published var disabledInputPresets: Set<String> {
        didSet { preferences.set(disabledInputPresets.sorted(), forKey: "disabledInputPresets") }
    }
    @Published var glowAppearance: GlowAppearance { didSet { preferences.set(glowAppearance.rawValue, forKey: "glowAppearance") } }
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

    private let focusHistory: AppFocusHistory
    private let preferences: UserDefaults
    private let api: DictationAPI
    private let microphone = Microphone()
    private var work: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var meterTimer: Timer?
    private var startedAt = Date()
    private var previewStartedAt: Double = 0
    private var recording: Data?
    private var startTargetTask: Task<TextInsertion.Target?, Never>?
    @Published var pasteAtStart: Bool { didSet { preferences.set(pasteAtStart, forKey: "pasteAtStart") } }
    private var insertionTarget: TextInsertion.Target?
    private var sessionMode: WritingMode = .clean
    private var sessionProvider: ProcessingProvider?
    private var audioChangeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    let isPreview: Bool
    private let outputPasteboard: NSPasteboard
    private let insertText: (String, TextInsertion.Target?) async throws -> TextInsertion.Outcome
    private let insertPromptImages: ([URL], pid_t?, NSPasteboard) async throws -> PromptImageInsertion.Result
    private let promptStorageDirectory: URL

    init(preview: Bool = false, api: DictationAPI = DictationAPI(), clipboardMonitor: ClipboardMonitor? = nil, outputPasteboard: NSPasteboard? = nil, promptSession: PromptModeSession? = nil, insertPromptImages: (([URL], pid_t?, NSPasteboard) async throws -> PromptImageInsertion.Result)? = nil, insertText: @escaping (String, TextInsertion.Target?) async throws -> TextInsertion.Outcome = { try await TextInsertion.insert($0, into: $1) }) {
        self.insertText = insertText
        self.insertPromptImages = insertPromptImages ?? { images, recipient, board in
            guard !preview else { return .init(sentCount: 0, issue: "Image insertion is disabled in preview.", clipboardChange: board.changeCount) }
            return try await PromptImageInsertion.insert(images, recipient: recipient, board: board)
        }
        self.promptSession = preview ? promptSession : nil
        promptStorageDirectory = preview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("s2t-prompt-preview-" + UUID().uuidString)
            : Self.systemPromptFile.url.deletingLastPathComponent().appendingPathComponent("Prompt references")
        self.outputPasteboard = outputPasteboard ?? (preview ? NSPasteboard(name: NSPasteboard.Name("com.s2t.preview.output.\(UUID().uuidString)")) : .general)
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitor(persistence: preview ? nil : ClipboardStorage.makeStore())
        self.isPreview = preview
        focusHistory = AppFocusHistory(observe: !preview)
        self.api = api
        preferences = preview ? UserDefaults(suiteName: "com.s2t.preview")! : .standard
        if !preview, !preferences.bool(forKey: "legacyPreferencesImported") {
            if let previous = UserDefaults(suiteName: "com.sotto.dictation") {
                for key in ["writingMode", "fallbackModel", "autoCopy", "pasteToApp", "glowStrength"] where preferences.object(forKey: key) == nil {
                    if let value = previous.object(forKey: key) { preferences.set(value, forKey: key) }
                }
            }
            preferences.set(true, forKey: "legacyPreferencesImported")
        }
        promptModeEnabled = preferences.bool(forKey: "promptModeEnabled")
        promptShortcutKey = preferences.data(forKey: "promptShortcutKey").flatMap { try? JSONDecoder().decode(ShortcutKey.self, from: $0) } ?? .rightCommand
        promptHoldEnabled = preferences.object(forKey: "promptHoldEnabled") as? Bool ?? true
        promptTapEnabled = preferences.object(forKey: "promptTapEnabled") as? Bool ?? true
        let visionProvider = VisionProvider(rawValue: preferences.string(forKey: "promptVisionProvider") ?? "") ?? .openRouter
        promptVisionProvider = visionProvider
        promptVisionModel = preferences.string(forKey: visionProvider.modelPreferenceKey) ?? visionProvider.defaultModel
        localVisionURL = preferences.string(forKey: "localVisionURL") ?? LocalEndpoint.defaultProcessingURL
        codexModelOptions = preferences.data(forKey: "codexModelOptions").flatMap { try? JSONDecoder().decode([String: CodexOptions].self, from: $0) } ?? [:]
        codexExecutable = preferences.string(forKey: "codexExecutable") ?? ""
        promptLanguage = preferences.string(forKey: "promptLanguage") ?? "en-US"
        pasteAtStart = preferences.bool(forKey: "pasteAtStart")
        clipboardContextEnabled = preferences.object(forKey: "clipboardContextEnabled") as? Bool ?? true
        localProcessingURL = preferences.string(forKey: "localProcessingURL") ?? LocalEndpoint.defaultProcessingURL
        localTranscriptionURL = preferences.string(forKey: "localTranscriptionURL") ?? LocalEndpoint.defaultTranscriptionURL
        localTranscriptionModel = preferences.string(forKey: "localTranscriptionModel") ?? TranscriptionProvider.local.defaultModel
        transcriptionProvider = TranscriptionProvider(rawValue: preferences.string(forKey: "transcriptionProvider") ?? "") ?? .assemblyAI
        elevenLabsModel = preferences.string(forKey: "elevenLabsTranscriptionModel") ?? TranscriptionProvider.elevenLabs.defaultModel
        routerTranscriptionModel = preferences.string(forKey: "routerTranscriptionModel") ?? TranscriptionProvider.openRouter.defaultModel
        transcriptionMode = TranscriptionMode(rawValue: preferences.string(forKey: "transcriptionMode") ?? "") ?? .fast
        mode = WritingMode(rawValue: preferences.string(forKey: "writingMode") ?? "") ?? .clean
        let provider = ProcessingProvider(rawValue: preferences.string(forKey: "processingProvider") ?? "") ?? .openRouter
        processingProvider = provider
        let savedModel = preferences.string(forKey: provider.modelPreferenceKey) ?? provider.defaultModel
        let misplacedEndpoint = provider == .openRouter && savedModel == "cerebras/fp16"
        processingModel = misplacedEndpoint ? ProcessingProvider.cerebrasOpenRouterModel : savedModel
        routerEndpoint = misplacedEndpoint ? "cerebras/fp16" : preferences.string(forKey: "routerEndpoint") ?? ProcessingProvider.openRouter.defaultEndpoint!
        if misplacedEndpoint {
            preferences.set(ProcessingProvider.cerebrasOpenRouterModel, forKey: "fallbackModel")
            preferences.set("cerebras/fp16", forKey: "routerEndpoint")
        }
        disabledInputPresets = Set(preferences.stringArray(forKey: "disabledInputPresets") ?? [])
        menuAppearance = preferences.string(forKey: "menuAppearance") ?? "system"
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
        self.clipboardMonitor.onChange = { [weak self] in self?.objectWillChange.send() }
        if !preview {
            if clipboardContextEnabled { self.clipboardMonitor.start() }
            if processingProvider == nil { page = .connections }
            loadSavedKeys()
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
                Task { @MainActor in self?.cancel() }
            }
        }
    }

    @Published private(set) var savedKeysLocked = false

    func loadSavedKeys(allowInteraction: Bool = false) {
        guard !isPreview else { return }
        savedKeysLocked = false
        for account in APIAccount.allCases {
            if !keyValue(account.rawValue).isEmpty && !savedKeyAccounts.contains(account.rawValue) { continue }
            do {
                let value = try Keychain.read(account.rawValue, allowInteraction: allowInteraction)
                guard !value.isEmpty else { continue }
                switch account {
                case .assemblyAI: assemblyKey = value
                case .openRouter: routerKey = value
                case .elevenLabs: elevenLabsKey = value
                case .cerebras: cerebrasKey = value
                }
                savedKeyAccounts.insert(account.rawValue)
                keyStatuses[account.rawValue] = nil
            } catch {
                savedKeysLocked = true
                keyStatuses[account.rawValue] = .issue("Saved key is locked. Choose Unlock saved keys under API keys. Existing keys are preserved.")
                if allowInteraction { break }
            }
        }
        if allowInteraction && !savedKeysLocked && clipboardMonitor.persistenceError != nil {
            do {
                _ = try Keychain.read("clipboard-history-encryption", allowInteraction: true)
                if clipboardContextEnabled { clipboardMonitor.poll() }
            } catch { savedKeysLocked = true }
        }
        credentialsSaved = !transcriptionKey.isEmpty
    }

    var processingKey: String {
        switch processingProvider {
        case .openRouter: return routerKey
        case .cerebras: return cerebrasKey
        case .local, .codex, nil: return ""
        }
    }
    var transcriptionKey: String { keyValue(transcriptionProvider.rawValue) }
    var transcriptionModel: String {
        switch transcriptionProvider {
        case .local: return localTranscriptionModel
        case .assemblyAI: return transcriptionProvider.defaultModel
        case .elevenLabs: return elevenLabsModel
        case .openRouter: return routerTranscriptionModel
        }
    }
    var canRecord: Bool {
        guard let provider = processingProvider else { return false }
        let speechReady = transcriptionProvider == .local
            ? (try? LocalEndpoint.url(localTranscriptionURL)) != nil && TranscriptionProvider.local.validModelID(localTranscriptionModel)
            : !transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cleanupReady: Bool
        switch provider {
        case .local: cleanupReady = (try? LocalEndpoint.url(localProcessingURL)) != nil && provider.validModelID(processingModel)
        case .codex: cleanupReady = provider.validModelID(processingModel)
        case .openRouter, .cerebras: cleanupReady = !processingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return speechReady && (mode == .verbatim || cleanupReady)
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

    private func keyEdited(_ account: String) {
        savedKeyAccounts.remove(account)
        keyChecks[account]?.cancel()
        keyChecks[account] = nil
        keyRevisions[account] = UUID()
        keyStatuses[account] = nil
    }

    func keyValue(_ account: String) -> String {
        switch account {
        case "elevenlabs": return elevenLabsKey
        case "assemblyai": return assemblyKey
        case "openrouter": return routerKey
        case "cerebras": return cerebrasKey
        default: return ""
        }
    }

    func saveAPIKey(account: String) {
        guard let provider = APIAccount(rawValue: account) else { return }
        let value = keyValue(account).trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .elevenLabs: elevenLabsKey = value
        case .assemblyAI: assemblyKey = value
        case .openRouter: routerKey = value
        case .cerebras: cerebrasKey = value
        }
        guard !value.isEmpty else {
            keyStatuses[account] = .issue("Paste your \(provider.title) API key, then save.")
            return
        }
        do {
            if !isPreview { try Keychain.save(value, account: account) }
            savedKeyAccounts.insert(account)
            credentialsSaved = !transcriptionKey.isEmpty
        } catch {
            keyStatuses[account] = .issue("Could not save in Keychain. \(error.localizedDescription)")
            return
        }
        let revision = UUID()
        keyRevisions[account] = revision
        keyStatuses[account] = .checking
        keyChecks[account] = Task { [weak self, api] in
            let status: APIKeyStatus
            do {
                try await api.validateKey(value, account: provider)
                status = .accepted
            } catch is CancellationError { return }
            catch {
                if case .account = error as? ServiceError {
                    status = .issue(error.localizedDescription)
                } else {
                    status = .issue("Couldn't check the key. Check your connection or try saving again.")
                }
            }
            guard !Task.isCancelled, let self, self.keyRevisions[account] == revision else { return }
            self.keyStatuses[account] = status
            self.keyChecks[account] = nil
        }
    }

    @discardableResult func recordKeyFailure(_ error: Error, using value: String) -> Bool {
        guard case .account(let account, _) = error as? ServiceError else { return false }
        guard keyValue(account.rawValue).trimmingCharacters(in: .whitespacesAndNewlines) == value else { return true }
        keyChecks[account.rawValue]?.cancel()
        keyRevisions[account.rawValue] = UUID()
        keyStatuses[account.rawValue] = .issue(error.localizedDescription)
        return true
    }

    func recordKeySuccess(account: String, using value: String) {
        guard keyValue(account).trimmingCharacters(in: .whitespacesAndNewlines) == value else { return }
        keyChecks[account]?.cancel()
        keyRevisions[account] = UUID()
        keyStatuses[account] = .accepted
    }

    func toggleRecording(prompt: Bool = false) {
        if phase == .recording { if !prompt || sessionIsPrompt { stopRecording() }; return }
        guard !phase.busy else { return }
        stopShortcutTest?()
        guard !needsInstallation else { notice = setupSummary; return }
        guard canRecord else { page = .connections; notice = "Configure the keys or local endpoint settings for your selected providers."; return }
        if prompt {
            guard promptModeEnabled else { notice = "Enable Prompt mode from its Experimental beta submenu first."; return }
            guard PromptSpeechListener.permissionGranted, PromptScreenshot.permissionGranted else {
                notice = "Set up Prompt mode permissions from its Experimental beta submenu first."; return
            }
            guard !routerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notice = "Prompt mode needs your OpenRouter key to describe screenshots."; return
            }
        }
        startRecording(prompt: prompt)
    }

    private func startRecording(prompt: Bool) {
        sessionIsPrompt = prompt
        promptListener.stop()
        promptSession?.cancel()
        promptSession = prompt && !isPreview ? PromptModeSession() : nil
        promptSession?.onStatus = { [weak self] in self?.promptStatus = $0 }
        dictionaryLearner.stop()
        microphone.cancel()
        hideTask?.cancel()
        work?.cancel()
        insertionTarget?.stopTracking()
        insertionTarget = TextInsertion.captureTarget(previousApp: focusHistory.previousApp)
        startTargetTask?.cancel()
        let capturedTarget = insertionTarget
        startTargetTask = pasteAtStart && !isPreview ? Task { await TextInsertion.rememberStart(capturedTarget) } : nil
        pasteHint = nil
        isWaitingToPaste = false
        sessionMode = mode
        sessionProvider = processingProvider
        phase = .preparing
        errorMessage = nil
        notice = nil
        copied = false
        elapsed = 0
        overlayVisible = true
        work = Task { [self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard allowed else {
                fail(ServiceError.message("Microphone access is off. Allow S2T in System Settings → Privacy & Security → Microphone."))
                return
            }
            do {
                if promptSession != nil {
                    try await promptSession?.startRecording()
                    try Task.checkCancellation()
                    try promptListener.start(microphone: microphone, locale: promptLanguage, onReference: { [weak self] phrase, seconds in
                        guard let self, self.phase == .recording else { return }
                        self.promptStatus = "Reference heard. Recording context for final matching…"
                    }, onFailure: { [weak self] in self?.promptSession?.recordWarning($0); self?.promptStatus = $0; self?.notice = $0 })
                }
                try await microphone.start(deviceUID: microphoneUID, liveSpeech: promptSession != nil)
                guard !Task.isCancelled else { return }
                startedAt = Date()
                phase = .recording
                if promptSession != nil { promptStatus = "Recording visual context · Experimental beta" }
                connectionTask?.cancel()
                if transcriptionProvider == .assemblyAI && transcriptionMode == .fast { connectionTask = Task { await api.warmTranscriptionConnection() } }
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.elapsed = Date().timeIntervalSince(self.startedAt)
                        if self.elapsed >= 600 { self.stopRecording() }
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                meterTimer = timer
            } catch {
                guard !Task.isCancelled else { return }
                promptListener.stop(); promptSession?.cancel(); fail(error)
            }
        }
    }

    private func stopRecording() {
        guard phase == .recording else { return }
        if let promptSession {
            promptSession.stopListening()
        } else { promptListener.stop() }
        meterTimer?.invalidate(); meterTimer = nil
        elapsed = Date().timeIntervalSince(startedAt)
        phase = .transcribing
        work = Task {
            guard !Task.isCancelled else { return }
            let captured = await microphone.finish()
            guard !Task.isCancelled else { return }
            promptSession?.setAudioOrigin(microphone.audioStartTime)
            promptSession?.stopListening(words: Task { await promptListener.finish() })
            guard elapsed >= 0.3, captured.count > 44 else {
                promptSession?.cancel()
                startTargetTask?.cancel()
                insertionTarget?.stopTracking()
                phase = .idle
                overlayVisible = false
                return
            }
            processRecording(captured)
        }
    }

    func processRecording(_ captured: Data) {
        guard processingProvider != nil else { page = .connections; notice = "Choose a text cleanup provider first."; return }
        sessionMode = mode
        sessionProvider = processingProvider
        recording = captured
        promptImages = []
        rawTranscript = ""
        output = ""
        modelUsed = ""
        showOriginal = false
        runPipeline()
    }

    func retry() {
        guard !phase.busy, recording != nil || !rawTranscript.isEmpty else { return }
        guard processingProvider != nil else { page = .connections; notice = "Choose a text cleanup provider first."; return }
        sessionMode = mode
        sessionProvider = processingProvider
        runPipeline()
    }

    var canRetry: Bool { phase == .failed && (recording != nil || !rawTranscript.isEmpty) }

    private func runPipeline() {
        work?.cancel()
        hideTask?.cancel()
        errorMessage = nil
        notice = nil
        overlayVisible = true
        processingFailureModel = nil
        let clipboardHistory = clipboardContextEnabled ? clipboardMonitor.snapshot() : ClipboardHistory()
        let speechProvider = transcriptionProvider
        let speechKey = transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechModel = transcriptionModel
        let speechMode = transcriptionMode
        let speechURL = localTranscriptionURL
        let cleanupURL = localProcessingURL
        guard let provider = sessionProvider else { return }
        let processingAPIKey = (provider.requiresAPIKey ? (provider == .openRouter ? routerKey : cerebrasKey) : "").trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedMode = sessionMode
        let model = processingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = processingEndpoint
        let visualSession = promptSession
        let visionModel = promptVisionModel
        let visionProvider = promptVisionProvider
        let visionURL = localVisionURL
        let codexPath = codexExecutable
        let cleanupOptions = codexOptions(model: model, vision: false)
        let visionOptions = codexOptions(model: promptVisionModel, vision: true)
        let visionKey = visionProvider == .openRouter ? routerKey.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let trackedTarget = insertionTarget
        phase = rawTranscript.isEmpty ? .transcribing : .processing
        work = Task {
            defer { trackedTarget?.stopTracking() }
            do {
                if rawTranscript.isEmpty, let recording {
                    let transcriptionStarted = ProcessInfo.processInfo.systemUptime
                    let transcription = try await api.transcribeDetailed(audio: recording, apiKey: speechKey, mode: speechMode, provider: speechProvider, model: speechModel, localURL: speechURL, includeTimestamps: visualSession != nil)
                    try Task.checkCancellation()
                    preferences.set(ProcessInfo.processInfo.systemUptime - transcriptionStarted, forKey: "lastTranscriptionSeconds")
                    recordKeySuccess(account: speechProvider.rawValue, using: speechKey)
                    rawTranscript = transcription.text
                    output = transcription.text
                    visualSession?.setTranscriptionWords(transcription.words)
                }
                let visualWork: Task<PromptModeSession.Result, Error>? = visualSession.map { session in
                    let transcript = rawTranscript
                    let directory = promptStorageDirectory.appendingPathComponent(session.id)
                    return Task {
                        let started = ProcessInfo.processInfo.systemUptime
                        let result = try await session.describe(transcript: transcript, api: api, key: visionKey, model: visionModel, directory: directory, provider: visionProvider, localURL: visionURL, codexExecutable: codexPath, codexOptions: visionOptions, onVisionError: { [weak self] error in self?.recordKeyFailure(error, using: visionKey) ?? false })
                        try Task.checkCancellation()
                        preferences.set(ProcessInfo.processInfo.systemUptime - started, forKey: "lastPromptAnalysisSeconds")
                        return result
                    }
                }
                defer { visualWork?.cancel() }
                if selectedMode != .verbatim {
                    phase = .processing
                    do {
                        guard !provider.requiresAPIKey || !processingAPIKey.isEmpty else { throw ServiceError.message("Add your \(provider.title) API key in Settings, then retry processing.") }
                        routeDescription = "Selected model"
                        let processingStarted = ProcessInfo.processInfo.systemUptime
                        let context = clipboardContextEnabled ? clipboardHistory.context(for: rawTranscript) : ClipboardContext()
                        let processed = try await api.process(text: rawTranscript, mode: selectedMode, model: model, apiKey: processingAPIKey, provider: provider, endpoint: endpoint, clipboardContext: context, systemPrompt: isPreview ? nil : try Self.systemPromptFile.read() + Self.dictionaryFile.prompt(), localURL: cleanupURL, codexExecutable: codexPath, codexOptions: cleanupOptions)
                        try Task.checkCancellation()
                        preferences.set(ProcessInfo.processInfo.systemUptime - processingStarted, forKey: "lastProcessingSeconds")
                        recordKeySuccess(account: provider.rawValue, using: processingAPIKey)
                        output = processed.text
                        modelUsed = processed.model + (processed.host.map { " · " + $0 } ?? "")
                    } catch {
                        try Task.checkCancellation()
                        processingFailureModel = model
                        output = rawTranscript
                        modelUsed = speechProvider.title
                        routeDescription = "Original transcription"
                        if !recordKeyFailure(error, using: processingAPIKey) {
                            errorMessage = "\(provider.title) processing failed. Using your original words. \(error.localizedDescription)"
                        }
                    }
                } else {
                    output = rawTranscript
                    modelUsed = speechProvider.title
                    routeDescription = "Original transcription"
                }
                try Task.checkCancellation()
                if let visualSession, let visualWork {
                    phase = .processing
                    promptStatus = "Describing visual references…"
                    let visual = try await withTaskCancellationHandler { try await visualWork.value } onCancel: { visualWork.cancel() }
                    try Task.checkCancellation()
                    promptImages = visual.images
                    output = PromptReferenceText.append(to: output, session: visualSession.id, references: visual.references)
                    promptStatus = visual.images.isEmpty ? "No reference screenshots available." : "\(visual.images.count) screenshots ready to paste with this prompt."
                    if !visual.warnings.isEmpty { errorMessage = ([errorMessage].compactMap { $0 } + visual.warnings).joined(separator: "\n") }
                    if !visual.images.isEmpty { notice = promptStatus }
                }
                try Task.checkCancellation()
                if TextInsertion.menuIsOpen {
                    isWaitingToPaste = true
                    phase = .complete
                    notice = "Close the menu to insert dictation at your cursor."
                    hideOverlay(after: 0.35)
                }
                if let startTargetTask { insertionTarget = await startTargetTask.value }
                try Task.checkCancellation()
                let outcome: TextInsertion.Outcome = startTargetTask != nil && insertionTarget == nil ? .noTarget : try await insertText(output, insertionTarget ?? (isPreview ? nil : TextInsertion.captureTarget(previousApp: focusHistory.previousApp)))
                try Task.checkCancellation()
                let imageRecipient = isPreview ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier
                isWaitingToPaste = false
                preferences.set(outcome.rawValue, forKey: "lastInsertionOutcome")
                preferences.set(Date(), forKey: "lastDeliveryAt")
                copied = false
                if outcome == .textSent {
                    if visualSession != nil, !promptImages.isEmpty {
                        phase = .processing
                        promptStatus = "Pasting reference screenshots…"
                        let attachmentStarted = ProcessInfo.processInfo.systemUptime
                        let attachment = try await insertPromptImages(promptImages, imageRecipient, outputPasteboard)
                        preferences.set(ProcessInfo.processInfo.systemUptime - attachmentStarted, forKey: "lastPromptAttachmentSeconds")
                        try Task.checkCancellation()
                        promptStatus = attachment.issue ?? "Sent \(attachment.sentCount) screenshots for attachment. If they don't appear, use Reference images."
                        notice = promptStatus
                        if outputPasteboard.changeCount == attachment.clipboardChange { copyText(output) }
                    } else {
                        copyText(output)
                    }
                    if !isPreview {
                        dictionaryLearner.start(output: output, file: Self.dictionaryFile) { [weak self] error in
                            self?.errorMessage = error
                        }
                    }
                }
                pasteHint = outcome.hint
                if notice == "Close the menu to insert dictation at your cursor." { notice = nil }
                if let hint = outcome.hint { notice = hint }
                try Task.checkCancellation()
                phase = .complete
                if glowAppearance == .bezel { overlayVisible = true }
                hideOverlay(after: pasteHint == nil ? (glowAppearance == .bezel ? 0.85 : 0.35) : 5)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                if recordKeyFailure(error, using: speechKey) {
                    phase = .failed
                    hideOverlay(after: 2)
                } else {
                    fail(error)
                }
            }
        }
    }

    var canCancel: Bool {
        isWaitingToPaste || phase.busy || [.recording, .preview, .monitoring, .preparing].contains(phase)
    }

    func cancel() {
        promptListener.stop()
        promptSession?.cancel()
        promptSession = nil
        dictionaryLearner.stop()
        isWaitingToPaste = false
        startTargetTask?.cancel(); startTargetTask = nil
        insertionTarget?.stopTracking(); insertionTarget = nil
        work?.cancel(); hideTask?.cancel(); connectionTask?.cancel()
        meterTimer?.invalidate(); meterTimer = nil
        microphone.cancel()
        phase = .idle
        overlayVisible = false
    }

    func clearClipboardHistory() {
        clipboardMonitor.clear()
    }

    func copyResult() { copyText(displayText) }

    private func copyText(_ text: String) {
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

    private func fail(_ error: Error) {
        startTargetTask?.cancel()
        insertionTarget?.stopTracking()
        phase = .failed
        errorMessage = error.localizedDescription
        hideOverlay(after: 2)
    }

    private func hideOverlay(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }
}
