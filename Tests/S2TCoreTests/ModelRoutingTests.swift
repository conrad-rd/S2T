import XCTest
@testable import S2TCore

final class ModelRoutingTests: XCTestCase {
    func testCerebrasEndpointCannotBeSavedAsAModel() {
        XCTAssertFalse(ProcessingProvider.openRouter.validModelID("cerebras/fp16"))
        XCTAssertTrue(ProcessingProvider.openRouter.validModelID("openai/gpt-oss-120b"))
    }

    func testActualModelAndHostAreReported() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200,
            json: #"{"model":"openai/gpt-oss-120b","provider":"Cerebras","choices":[{"finish_reason":"stop","message":{"content":"Edited."}}]}"#)])
        let result = try await DictationAPI(transport: transport).process(text: "um edited", mode: .clean,
            model: "openai/gpt-oss-120b", apiKey: "fixture", endpoint: "cerebras/fp16")
        XCTAssertEqual(result.model, "openai/gpt-oss-120b")
        XCTAssertEqual(result.host, "Cerebras")
    }

    func testEndpointDefaultIsOnlyForOpenRouter() {
        XCTAssertEqual(ProcessingProvider.openRouter.defaultEndpoint, "cerebras/fp16")
        XCTAssertEqual(ProcessingProvider.openRouter.defaultModel, "openai/gpt-oss-120b")
        XCTAssertNil(ProcessingProvider.cerebras.defaultEndpoint)
    }

    func testSelectedModelAndExactEndpointReachOpenRouterWithoutDiscovery() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200,
            json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Done."}}]}"#)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean,
            model: "provider/selected", apiKey: "router-fixture", endpoint: "cerebras/fp16")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "provider/selected")
        let route = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(route["only"] as? [String], ["cerebras/fp16"])
        XCTAssertEqual(route["allow_fallbacks"] as? Bool, false)
    }

    func testOtherProvidersDoNotReceiveOpenRouterEndpointSettings() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200,
            json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Done."}}]}"#)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean,
            model: "gpt-oss-120b", apiKey: "cerebras-fixture", provider: .cerebras, endpoint: "cerebras/fp16")
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-oss-120b")
        XCTAssertNil(body["provider"])
    }

    func testClearedEndpointDoesNotAddProviderRestrictions() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200,
            json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Done."}}]}"#)])
        _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean,
            model: "provider/selected", apiKey: "fixture", endpoint: " ")
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertNil(body["provider"])
    }
}
