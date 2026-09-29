import AppKit
import S2TCore

@MainActor enum NativeStateRegressionProbe {
    static func run() async throws {
        let suite = "com.s2t.native-state-test." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-legacy-receipt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RecordingRecoveryStore(directory: folder, key: { Data(repeating: 28, count: 32) })
        let transport = NativeBalanceFixture()
        var catalogCalls = 0
        let state = AppState(preview: true, previewPreferences: preferences, speechCatalogLoader: {
            catalogCalls += 1
            if catalogCalls == 1 { throw URLError(.notConnectedToInternet) }
            return [.init(id: "fixture/model", name: "Refreshed")]
        }, recoveryStore: store, creditsAPI: CreditsAPI(transport: transport))
        defer { state.cancel() }
        state.creditsAddress = "http://localhost:4317"
        let editing = APIKeyEditing(state: state)
        editing.paste("s2t_demo_" + String(repeating: "a", count: 64), for: "s2t")
        editing.save("s2t")
        for _ in 0..<200 where state.creditConnection == nil { try await Task.sleep(for: .milliseconds(5)) }
        guard state.creditBalance?.available == 0 else { throw failure("Zero-balance fixture was not loaded") }
        await state.refreshCredits()
        guard state.creditBalance?.available == 100 else { throw failure("Top-up was blocked by the zero-balance status") }
        await state.refreshSpeechCatalog()
        await state.refreshSpeechCatalog()
        guard catalogCalls == 2, state.routerSpeechModels.first?.id == "fixture/model" else { throw failure("A failed catalog request started the success cooldown") }
        await state.refreshSpeechCatalog()
        guard catalogCalls == 2 else { throw failure("Successful catalog was not cached") }
        await state.refreshSpeechCatalog(force: true)
        guard catalogCalls == 3 else { throw failure("Explicit refresh did not bypass the catalog cache") }
        var legacy = RecordingRecovery(audio: Data([1, 2]), requestID: "legacy", mode: .verbatim)
        legacy.streamingReceipt = CreditStreamingReceipt(authorizationID: "saved-auth", sessionID: "saved-session", sessionDurationSeconds: 5, audioDurationSeconds: 4)
        try await store.save(legacy)
        await state.refreshCredits(force: true)
        await state.refreshCredits(force: true)
        guard await transport.paths.allSatisfy({ !$0.contains("streaming") }),
              try await store.pendingStreamingReports().count == 1 else { throw failure("Legacy receipt refresh retried a retired endpoint or cleared metadata") }
        guard state.historicalStreamingReceiptCount == 1,
              state.historicalReceiptNotice?.contains("may already have been reconciled") == true else {
            throw failure("Historical receipt confirmation notice is absent or implies an outstanding hold")
        }
        try await store.complete(legacy)
        await state.refreshCredits(force: true)
        guard state.historicalStreamingReceiptCount == 1, try await store.pendingStreamingReports().count == 1 else {
            throw failure("Delivery discarded the historical financial receipt")
        }
        try await store.save(legacy)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("broken.enc"))
        await state.refreshRecoveredRecordings()
        guard state.recoveredRecordings.count == 1, state.notice?.contains("could not be read") == true else {
            throw failure("Corrupt sibling notice was hidden by the healthy recording")
        }
        try await BenchmarkFeedProbe.run()
        print("PASS: top-up revalidation, failed catalog retry, forced catalog refresh, speech-only local text preservation, historical receipt preservation without retired requests, and corrupt-sibling notices. Synthetic transports and isolated preferences.")
    }
    static func failure(_ message: String) -> ServiceError { .message(message) }
}

private actor NativeBalanceFixture: HTTPTransport {
    var calls = 0
    var paths: [String] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        paths.append(request.url!.path)
        let text = "{\"available\":\(calls == 1 ? 0 : 100),\"reserved\":0,\"frozen\":false,\"paused\":false,\"mode\":\"demo\"}"
        return (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
