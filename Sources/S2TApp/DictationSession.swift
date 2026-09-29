import Foundation
import S2TCore

@MainActor struct DictationConfiguration {
    let microphoneUID: String
    let earlyTranscriptionEnabled: Bool
    let mode: WritingMode
    let savedCreditConnection: CreditConnection?
    let speechConnection: CreditConnection?
    let speechProvider: TranscriptionProvider
    let speechKey: String
    let speechModel: String
    let speechMode: TranscriptionMode
    let speechURL: String
    let cleanupConnection: CreditConnection?
    let cleanupProvider: ProcessingProvider
    let cleanupKey: String
    let cleanupModel: String
    let cleanupEndpoint: String?
    let cleanupURL: String
    let cleanupRouterOptions: OpenRouterOptions
    let cleanupOptions: CodexOptions
    let codexPath: String
    let jevMode: JevCleanupMode
    let jevRoute: JevRoute
    let jevConnection: CreditConnection?
    let jevKey: String
    let clipboardEnabled: Bool
    let clipboard: ClipboardHistory
    let editingPreferences: Result<(prompt: String, dictionary: String, instructions: String?), Error>
    let missingCreditKey: Bool

    init(_ state: AppState) {
        microphoneUID = state.microphoneUID
        earlyTranscriptionEnabled = state.earlyTranscriptionEnabled
        mode = state.mode
        savedCreditConnection = state.creditConnection
        speechConnection = state.speechUsesCredits ? state.creditConnection : nil
        speechProvider = speechConnection == nil ? state.transcriptionProvider : state.creditSpeechProvider
        speechKey = speechConnection?.key ?? state.transcriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        speechModel = speechConnection == nil ? state.transcriptionModel : state.creditTranscriptionModel
        speechMode = speechConnection == nil ? state.transcriptionMode : .fast
        speechURL = state.localTranscriptionURL
        cleanupConnection = state.cleanupUsesCredits && mode != .verbatim ? state.creditConnection : nil
        cleanupProvider = state.cleanupUsesCredits ? state.creditCleanupProvider : state.processingProvider ?? .openRouter
        cleanupKey = cleanupConnection?.key ?? (cleanupProvider.requiresAPIKey ? state.keyValue(cleanupProvider.rawValue) : "").trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupModel = cleanupConnection == nil ? state.processingModel.trimmingCharacters(in: .whitespacesAndNewlines) : state.creditCleanupModel
        cleanupEndpoint = cleanupConnection == nil ? state.processingEndpoint : state.creditCleanupHost
        cleanupURL = state.localProcessingURL
        cleanupRouterOptions = cleanupConnection == nil ? state.routerOptions(model: cleanupModel) : state.creditCleanupOptions
        cleanupOptions = state.codexOptions(model: cleanupModel)
        codexPath = state.codexExecutable
        jevMode = state.jevCleanupMode
        jevRoute = state.jevRoute
        jevConnection = jevRoute == .s2t ? state.creditConnection : nil
        jevKey = (jevRoute == .s2t ? jevConnection?.key ?? "" : jevRoute.account == .typeSafe ? state.typeSafeKey : state.routerKey).trimmingCharacters(in: .whitespacesAndNewlines)
        clipboardEnabled = state.clipboardContextEnabled
        clipboard = clipboardEnabled ? state.clipboardMonitor.snapshot() : ClipboardHistory()
        editingPreferences = Result {
            let prompt = state.isPreview ? WritingMode.defaultEditingInstruction : try AppState.instructionsFile.read()
            let dictionary = state.isPreview ? "" : try AppState.dictionaryFile.read()
            return (prompt, dictionary, state.isPreview ? nil : prompt + DictionaryFile.prompt(content: dictionary))
        }
        missingCreditKey = (state.speechUsesCredits || state.cleanupUsesCredits && mode != .verbatim) && state.creditConnection == nil
    }
}

@MainActor final class DictationSession {
    enum Outcome { case delivered, empty, undelivered, failed, cancelled, interrupted }
    enum TerminalState { case open, completing(Outcome), completed(Outcome), completionFailed(Outcome) }
    private(set) var terminalState: TerminalState = .open
    private var storageTask: Task<RecordingRecovery?, Error>?
    let configuration: DictationConfiguration
    var requestID: String
    var audio: Data?
    var recovery: RecordingRecovery?
    var isSaved = false
    private var captureFinish: Task<Data, Never>?

    init(configuration: DictationConfiguration, audio: Data? = nil, recovery: RecordingRecovery? = nil) {
        self.configuration = configuration
        self.audio = audio
        self.recovery = recovery
        requestID = recovery?.requestID ?? UUID().uuidString
    }

    func finishCapture(_ microphone: Microphone) async -> Data {
        if captureFinish == nil { captureFinish = Task { await microphone.finish() } }
        let captured = await captureFinish!.value
        if captured.count > 44 { audio = captured }
        return captured
    }

    func save(transcript: String, to store: RecordingRecoveryStore?) async throws -> RecordingRecovery? {
        switch terminalState {
        case .completed: return nil
        case .completing: return try await storageTask?.value
        case .completionFailed(let outcome): return try await finish(outcome, transcript: transcript, store: store)
        case .open: break
        }
        guard var saved = recovery else { return nil }
        saved.requestID = requestID
        saved.transcript = transcript
        recovery = saved
        let previous = storageTask
        let task = Task { () throws -> RecordingRecovery? in
            _ = await previous?.result
            if let store { try await store.save(saved) }
            return saved
        }
        storageTask = task
        let stored = try await task.value
        switch terminalState {
        case .open: isSaved = true; return stored
        case .completed: return nil
        case .completing, .completionFailed: return try await storageTask?.value
        }
    }

    func finish(_ outcome: Outcome, transcript: String, store: RecordingRecoveryStore?) async throws -> RecordingRecovery? {
        switch outcome {
        case .delivered, .empty:
            switch terminalState {
            case .completed: return nil
            case .completing: return try await storageTask?.value
            case .open, .completionFailed: break
            }
            terminalState = .completing(outcome)
            let saved = recovery
            let previous = storageTask
            let task = Task { () throws -> RecordingRecovery? in
                _ = await previous?.result
                do {
                    if let saved, let store { try await store.complete(saved) }
                    recovery = nil
                    isSaved = true
                    terminalState = .completed(outcome)
                    return nil
                } catch {
                    terminalState = .completionFailed(outcome)
                    throw error
                }
            }
            storageTask = task
            return try await task.value
        case .undelivered, .failed, .cancelled, .interrupted:
            return try await save(transcript: transcript, to: store)
        }
    }
}
