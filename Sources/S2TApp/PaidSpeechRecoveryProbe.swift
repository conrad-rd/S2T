import AppKit
import S2TCore

@MainActor enum PaidSpeechRecoveryProbe {
    static func run() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-paid-speech-" + UUID().uuidString)
        let suite = "com.s2t.paid-speech." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let transport = SpeechReplayTransport()
        let store = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 61, count: 32) })
        func state(_ store: RecordingRecoveryStore) async throws -> AppState {
            let value = AppState(preview: true, previewPreferences: preferences, recoveryStore: store,
                creditsAPI: CreditsAPI(transport: transport), insertText: { _, _ in .destinationUnavailable })
            value.mode = .verbatim; value.speechUsesCredits = true; value.cleanupUsesCredits = false
            value.creditSpeechProvider = .assemblyAI; value.creditsAddress = "http://localhost:4317"
            let editing = APIKeyEditing(state: value)
            editing.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t"); editing.save("s2t")
            try await wait { value.creditConnection != nil }
            return value
        }
        let original = try await state(store)
        defer { original.cancel() }
        original.processRecording(WaveAudio.encode(samples: Array(repeating: 500, count: 16000), sampleRate: 16000))
        try await wait { original.phase == .failed }
        let restartedStore = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 61, count: 32) })
        let saved = try await restartedStore.pending()[0]
        let restarted = try await state(restartedStore)
        defer { restarted.cancel() }
        restarted.creditSpeechProvider = .xai
        let switchedKey = APIKeyEditing(state: restarted)
        switchedKey.paste("s2t_demo_" + String(repeating: "b", count: 64), for: "s2t"); switchedKey.save("s2t")
        try await wait { restarted.creditConnection?.key.hasSuffix(String(repeating: "b", count: 64)) == true }
        restarted.recoverRecording(saved); restarted.retry()
        try await wait { !restarted.phase.busy }
        guard restarted.phase == .failed, restarted.errorMessage?.contains("Reconnect the S2T key") == true,
              await transport.requests.count == 1 else { throw ServiceError.message("Changed account submitted a saved paid speech request") }
        switchedKey.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t"); switchedKey.save("s2t")
        try await wait { restarted.creditConnection?.key.hasSuffix(String(repeating: "a", count: 64)) == true }
        restarted.speechUsesCredits = false
        restarted.transcriptionProvider = .local
        restarted.retry()
        try await wait { !restarted.phase.busy }
        let requests = await transport.requests
        guard requests.count == 2, requests[0].httpBody == requests[1].httpBody,
              requests[0].value(forHTTPHeaderField: "Idempotency-Key") == requests[1].value(forHTTPHeaderField: "Idempotency-Key") else {
            throw ServiceError.message("Paid speech retry changed its original body or identity after restart/settings change")
        }
        var legacy = RecordingRecovery(audio: saved.audio, requestID: "legacy-speech", mode: .verbatim)
        legacy.creditSpeechSnapshotVersion = nil
        try await restartedStore.save(legacy)
        restarted.speechUsesCredits = true
        restarted.recoverRecording(legacy); restarted.retry()
        try await wait { !restarted.phase.busy }
        guard restarted.phase == .failed, restarted.errorMessage?.contains("predates exact paid speech recovery") == true,
              await transport.requests.count == 2 else { throw ServiceError.message("Legacy speech retry submitted a request without its original contract") }
        await transport.rejectNextSpeech()
        restarted.processRecording(saved.audio)
        try await wait { restarted.phase == .failed }
        let renewed = restarted.recovery!
        let renewedStore = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 61, count: 32) })
        guard let renewedAfterRestart = try await renewedStore.pending().first(where: { $0.id == renewed.id }),
              renewedAfterRestart.creditSpeechRequest?.parts == renewed.creditSpeechRequest?.parts else {
            throw ServiceError.message("Rejected speech renewal was not durable before restart")
        }
        let afterRestart = try await state(renewedStore)
        defer { afterRestart.cancel() }
        afterRestart.recoverRecording(renewedAfterRestart); afterRestart.retry()
        try await wait { !afterRestart.phase.busy }
        let afterRejection = await transport.requests
        guard afterRejection.count == 4, afterRejection[2].httpBody == afterRejection[3].httpBody,
              afterRejection[3].value(forHTTPHeaderField: "Idempotency-Key") == renewed.creditSpeechRequest?.parts.first?.requestID,
              afterRejection[2].value(forHTTPHeaderField: "Idempotency-Key") != afterRejection[3].value(forHTTPHeaderField: "Idempotency-Key") else {
            throw ServiceError.message("Definitively rejected speech did not renew only its payment identity")
        }
        print("Paid speech: exact restart/settings replay, wrong-account refusal, legacy refusal and definitive rejection renewal PASS")
    }

    static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ServiceError.message("Paid speech fixture timed out")
    }
}

private actor SpeechReplayTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var shouldReject = false
    func rejectNextSpeech() { shouldReject = true }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var body = #"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"demo"}"#
        if request.url?.path == "/api/v1/requests" {
            requests.append(request)
            if requests.count == 1 { throw URLError(.badServerResponse) }
            if shouldReject { shouldReject = false; body = #"{"state":"released","error":"Fixture rejected the speech request"}"# }
            else { body = #"{"state":"settled","result":{"text":"Original speech","model":"universal-3-5-pro"}}"# }
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
