import Foundation
import S2TCore

@MainActor enum BenchmarkFeedProbe {
    static func runPublic() async throws {
        let snapshot = try await ArtificialAnalysisPublicClient().fetch()
        let catalog = try await SpeechModelCatalog.load()
        let offers = catalog.map { BenchmarkOffering(id: "openrouter/" + $0.id, name: $0.name, task: "speech") } +
            TranscriptionProvider.xaiModels.map { BenchmarkOffering(id: "xai/" + $0, name: $0, task: "speech") } +
            [.init(id: "assemblyai/universal-3-pro", name: "Universal 3 Pro", task: "speech"),
             .init(id: "assemblyai/universal-3-5-pro", name: "Universal 3.5 Pro", task: "speech")]
        let models = BenchmarkAvailability.filter(snapshot.models, offered: offers)
        let ranked = BenchmarkRanking.rank(models, enabled: [.quality], quality: .speech)
        guard snapshot.tier == "public", ranked.count >= 5, catalog.count > 3 else {
            throw failure("Public catalogs must yield at least five measured speech models")
        }
        print("Public speech feed: \(catalog.count) OpenRouter models, \(models.count) offered models, \(ranked.count) measured models, \(BenchmarkRanking.top(ranked).count) ranked columns. No API key or local credentials used.")
    }

    static func run() async throws {
        let transport = BenchmarkFeedFixture()
        let feed = BenchmarkFeed(preview: true, client: .init(transport: transport), publicClient: .init(transport: transport))
        await feed.refresh(key: "")
        let initialCalls = await transport.calls
        guard initialCalls == 1, feed.snapshot?.tier == "public", feed.message.contains("Public benchmark table") else {
            throw failure("A keyless benchmark feed must read the public table without authentication")
        }
        let local = try LocalModel.read(from: URL(fileURLWithPath: "Resources/LocalModels/catalog.json"))
        guard feed.models(local: local).contains(where: { $0.provider == "Local" && $0.task == "text" }) else {
            throw failure("Speech-only refresh removed local text references")
        }
        await feed.refresh(key: "fixture-a")
        guard feed.snapshot?.models.count == 1, feed.snapshot?.tier == "free", !feed.loading,
              feed.models(local: []).contains(where: { $0.id == "aa/fixture/text" }),
              !feed.models(local: []).contains(where: { $0.task == "text" && $0.id.hasPrefix("reference/") }) else {
            throw failure("Fresh API data must replace dated references only for available tasks")
        }
        let refreshedCalls = await transport.calls
        await feed.refresh(key: "fixture-a")
        let repeatedCalls = await transport.calls
        guard refreshedCalls == repeatedCalls else { throw failure("Opening Models repeatedly must use the six-hour cache") }
        await feed.refresh(key: "rejected-fixture-b")
        guard feed.snapshot == nil, feed.message.contains("rejected"), !feed.loading else {
            throw failure("Changing API accounts must clear old results and explain authentication failures")
        }
        await feed.refresh(key: "")
        guard feed.snapshot?.tier == "public", feed.message.contains("Public benchmark table") else {
            throw failure("Removing the key must return to the public benchmark table")
        }
        print("Benchmark feed verified: public data without a key, cached refresh, account isolation and honest per-task fallback. Mock transport only.")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BenchmarkFeedProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
private actor BenchmarkFeedFixture: HTTPTransport {
    private(set) var calls = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if request.url == ArtificialAnalysisPublicClient.speechURL {
            guard request.value(forHTTPHeaderField: "x-api-key") == nil else { throw URLError(.userAuthenticationRequired) }
            let html = "<table><tr><th>Model</th><th>Provider</th><th>Word Error Rate</th><th>Median Speed Factor</th><th>Price</th></tr><tr><td>Grok Voice Transcribe 2.0</td><td>SpaceXAI</td><td>2.3%</td><td>153.8</td><td>1.67</td></tr></table>"
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let rejected = request.value(forHTTPHeaderField: "x-api-key") == "rejected-fixture-b"
        if request.url!.path.contains("language/providers") {
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }
        let body = request.url!.path.contains("speech-to-text") ? #"{"tier":"free","data":[]}"# :
            #"{"status":200,"data":[{"id":"fixture","slug":"fixture","name":"Fixture","evaluations":{"artificial_analysis_intelligence_index":50},"median_output_tokens_per_second":125,"pricing":null}]}"#
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: rejected ? 401 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
