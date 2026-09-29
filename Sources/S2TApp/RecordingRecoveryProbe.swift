import AppKit
import S2TCore

@MainActor enum RecordingRecoveryProbe {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-recovery-probe-" + UUID().uuidString)
        let store = RecordingRecoveryStore(directory: directory, key: { Data(repeating: 19, count: 32) })
        let transport = RecoveryProbeTransport()
        let state = AppState(preview: true, recoveryStore: store, api: DictationAPI(transport: transport), insertText: { _, _ in .textSent })
        state.mode = .verbatim
        state.speechUsesCredits = false
        state.cleanupUsesCredits = false
        state.transcriptionProvider = .assemblyAI
        state.transcriptionMode = .fast
        state.assemblyKey = "synthetic-recovery-key"
        let audio = WaveAudio.encode(samples: Array(repeating: 15, count: 16000), sampleRate: 16000)
        state.processRecording(audio)
        for _ in 0..<200 {
            if state.phase == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard state.phase == .failed, state.output.isEmpty, state.canRetry, state.canSaveRecording else { throw failure("A failed transcription must expose its recording without a transcript") }
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); state.cancel() }
        controller.menuNeedsUpdate(controller.menu)
        guard controller.menu.items.first(where: { $0.identifier?.rawValue == "result.retry" })?.isEnabled == true else {
            throw failure("Retry last dictation is unavailable for a failed recording")
        }
        controller.appearanceWindow.showDictation()
        guard controller.appearanceWindow.showingDictation, state.canSaveRecording else {
            throw failure("Saving a failed recording must remain available in Dictation settings")
        }
        let restarted = AppState(preview: true, recoveryStore: store, api: DictationAPI(transport: transport), insertText: { _, _ in .textSent })
        defer { restarted.cancel() }
        await restarted.refreshRecoveredRecordings()
        guard let saved = restarted.recoveredRecordings.first, saved.audio == audio else { throw failure("Restart lost the encrypted recording") }
        restarted.recoverRecording(saved)
        guard restarted.canRetry, restarted.canSaveRecording else { throw failure("Recovered audio is not actionable") }
        restarted.retry()
        for _ in 0..<200 {
            if restarted.phase == .complete { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let pending = try await store.pending()
        guard restarted.phase == .complete, restarted.output == "Recovered words", pending.isEmpty else { throw failure("Recovered recording did not deliver or clear its pending recovery") }
        let blockedTransport = RecoveryProbeTransport()
        let blockedStore = RecordingRecoveryStore(directory: directory.appendingPathComponent("blocked"), key: { throw CocoaError(.fileWriteNoPermission) })
        let blocked = AppState(preview: true, recoveryStore: blockedStore, api: DictationAPI(transport: blockedTransport), insertText: { _, _ in .textSent })
        defer { blocked.cancel() }
        blocked.processRecording(audio)
        for _ in 0..<200 {
            if blocked.phase == .failed { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let networkCalls = await blockedTransport.calls
        guard blocked.phase == .failed, blocked.canSaveRecording, networkCalls == 0 else { throw failure("Recovery write failure must retain audio and prevent uploads") }
        blocked.recoverRecording(saved)
        guard blocked.errorMessage?.contains("only copy") == true else { throw failure("Opening another recording replaced unsaved audio") }
        print("PASS: failed transcription exposes Retry and Save with no transcript; encrypted audio survives a new AppState; retry delivers and completes recovery. Isolated audio, storage, key and transport only.")
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "RecordingRecoveryProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private actor RecoveryProbeTransport: HTTPTransport {
    private var failed = false
    var calls = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if !failed { failed = true; throw ServiceError.message("S2T credits: Request body is too large.") }
        return (Data(#"{"text":"Recovered words"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
