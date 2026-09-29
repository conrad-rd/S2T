import AppKit
import S2TCore

@MainActor enum EarlyTranscriptionProbe {
    static func run() async throws {
        let baseline = try await verify(early: false)
        let early = try await verify(early: true)
        guard early < baseline * 0.6 else { throw failure("Transcription completed during recording did not reduce Finish latency") }
        print(String(format: "Generated 21-second audio, simulated provider: Finish to delivery %.0f ms before, %.0f ms with early transcription", baseline * 1000, early * 1000))
        _ = try await verify(early: true, finishDuringRequest: true)
        _ = try await verify(early: true, cancel: true)
        print("PASS: real AppState start/Finish, encrypted prefix recovery, in-flight Finish, cancellation, exact audio, one complete cleanup request and no repeated completed uploads. Synthetic audio and isolated providers only.")
    }

    private static func verify(early: Bool, finishDuringRequest: Bool = false, cancel: Bool = false) async throws -> Double {
        let rate = 48000
        func speech(_ seconds: Double) -> [Float] {
            (0..<Int(Double(rate) * seconds)).map { Float(sin(Double($0) * 0.057) * 0.35) }
        }
        let quiet = [Float](repeating: 0, count: rate)
        let signal = speech(8) + quiet + speech(8) + quiet + speech(3)
        let transport = EarlyProbeTransport()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-early-probe-" + UUID().uuidString)
        let store = RecordingRecoveryStore(directory: directory, key: { Data(repeating: 35, count: 32) })
        let suite = "com.s2t.early-probe." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        defer { try? FileManager.default.removeItem(at: directory) }
        var delivered = false
        let state = AppState(preview: true, previewPreferences: preferences, microphone: Microphone(simulatedAudio: signal, startDelay: 0), microphoneAccess: { true },
            recoveryStore: store, creditsAPI: CreditsAPI(transport: transport), insertText: { text, _ in
                guard text == "Final complete edit" else { throw failure("Incomplete output reached insertion") }
                delivered = true
                return .textSent
            })
        defer { state.cancel() }
        state.earlyTranscriptionEnabled = early
        state.creditsAddress = "http://localhost:4317"
        state.speechUsesCredits = true
        state.creditSpeechProvider = .assemblyAI
        state.cleanupUsesCredits = true
        state.creditCleanupModel = "openai/gpt-oss-120b"
        state.creditCleanupHost = "cerebras/fp16"
        state.mode = .clean
        let editor = APIKeyEditing(state: state)
        editor.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t")
        editor.save("s2t")
        try await wait { state.creditConnection != nil }
        state.handleActivation(.start)
        try await wait { state.phase == .recording || state.phase == .failed }
        guard state.phase == .recording else { throw failure(state.errorMessage ?? "Recording failed") }
        if early {
            for _ in 0..<2000 {
                if finishDuringRequest || cancel {
                    if await transport.speechStarted > 0 { break }
                } else if await transport.speechCompleted == 2 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard await transport.speechStarted > 0, state.phase == .recording, !delivered else {
                throw failure("No transcription was started while recording")
            }
            let pending = try await store.pending()
            guard let saved = pending.first, saved.speechSegmentEnds?.isEmpty == false, !saved.audio.isEmpty else {
                throw failure("Early upload did not have a durable recovery record")
            }
        } else { try await Task.sleep(for: .milliseconds(400)) }
        if cancel {
            state.handleActivation(.cancel)
            state.handleActivation(.start)
            try await wait { state.phase == .recording || state.phase == .failed }
            guard state.phase == .recording else { throw failure("Cancellation prevented the next recording") }
            state.handleActivation(.cancel)
            try await Task.sleep(for: .milliseconds(500))
            guard state.phase == .idle, !delivered, await transport.cleanupRequests == 0,
                  try await store.pending().isEmpty else { throw failure("Cancelled early transcription resumed or left pending audio") }
            return 0
        }
        // AppState rejects accidental sub-300-ms recordings; the fixture's audio clock is accelerated.
        try await Task.sleep(for: .milliseconds(350))
        let started = ProcessInfo.processInfo.systemUptime
        state.handleActivation(.stop)
        try await wait { state.phase == .complete || state.phase == .failed }
        let duration = ProcessInfo.processInfo.systemUptime - started
        guard delivered, state.phase == .complete, await transport.cleanupRequests == 1 else {
            throw failure(state.errorMessage ?? "Early transcription did not deliver")
        }
        let parts = await transport.audio
        let source = WaveAudio.encode(samples: signal.map { Int16($0 * 32767) }, sampleRate: UInt32(rate))
        let expected = WaveAudio.speechUpload(source).dropFirst(44)
        guard parts.reduce(into: Data(), { $0.append($1.dropFirst(44)) }) == expected else {
            throw failure("Section uploads lost, repeated or changed audio samples")
        }
        guard try await store.pending().isEmpty, state.recoveredRecordings.isEmpty else { throw failure("Completed recovery remained pending") }
        return duration
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<3000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw failure("Early transcription fixture timed out")
    }

    private static func failure(_ text: String) -> ServiceError { .message(text) }
}

private actor EarlyProbeTransport: HTTPTransport {
    var audio: [Data] = []
    var speechStarted = 0
    var speechCompleted = 0
    var cleanupRequests = 0
    private var ids = Set<String>()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response: String
        switch request.url!.path {
        case "/api/v1/balance": response = #"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"demo"}"#
        case "/api/v1/warm": response = #"{"ready":true}"#
        case "/api/v1/requests":
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            if body["operation"] == "transcription" {
                guard body["model"] == "universal-3-5-pro", body["provider"] == "assemblyai",
                      let data = body["audio"].flatMap({ Data(base64Encoded: $0) }),
                      let id = request.value(forHTTPHeaderField: "Idempotency-Key"), ids.insert(id).inserted else {
                    throw ServiceError.message("An early section was duplicated or changed speech model")
                }
                speechStarted += 1
                audio.append(data)
                let seconds = Double(data.count - 44) / 32000
                try await Task.sleep(for: .seconds(0.03 + seconds * 0.045))
                speechCompleted += 1
                response = "{\"state\":\"settled\",\"result\":{\"text\":\"Section \(speechStarted)\",\"model\":\"universal-3-5-pro\"}}"
            } else {
                cleanupRequests += 1
                guard body["model"] == "openai/gpt-oss-120b", body["host"] == "cerebras/fp16",
                      let text = body["text"], (1...speechCompleted).allSatisfy({ text.contains("Section \($0)") }) else {
                    throw ServiceError.message("Cleanup did not receive the complete transcript on the selected route")
                }
                try await Task.sleep(for: .milliseconds(50))
                response = #"{"state":"settled","result":{"text":"Final complete edit","model":"openai/gpt-oss-120b","host":"Cerebras"}}"#
            }
        default: throw URLError(.unsupportedURL)
        }
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
