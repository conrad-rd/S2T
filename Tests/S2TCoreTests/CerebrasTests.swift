import XCTest
@testable import S2TCore

final class CerebrasTests: XCTestCase {
    func testDirectCerebrasRequestUsesItsOwnHostKeyAndModel() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200, json: #"{"model":"qwen-3.8-27b","choices":[{"finish_reason":"stop","message":{"content":"Hallo Welt.","reasoning":"Not part of the transcript"}}]}"#)])
        let result = try await DictationAPI(transport: transport).process(text: "äh hallo welt", mode: .clean, model: "qwen-3.8-27b", apiKey: "cerebras-test-key", provider: .cerebras)
        XCTAssertEqual(result.text, "Hallo Welt.")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.cerebras.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cerebras-test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen-3.8-27b")
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertEqual(body["stream"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        let source = try JSONDecoder().decode([String: String].self, from: Data(try XCTUnwrap(messages.last?["content"]).utf8))
        XCTAssertEqual(source, ["dictated_text": "äh hallo welt"])
    }

    func testSwitchingProvidersKeepsCredentialsOnTheirOwnHosts() async throws {
        let response = #"{"choices":[{"finish_reason":"stop","message":{"content":"Done."}}]}"#
        let transport = ScriptedTransport([
            .init(path: "/api/v1/chat/completions", status: 200, json: response),
            .init(path: "/v1/chat/completions", status: 200, json: response)
        ])
        let api = DictationAPI(transport: transport)
        _ = try await api.process(text: "one", mode: .clean, model: "openrouter/auto", apiKey: "router-only")
        _ = try await api.process(text: "two", mode: .clean, model: "gpt-oss-120b", apiKey: "cerebras-only", provider: .cerebras)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url?.host }, ["openrouter.ai", "api.cerebras.ai"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer router-only", "Bearer cerebras-only"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertNil(body["reasoning_effort"])
    }

    func testWrongProviderModelIsRejectedBeforeSendingTranscript() async {
        let transport = ScriptedTransport([])
        do {
            _ = try await DictationAPI(transport: transport).process(text: "private transcript", mode: .clean, model: "openrouter/auto", apiKey: "test", provider: .cerebras)
            XCTFail("Expected a Cerebras model identifier error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Cerebras")) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testCerebrasAuthenticationErrorDoesNotExposeKeyOrResponse() async {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 401, json: #"{"error":"secret-provider-content"}"#)])
        do {
            _ = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "qwen-3.8-27b", apiKey: "private-key", provider: .cerebras)
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Cerebras"))
            XCTAssertFalse(error.localizedDescription.contains("secret-provider-content"))
            XCTAssertFalse(error.localizedDescription.contains("private-key"))
        }
    }

    func testCerebrasIncompleteOutputPreservesOriginal() async {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#)])
        do {
            _ = try await DictationAPI(transport: transport).process(text: "original", mode: .clean, model: "qwen-3.8-27b", apiKey: "test", provider: .cerebras)
            XCTFail("Must reject incomplete text")
        } catch { XCTAssertTrue(error.localizedDescription.contains("original transcript is preserved")) }
    }
}
