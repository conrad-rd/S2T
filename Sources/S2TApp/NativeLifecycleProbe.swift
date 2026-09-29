import AppKit
import S2TCore

@MainActor enum NativeLifecycleProbe {
    static func run() async throws {
        try await PaidSpeechRecoveryProbe.run()
        try await SessionTerminalProbe.run()
        try await emptyCompletion()
        try await pendingIndexAndReplay()
        try await legacyDraftCannotBeResubmitted()
        try await interruptedCapture(stopFirst: false, early: false)
        try await interruptedCapture(stopFirst: true, early: false)
        try await interruptedCapture(stopFirst: false, early: true)
        try await interruptedCapture(stopFirst: false, early: false, blocked: true)
        try await configurationIsFrozen()
        print("PASS: empty completion, pending recovery index, immutable paid retry, legacy paid-draft refusal, capture/stop interruption, early-prefix preservation, save-failure quit refusal and frozen recording configuration. Synthetic microphone, transport, keys, preferences and files only.")
    }

    private static func fixture(_ name: String, transport: LifecycleTransport, audio: [Float] = [], blocked: Bool = false,
                                insertion: @escaping (String, TextInsertion.Target?) async throws -> TextInsertion.Outcome = { _, _ in .textSent }) async throws -> (AppState, RecordingRecoveryStore, URL, () -> Void) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-lifecycle-" + UUID().uuidString)
        let store = RecordingRecoveryStore(directory: folder, key: {
            if blocked { throw CocoaError(.fileWriteNoPermission) }
            return Data(repeating: 83, count: 32)
        })
        let suite = "com.s2t.lifecycle." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let state = AppState(preview: true, previewPreferences: defaults, microphone: Microphone(simulatedAudio: audio, startDelay: 0), microphoneAccess: { true },
            recoveryStore: store, api: DictationAPI(transport: transport), creditsAPI: CreditsAPI(transport: transport), insertText: insertion)
        state.mode = .verbatim
        state.earlyTranscriptionEnabled = false
        state.creditsAddress = "http://localhost:4317"
        state.speechUsesCredits = true
        state.cleanupUsesCredits = false
        state.creditSpeechProvider = .assemblyAI
        let editing = APIKeyEditing(state: state)
        editing.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t")
        editing.save("s2t")
        try await wait { state.creditConnection != nil }
        return (state, store, folder, { defaults.removePersistentDomain(forName: suite) })
    }

    private static func emptyCompletion() async throws {
        let transport = LifecycleTransport(empty: true)
        let (state, store, folder, cleanup) = try await fixture("empty", transport: transport)
        defer { state.cancel(); cleanup(); try? FileManager.default.removeItem(at: folder) }
        state.mode = .clean; state.cleanupUsesCredits = true
        state.processRecording(audio())
        try await wait { !state.phase.busy }
        guard state.phase == .idle, state.output.isEmpty, try await store.pending().isEmpty, state.recoveredRecordings.isEmpty else {
            throw failure("Successful empty cleanup was left unfinished")
        }
    }

    private static func pendingIndexAndReplay() async throws {
        let transport = LifecycleTransport(loseCleanup: true)
        let (state, store, folder, cleanup) = try await fixture("retry", transport: transport, insertion: { _, _ in .destinationUnavailable })
        defer { state.cancel(); cleanup(); try? FileManager.default.removeItem(at: folder) }
        state.mode = .clean; state.cleanupUsesCredits = true
        state.processRecording(audio())
        try await wait { !state.phase.busy }
        guard state.recoveredRecordings.count == 1, try await store.pending().count == 1 else { throw failure("Undelivered recording was absent from recovery index") }
        let first = try await store.pending()[0]
        guard first.creditCleanupRequest != nil else { throw failure("Paid input was not durable before submission") }
        state.creditCleanupModel = "different/model"
        state.creditCleanupHost = "different/host"
        state.retry()
        try await wait { !state.phase.busy }
        let bodies = await transport.cleanupBodies
        guard bodies.count == 2, bodies[0] == bodies[1], state.output == "Edited words" else { throw failure("Retry changed the saved paid body or lost its result") }
        state.processRecording(audio())
        try await wait { !state.phase.busy }
        guard state.recoveredRecordings.count == 2, state.recoveredRecordings.contains(where: { $0.id == first.id }) else {
            throw failure("A subsequent recording hid the earlier saved one")
        }
    }

    private static func legacyDraftCannotBeResubmitted() async throws {
        let transport = LifecycleTransport()
        let (state, store, folder, cleanup) = try await fixture("legacy", transport: transport)
        defer { state.cancel(); cleanup(); try? FileManager.default.removeItem(at: folder) }
        var old = RecordingRecovery(audio: audio(), requestID: "legacy-identity", mode: .clean, transcript: "Original legacy transcript")
        old.creditCleanupDraft = CreditCleanupDraft(requestID: "legacy-identity-cleanup", original: old.transcript, text: old.transcript)
        try await store.save(old)
        state.mode = .clean; state.cleanupUsesCredits = true
        state.recoverRecording(old)
        for _ in 0..<2 {
            state.retry()
            try await wait { !state.phase.busy }
            guard state.phase == .failed, state.errorMessage?.contains("predates exact request recovery") == true,
                  state.output == old.transcript, state.canSaveRecording else { throw failure("Legacy cleanup did not preserve an actionable original transcript/audio") }
        }
        let requests = await transport.cleanupBodies
        let speech = await transport.speechStarted
        let pending = try await store.pending()
        guard requests.isEmpty, speech == 0, pending.first?.requestID == old.requestID,
              pending.first?.creditCleanupDraft?.requestID == old.creditCleanupDraft?.requestID,
              pending.first?.audio == old.audio else { throw failure("Legacy retry submitted or replaced an uncertain paid identity") }
        state.mode = .verbatim
        state.retry()
        try await wait { !state.phase.busy }
        guard state.phase == .complete, state.output == old.transcript, await transport.cleanupBodies.isEmpty else {
            throw failure("Explicit Verbatim recovery did not deliver original text without payment")
        }
    }

    private static func interruptedCapture(stopFirst: Bool, early: Bool, blocked: Bool = false) async throws {
        let signal = early ? Array(repeating: Float(0.3), count: 48000 * 8) + Array(repeating: 0, count: 48000) : Array(repeating: Float(0.3), count: 48000)
        let transport = LifecycleTransport(delaySpeech: early)
        var delivered = false
        let (state, store, folder, cleanup) = try await fixture("interrupt", transport: transport, audio: signal, blocked: blocked, insertion: { _, _ in delivered = true; return .textSent })
        defer { state.cancel(); cleanup(); try? FileManager.default.removeItem(at: folder) }
        state.earlyTranscriptionEnabled = early
        state.handleActivation(.start)
        try await wait { state.phase == .recording }
        if early {
            for _ in 0..<500 {
                if await transport.speechStarted > 0 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard await transport.speechStarted > 0 else { throw failure("Early fixture did not start an in-flight upload") }
        }
        if stopFirst { state.handleActivation(.stop) }
        let saved = await state.preserveForInterruption()
        guard !delivered, state.canSaveRecording else { throw failure("Interruption delivered text or discarded captured audio") }
        if blocked {
            guard !saved, state.phase == .failed else { throw failure("Quit was allowed with the only audio copy unsaved") }
            return
        }
        let pending = try await store.pending()
        let expected = WaveAudio.encode(samples: signal.map { Int16($0 * 32767) }, sampleRate: 48000)
        guard saved, pending.count == 1, pending[0].audio == expected, state.recoveredRecordings.count == 1 else {
            throw failure("Interruption did not retain the complete original microphone audio")
        }
        if early { guard pending[0].speechSegmentEnds?.isEmpty == false else { throw failure("Saved early request boundaries were erased") } }
        try await Task.sleep(for: .milliseconds(50))
        guard try await store.pending().count == 1 else { throw failure("Canceled early task erased preserved interruption data") }
    }

    private static func configurationIsFrozen() async throws {
        let transport = LifecycleTransport()
        let (state, _, folder, cleanup) = try await fixture("snapshot", transport: transport, audio: Array(repeating: Float(0.3), count: 48000))
        defer { state.cancel(); cleanup(); try? FileManager.default.removeItem(at: folder) }
        state.handleActivation(.start)
        try await wait { state.phase == .recording }
        state.mode = .clean; state.cleanupUsesCredits = true
        state.creditSpeechProvider = .xai
        try await Task.sleep(for: .milliseconds(310))
        state.handleActivation(.stop)
        try await wait { !state.phase.busy && state.phase != .recording }
        guard state.phase == .complete, await transport.cleanupBodies.isEmpty, await transport.speechProviders == ["assemblyai"] else {
            throw failure("Changing preferences during capture changed the in-flight session")
        }
    }

    private static func audio() -> Data { WaveAudio.encode(samples: Array(repeating: 200, count: 16000), sampleRate: 16000) }
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw failure("Native lifecycle fixture timed out")
    }
    private static func failure(_ text: String) -> ServiceError { .message(text) }
}

private actor LifecycleTransport: HTTPTransport {
    let empty: Bool, loseCleanup: Bool, delaySpeech: Bool
    var cleanupBodies: [Data] = []
    var speechStarted = 0
    var speechProviders: [String] = []
    init(empty: Bool = false, loseCleanup: Bool = false, delaySpeech: Bool = false) {
        self.empty = empty; self.loseCleanup = loseCleanup; self.delaySpeech = delaySpeech
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var response = #"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"demo"}"#
        if request.url?.path == "/api/v1/requests" {
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            let cleanup = body["operation"] == "cleanup"
            if cleanup {
                cleanupBodies.append(request.httpBody!)
                if loseCleanup, cleanupBodies.count == 1 { throw URLError(.badServerResponse) }
            } else {
                speechStarted += 1; speechProviders.append(body["provider"] ?? "")
                if delaySpeech { try await Task.sleep(for: .seconds(5)) }
            }
            let text = cleanup ? (empty ? "__S2T_NO_TEXT_0__" : "Edited words") : "Original words"
            response = String(decoding: try JSONSerialization.data(withJSONObject: ["state": "settled", "result": ["text": text, "model": body["model"] ?? "fixture"]]), as: UTF8.self)
        }
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
