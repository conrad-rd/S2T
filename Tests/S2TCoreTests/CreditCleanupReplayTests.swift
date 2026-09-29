import XCTest
@testable import S2TCore

final class CreditCleanupReplayTests: XCTestCase {
    func testRestartReplaysExactPaidBodyAndResolvesOriginalClipboard() async throws {
        let connection = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "a", count: 64))
        var clipboard = ClipboardHistory()
        clipboard.record("Original copied material")
        let context = clipboard.context(for: "Include the copied text")
        let request = try CreditCleanupRequest(text: "Include the copied text", mode: .clean, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: connection,
            clipboardContext: context, instructions: "Preserve names", requestID: "immutable-cleanup")
        let transport = ReplayCleanupTransport(text: context.items[0].placeholder)
        let api = CreditsAPI(transport: transport)
        _ = try await api.process(request, connection: connection)
        var recovery = RecordingRecovery(audio: Data([1]), requestID: "immutable", mode: .clean)
        recovery.creditCleanupRequest = request
        let restored = try JSONDecoder().decode(RecordingRecovery.self, from: JSONEncoder().encode(recovery))
        clipboard.record("New clipboard copied during interruption")
        let newContext = clipboard.context(for: "Include the copied text")
        XCTAssertNotEqual(newContext.prompt, context.prompt)
        let result = try await api.process(XCTUnwrap(restored.creditCleanupRequest), connection: connection)
        XCTAssertEqual(result.text, "Original copied material")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Idempotency-Key"), requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        let other = try CreditConnection(address: "http://localhost:4317", key: "s2t_demo_" + String(repeating: "b", count: 64))
        do { _ = try await api.process(request, connection: other); XCTFail("Account change must not resubmit the pending paid request") } catch { }
        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
    }
}

private actor ReplayCleanupTransport: HTTPTransport {
    let text: String
    var requests: [URLRequest] = []
    init(text: String) { self.text = text }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let data = try JSONSerialization.data(withJSONObject: ["state": "settled", "result": ["text": text, "model": "openai/gpt-oss-120b"]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
