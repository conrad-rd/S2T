import XCTest
@testable import S2TCore

final class CerebrasTests: XCTestCase {
    func testLegacyCerebrasRawValueHasNoDirectProvider() {
        XCTAssertNil(ProcessingProvider(rawValue: "cerebras"))
        XCTAssertNil(APIAccount(rawValue: "cerebras"))
        XCTAssertNil(TranscriptionProvider(rawValue: "cerebras"))
    }

    func testOpenRouterStillRoutesThroughCerebrasEndpoint() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200,
            json: #"{"model":"openai/gpt-oss-120b","provider":"Cerebras","choices":[{"finish_reason":"stop","message":{"content":"Edited."}}]}"#)])
        let result = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean,
            model: "openai/gpt-oss-120b", apiKey: "router-fixture", endpoint: "cerebras/fp16")
        XCTAssertEqual(result.host, "Cerebras")
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "openai/gpt-oss-120b")
        let route = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(route["only"] as? [String], ["cerebras/fp16"])
        XCTAssertEqual(route["allow_fallbacks"] as? Bool, false)
    }

    func testCreditsPassSelectedHostToServiceForPolicyValidation() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/requests", status: 400,
            json: #"{"error":"This model and host are not available with S2T."}"#)])
        let key = "s2t_demo_" + String(repeating: "a", count: 64)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        do {
            _ = try await CreditsAPI(transport: transport).process(text: "hello", mode: .clean,
                model: "openai/gpt-oss-120b", endpoint: "other/host", connection: connection,
                clipboardContext: ClipboardContext(), instructions: nil)
            XCTFail("Service must enforce its available hosts")
        } catch { XCTAssertTrue(error.localizedDescription.contains("not available")) }
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertEqual(body["host"], "other/host")
    }
}
