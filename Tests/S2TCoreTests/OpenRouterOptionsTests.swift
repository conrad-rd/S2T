import XCTest
@testable import S2TCore

final class OpenRouterOptionsTests: XCTestCase {
    func testSavedGPTOSSReasoningIsSentWithoutSilentChanges() async throws {
        for model in ["openai/gpt-oss-120b", "openai/gpt-oss-20b"] {
            for saved in [OpenRouterOptions.Effort.none, .minimal, .max, .xhigh] {
                let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: response)])
                _ = try await DictationAPI(transport: transport).process(text: "Fixture.", mode: .clean, model: model, apiKey: "fixture", endpoint: "cerebras/fp16", routerOptions: OpenRouterOptions(reasoning: saved))
                let requests = await transport.requests
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
                XCTAssertEqual((body["reasoning"] as? [String: String])?["effort"], saved.rawValue)
                XCTAssertEqual(body["model"] as? String, model)
                XCTAssertEqual((body["provider"] as? [String: Any])?["only"] as? [String], ["cerebras/fp16"])
            }
        }
    }
    private let response = #"{"choices":[{"finish_reason":"stop","message":{"content":"Done."}}]}"#

    func testReasoningAndFastRoutingReachTheRequest() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: response)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "openai/gpt-oss-120b", apiKey: "fixture",
            routerOptions: OpenRouterOptions(reasoning: .low, fast: true))
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertEqual((body["provider"] as? [String: Any])?["sort"] as? String, "throughput")
        XCTAssertEqual((body["provider"] as? [String: Any])?["data_collection"] as? String, "deny")
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
    }

    func testPinnedHostOverridesFastRouting() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: response)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "vendor/model", apiKey: "fixture",
            endpoint: "cerebras/fp16", routerOptions: OpenRouterOptions(reasoning: .high, fast: true))
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        let routing = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(routing["only"] as? [String], ["cerebras/fp16"])
        XCTAssertEqual(routing["allow_fallbacks"] as? Bool, false)
        XCTAssertEqual(routing["data_collection"] as? String, "deny")
        XCTAssertNil(routing["sort"])
    }

    func testOtherProvidersIgnoreRouterOptions() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200, json: response)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "gpt-oss-120b", apiKey: "fixture", provider: .local, localURL: LocalEndpoint.defaultProcessingURL,
            routerOptions: OpenRouterOptions(reasoning: .high, fast: true))
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertNil(body["reasoning"])
        XCTAssertNil(body["provider"])
    }

    func testDefaultRoutingExcludesDataCollection() {
        var body: [String: Any] = [:]
        OpenRouterOptions().apply(to: &body)
        let routing = body["provider"] as? [String: String]
        XCTAssertEqual(routing, ["data_collection": "deny"])
    }


}

extension OpenRouterOptionsTests {
    func testContributorConsentDefaultsOffAndCannotAffectOtherModels() throws {
        let legacy = try JSONDecoder().decode(OpenRouterOptions.self, from: Data(#"{"reasoning":"low","fast":true}"#.utf8))
        XCTAssertFalse(legacy.allowDataCollection)
        let options = OpenRouterOptions(allowDataCollection: true)
        var contributor: [String: Any] = ["model": OpenRouterOptions.contributorModel]
        options.apply(to: &contributor)
        XCTAssertEqual((contributor["provider"] as? [String: Any])?["data_collection"] as? String, "allow")
        var ordinary: [String: Any] = ["model": "openai/gpt-oss-120b"]
        options.apply(to: &ordinary)
        XCTAssertEqual((ordinary["provider"] as? [String: Any])?["data_collection"] as? String, "deny")
    }
}
