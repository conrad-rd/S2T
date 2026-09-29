import AppKit
import Combine
import S2TCore

@MainActor enum RecordingStartupProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        try await verify()
        try await verifyMixedWarm()
        if CommandLine.arguments.contains("--require-nonblocking") {
            try await verify(cancelled: true)
            try await verify(rejected: true)
            try await verify(longRecording: true)
            try Microphone.verifyStreamingAudio()
            for phase in [DictationPhase.preparing, .recording] {
                guard !phase.processingAudio,
                      BezelSymbol.resolve(phase: phase, waiting: false, deliveryHint: nil) == .waveform,
                      !InputOutline.showsProcessing(phase) else {
                    throw ServiceError.message("Starting dictation selected a processing appearance")
                }
            }
            print("PASS: cancellation before upload, failed transcription recovery, longer audio, bounded legacy streaming chunks and immediate listening appearances.")
        }
    }

    private static func verify(cancelled: Bool = false, rejected: Bool = false, longRecording: Bool = false) async throws {
        let transport = StartupTransport(rejected: rejected, delay: longRecording ? 6 : 1)
        let signal = (0..<(longRecording ? 48000 * 6 : 24000)).map { Float(sin(Double($0) * 0.07) * 0.4) }
        let microphone = Microphone(simulatedAudio: signal, startDelay: 0.015)
        var delivered = false
        let state = AppState(preview: true, microphone: microphone, microphoneAccess: { true },
            creditsAPI: CreditsAPI(transport: transport),
            insertText: { text, _ in
                guard text == "Opening words preserved" else { throw ServiceError.message("Wrong startup transcript") }
                delivered = true
                return .textSent
            })
        defer { state.cancel() }
        state.creditsAddress = "http://localhost:4317"
        state.speechUsesCredits = true
        state.creditSpeechProvider = .assemblyAI
        state.cleanupUsesCredits = false
        state.mode = .verbatim
        let editor = APIKeyEditing(state: state)
        editor.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t")
        editor.save("s2t")
        try await wait { state.creditConnection != nil }
        var appeared: Double?
        let subscription = state.$overlayVisible.sink { visible in
            if visible && appeared == nil { appeared = ProcessInfo.processInfo.systemUptime }
        }
        defer { subscription.cancel() }
        let start = ProcessInfo.processInfo.systemUptime
        state.handleActivation(.start)
        try await wait { state.phase == .recording || state.phase == .failed }
        guard state.phase == .recording else { throw ServiceError.message(state.errorMessage ?? "Did not start") }
        for _ in 0..<100 {
            if await transport.creditWarms > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard await transport.creditWarms == 1 else { throw ServiceError.message("Credit recording did not warm the authenticated ledger") }
        let ready = ProcessInfo.processInfo.systemUptime - start
        let appearance = (appeared ?? start + 10) - start
        print(String(format: "Activation to recording %.2f ms; appearance requested %.2f ms; injected transcription delay %d ms, microphone delay 15 ms", ready * 1000, appearance * 1000, longRecording ? 6000 : 1000))
        if CommandLine.arguments.contains("--require-nonblocking") {
            guard ready < 0.2, appearance < 0.05, await transport.uploads == 0 else {
                throw ServiceError.message("Transcription networking started before Finish or delayed recording")
            }
        }
        if cancelled {
            state.handleActivation(.cancel)
            try await Task.sleep(for: .milliseconds(1100))
            guard state.phase == .idle, !state.overlayVisible, !delivered,
                  await transport.uploads == 0 else {
                throw ServiceError.message("Cancelled recording uploaded audio or restarted dictation")
            }
            return
        }
        try await Task.sleep(for: .milliseconds(350))
        state.handleActivation(.stop)
        try await wait { state.phase == .complete || state.phase == .failed }
        if rejected {
            guard state.phase == .failed, state.canSaveRecording, !delivered, await transport.uploads == 1 else {
                throw ServiceError.message("Transcription failure discarded the recording")
            }
            return
        }
        guard state.phase == .complete, delivered else { throw ServiceError.message(state.errorMessage ?? "Startup delivery failed") }
        guard let full = UserDefaults(suiteName: "com.s2t.preview")?.dictionary(forKey: "lastDictationTiming") as? [String: Double],
              let delivered = full["stopToInsertionReturn"], let completed = full["stopToComplete"],
              let capture = full["stopToPipeline"], let preparation = full["preTranscription"],
              let transcription = full["transcription"], let insertion = full["insertion"],
              capture >= 0, preparation >= 0, transcription >= (longRecording ? 5.9 : 0.9), insertion >= 0,
              delivered >= capture + preparation + transcription + insertion - 0.01,
              completed >= delivered, full["words"] == 3 else {
            throw ServiceError.message("Full dictation timing omitted a stage or counted one twice")
        }
        // Cloud speech receives the 16 kHz conversion of every captured sample, including the opening ones.
        let expected = WaveAudio.speechUpload(WaveAudio.encode(samples: signal.map { Int16($0 * 32767) }, sampleRate: 48000))
        guard await transport.audio == expected, await transport.uploads == 1 else {
            throw ServiceError.message("Opening audio changed or transcription was duplicated")
        }
        print("PASS: activation through delivery preserves every opening audio sample and uploads once after Finish. Isolated preferences, synthetic microphone, fake network and output only.")
    }

    private static func verifyMixedWarm() async throws {
        let transport = StartupTransport(rejected: false, delay: 0)
        let state = AppState(preview: true, microphone: Microphone(simulatedAudio: Array(repeating: 0, count: 24000), startDelay: 0),
            microphoneAccess: { true }, api: DictationAPI(transport: transport), creditsAPI: CreditsAPI(transport: transport))
        defer { state.cancel() }
        state.creditsAddress = "http://localhost:4317"
        state.speechUsesCredits = false
        state.cleanupUsesCredits = true
        state.mode = .clean
        state.assemblyKey = "synthetic-personal-key"
        let editor = APIKeyEditing(state: state)
        editor.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t")
        editor.save("s2t")
        try await wait { state.creditConnection != nil }
        state.handleActivation(.start)
        try await wait { state.phase == .recording || state.phase == .failed }
        guard state.phase == .recording else { throw ServiceError.message(state.errorMessage ?? "Mixed routing did not start") }
        for _ in 0..<100 {
            let counts = await transport.warmCounts
            if counts == (1, 1) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard await transport.warmCounts == (1, 1) else {
            throw ServiceError.message("Mixed billing must warm both personal AssemblyAI and the S2T ledger")
        }
        state.handleActivation(.cancel)
    }

    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<4000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ServiceError.message("Startup fixture timed out")
    }
}

private actor StartupTransport: HTTPTransport {
    var uploads = 0
    var audio = Data()
    var creditWarms = 0
    var personalWarms = 0
    var warmCounts: (Int, Int) { (creditWarms, personalWarms) }
    let rejected: Bool
    let delay: Double
    init(rejected: Bool, delay: Double) { self.rejected = rejected; self.delay = delay }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body: String
        var status = 200
        switch request.url!.path {
        case "/api/v1/balance":
            body = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"demo"}"#
        case "/api/v1/requests":
            let payload = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            guard payload["provider"] == "assemblyai", payload["operation"] == "transcription",
                  payload["model"] == "universal-3-5-pro", let encoded = payload["audio"],
                  let decoded = Data(base64Encoded: encoded) else {
                throw ServiceError.message("Unexpected transcription route or model")
            }
            uploads += 1
            audio = decoded
            try await Task.sleep(for: .seconds(delay))
            if rejected {
                status = 402
                body = #"{"error":"Synthetic transcription rejected","code":"insufficient_credits"}"#
            } else { body = #"{"state":"settled","result":{"text":"Opening words preserved","model":"universal-3-5-pro"}}"# }
        case "/api/v1/warm":
            guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer s2t_demo_") == true else {
                throw ServiceError.message("Credit warm-up omitted its S2T key")
            }
            creditWarms += 1
            body = #"{"ready":true}"#
        case "/warm":
            guard request.url?.host == "sync.assemblyai.com", request.value(forHTTPHeaderField: "X-AAI-Model") == "universal-3-5-pro" else {
                throw ServiceError.message("Personal speech warm-up used the wrong provider")
            }
            personalWarms += 1
            body = "{}"
        default: throw URLError(.unsupportedURL)
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
