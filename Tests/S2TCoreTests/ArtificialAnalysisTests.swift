import XCTest
@testable import S2TCore

final class ArtificialAnalysisTests: XCTestCase {
    private func model(_ id: String, _ quality: Double, image: Bool = false) -> String {
        #"{"id":"\#(id)","name":"\#(id)","slug":"\#(id)","evaluations":{"artificial_analysis_intelligence_index":\#(quality),"mmmu_pro":0.6},"pricing":{"price_1m_input_tokens":1,"price_1m_output_tokens":3},"performance":{"median_output_tokens_per_second":99999},"modalities":{"input":{"image":\#(image)}}}"#
    }
    private func page(_ tier: String, _ models: [String], number: Int = 1, more: Bool = false) -> String {
        #"{"tier":"\#(tier)","intelligence_index_version":4.3,"pagination":{"page":\#(number),"has_more":\#(more)},"data":[\#(models.joined(separator: ","))]}"#
    }
    private func provider(_ id: String, _ models: [(String, Double?)]) -> String {
        let rows = models.map { id, speed in
            #"{"id":"\#(id)","pricing":{"price_1m_input_tokens":0.2,"price_1m_output_tokens":0.8},"performance":{"median_output_tokens_per_second":\#(speed.map { String($0) } ?? "null")}}"#
        }
        return #"{"id":"\#(id)","name":"\#(id)","models":[\#(rows.joined(separator: ","))]}"#
    }
    func testTopFiveUseSpecificHostTPSAcrossAllPagesAndNeverUseAggregatedSpeed() async throws {
        let first = (1...4).map { model("m\($0)", Double(100 - $0)) }
        let second = [model("gpt-oss-120b", 50), model("m6", 40, image: true)]
        let transport = AAFixtureTransport([
            page("commercial", first), page("commercial", first, more: true), page("commercial", second, number: 2),
            #"{"tier":"commercial","pagination":{"page":1,"has_more":true},"data":[\#(provider("Groq", [("gpt-oss-120b", 400), ("m1", 100), ("m2", 200)]))]}"#,
            #"{"tier":"commercial","pagination":{"page":2,"has_more":false},"data":[\#(provider("Cerebras", [("gpt-oss-120b", 1700), ("m3", 300), ("m4", 500), ("m6", nil)]))]}"#,
            #"{"tier":"commercial","data":[{"id":"speech","name":"Speech","aa_wer_index":2.4,"providers":[{"id":"speech-host","name":"Speech host","aa_wer_index":2.4,"price_per_1k_minutes":3,"median_speed_factor":100}]}]}"#
        ], legacyUnavailable: true)
        let snapshot = try await ArtificialAnalysisClient(transport: transport).fetch(key: "fixture-aa-key")
        let text = snapshot.models.filter { $0.task == "text" }
        let fastest = BenchmarkRanking.top(BenchmarkRanking.rank(text, enabled: [.speed], quality: .intelligence))
        XCTAssertEqual(fastest.count, 5)
        XCTAssertEqual(fastest.map { $0.model.modelID! }, ["gpt-oss-120b", "m4", "m3", "m2", "m1"])
        XCTAssertEqual(fastest.first?.model.provider, "Cerebras")
        XCTAssertEqual(fastest.first?.model.speed?.value, 1700)
        XCTAssertEqual(text.first { $0.modelID == "gpt-oss-120b" && $0.provider == "Groq" }?.speed?.value, 400)
        XCTAssertEqual(fastest.map(\.rank), [1,2,3,4,5])
        XCTAssertNil(text.first { $0.modelID == "m6" }?.speed)
        XCTAssertEqual(snapshot.models.first { $0.task == "speech" }?.speed?.value, 100)
        XCTAssertEqual(snapshot.models.first { $0.task == "speech" }?.cost?.value, 3)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(requests[3].url?.query, "page=2")
        XCTAssertEqual(requests[5].url?.query, "page=2")
        for request in requests {
            XCTAssertEqual(request.url?.host, "artificialanalysis.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "fixture-aa-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.httpBody)
        }
    }
    func testV2FreeTierKeepsModelLevelTPSWithoutInventingHostIdentityOrSpeechCost() async throws {
        let transport = AAFixtureTransport([page("free", [model("one", 75)]),
            #"{"tier":"free","data":[{"id":"speech","name":"Speech","aa_wer_index":null}]}"#], legacyUnavailable: true)
        let snapshot = try await ArtificialAnalysisClient(transport: transport).fetch(key: "fixture")
        let model = try XCTUnwrap(snapshot.models.first { $0.task == "text" })
        XCTAssertEqual(model.quality[.intelligence]?.value, 75)
        XCTAssertEqual(model.speed?.value, 99999)
        XCTAssertEqual(model.provider, "AA reference")
        XCTAssertEqual(model.cost?.value, 1.5)
        XCTAssertNil(snapshot.models.first { $0.task == "speech" }?.cost)
        XCTAssertEqual(BenchmarkRanking.rank(snapshot.models, enabled: [.speed], quality: .intelligence).first?.model.provider, "AA reference")
        let requests = await transport.requests
        XCTAssertFalse(requests.contains { $0.url!.path.contains("providers") })
    }
    func testAuthenticationAndRateLimitFailuresDoNotLeakResponseOrCredentials() async {
        for status in [401,403,429,500] {
            let transport = AAFixtureTransport(["secret-response"], status: status)
            do {
                _ = try await ArtificialAnalysisClient(transport: transport).fetch(key: "secret-key")
                XCTFail("Expected failure")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("secret"))
            }
        }
    }
    func testSavedSnapshotRoundTripPreservesExactHostsAndDate() async throws {
        let now = Date(timeIntervalSince1970: 1234)
        let transport = AAFixtureTransport([page("free", [model("one", 75)]), #"{"tier":"free","data":[]}"#], legacyUnavailable: true)
        let result = try await ArtificialAnalysisClient(transport: transport).fetch(key: "fixture", now: now)
        let cached = try JSONDecoder().decode(ArtificialAnalysisSnapshot.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(cached.fetchedAt, now)
        XCTAssertEqual(cached.models.first?.provider, "AA reference")
        XCTAssertFalse(cached.speechAvailable)
        XCTAssertNotNil(cached.warning)
    }
    func testReferenceSpeedRanksFiveDistinctModelsAndKeepsCerebrasSpecific() {
        let models = BenchmarkCatalog.models(local: []).filter { $0.task == "text" }
        let top = BenchmarkRanking.top(BenchmarkRanking.rank(models, enabled: [.speed], quality: .intelligence))
        XCTAssertEqual(top.count, 5)
        XCTAssertEqual(Set(top.map { $0.model.modelID ?? $0.id }).count, 5)
        XCTAssertEqual(top.first?.model.name, "gpt-oss 120B")
        XCTAssertEqual(top.first?.model.provider, "Cerebras")
        XCTAssertTrue(models.filter { $0.provider == "Host unspecified" }.allSatisfy { $0.speed == nil })
        XCTAssertTrue(zip(top, top.dropFirst()).allSatisfy { $0.model.speed!.value >= $1.model.speed!.value })
    }
    func testDocumentedFreeEndpointUsesTopLevelTPSAndStableIDs() async throws {
        let data = #"{"status":200,"prompt_options":{"parallel_queries":1,"prompt_length":"medium"},"data":[{"id":"stable-oss","name":"gpt-oss 120B","slug":"gpt-oss-120b","model_creator":{"name":"OpenAI"},"evaluations":{"artificial_analysis_intelligence_index":62.9},"pricing":{"price_1m_blended_3_to_1":1.925},"median_output_tokens_per_second":153.831,"median_time_to_first_token_seconds":0.001},{"id":"stable-faster","name":"Faster","slug":"faster","evaluations":{"artificial_analysis_intelligence_index":40},"pricing":null,"median_output_tokens_per_second":200,"median_time_to_first_token_seconds":20}]}"#
        let transport = AAFixtureTransport([data, "{}", #"{"tier":"free","data":[]}"#], statuses: [200,403,200])
        let snapshot = try await ArtificialAnalysisClient(transport: transport).fetch(key: "fixture")
        let top = BenchmarkRanking.top(BenchmarkRanking.rank(snapshot.models, enabled: [.speed], quality: .intelligence))
        XCTAssertEqual(top.map { $0.model.modelID! }, ["stable-faster", "stable-oss"])
        XCTAssertEqual(top.last?.model.speed?.value, 153.831)
        XCTAssertEqual(top.last?.model.cost?.value, 1.925)
        XCTAssertEqual(top.last?.model.provider, "AA reference")
        XCTAssertNil(snapshot.indexVersion)
        XCTAssertFalse(snapshot.models.contains { $0.provider == "Cerebras" || $0.provider == "OpenAI" })
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://artificialanalysis.ai/api/v2/data/llms/models")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "x-api-key"), "fixture")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
    func testNullFreeTPSRemainsUnknown() async throws {
        let transport = AAFixtureTransport([#"{"status":200,"data":[{"id":"one","name":"One","slug":"one","evaluations":{},"median_output_tokens_per_second":null}]}"#, "{}", #"{"tier":"free","data":[]}"#], statuses: [200,403,200])
        let snapshot = try await ArtificialAnalysisClient(transport: transport).fetch(key: "fixture")
        XCTAssertNil(snapshot.models.first?.speed)
        XCTAssertTrue(BenchmarkRanking.rank(snapshot.models, enabled: [.speed], quality: .intelligence).isEmpty)
    }
    func testAAValidationUsesItsOwnHeader() async throws {
        let transport = AAFixtureTransport(["{}"])
        try await DictationAPI(transport: transport).validateKey("fixture-aa", account: .artificialAnalysis)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "x-api-key"), "fixture-aa")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
}
private actor AAFixtureTransport: HTTPTransport {
    var responses: [String]
    let status: Int
    var statuses: [Int]
    let legacyUnavailable: Bool
    private(set) var requests: [URLRequest] = []
    init(_ responses: [String], status: Int = 200, statuses: [Int] = [], legacyUnavailable: Bool = false) {
        self.responses = responses; self.status = status; self.statuses = statuses; self.legacyUnavailable = legacyUnavailable
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if legacyUnavailable, request.url!.path == "/api/v2/data/llms/models" {
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let status = statuses.isEmpty ? status : statuses.removeFirst()
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return (Data(responses.removeFirst().utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
