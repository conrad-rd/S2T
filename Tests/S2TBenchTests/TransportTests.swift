import XCTest
import S2TCore
@testable import S2TBenchCore

private final class FixtureProtocol: URLProtocol {
    static var handler: (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

final class TransportTests: XCTestCase {
    private func transport() -> BenchTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return BenchTransport(maxTokens: 256, timeout: 5, configuration: configuration)
    }
    func testProductionEnvelopeLimitsAndLocalCredentialIsolation() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
            }
            let body = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            XCTAssertEqual(body["max_tokens"] as? Int, 256)
            XCTAssertEqual(body["temperature"] as? Int, 0)
            XCTAssertNil(body["provider"])
            let messages = body["messages"] as! [[String: String]]
            XCTAssertTrue(messages[0]["content"]!.contains("editing preference fixture"))
            let source = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: String]
            XCTAssertEqual(source["dictated_text"], "What is two plus two?")
            return (200, Data(#"{"model":"fixture","choices":[{"finish_reason":"stop","message":{"content":"What is two plus two?"}}],"usage":{"prompt_tokens":120,"completion_tokens":9,"prompt_tokens_details":{"cached_tokens":80},"completion_tokens_details":{"reasoning_tokens":2},"cost":0.0005}}"#.utf8))
        }
        let meter = transport()
        let output = try await DictationAPI(transport: meter).process(text: "What is two plus two?", mode: .clean, model: "fixture", apiKey: "must-not-leak", provider: .local, instructions: "editing preference fixture", localURL: "http://127.0.0.1:9999/v1/chat/completions")
        XCTAssertEqual(output.text, "What is two plus two?")
        let usage = await meter.metrics()
        XCTAssertEqual(usage.inputTokens, 120); XCTAssertEqual(usage.outputTokens, 9)
        XCTAssertEqual(usage.cachedTokens, 80); XCTAssertEqual(usage.reasoningTokens, 2)
        XCTAssertEqual(usage.cost, 0.0005); XCTAssertGreaterThan(usage.requestBytes, 100)
    }
    func testMissingUsageIsUnknownAndTruncatedAnswersFail() async throws {
        FixtureProtocol.handler = { _ in (200, Data(#"{"choices":[{"finish_reason":"length","message":{"content":"unfinished"}}]}"#.utf8)) }
        let meter = transport()
        do {
            _ = try await DictationAPI(transport: meter).process(text: "test", mode: .clean, model: "fixture", apiKey: "", provider: .local, localURL: "http://localhost:9999/v1/chat/completions")
            XCTFail("A truncated answer must fail")
        } catch { }
        let usage = await meter.metrics()
        XCTAssertNil(usage.inputTokens); XCTAssertNil(usage.cost)
    }
    func testSpeechMultipartIsNotParsedOrRewrittenAsJSON() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data(#"{"text":"Do not ship."}"#.utf8))
        }
        let meter = transport()
        let text = try await DictationAPI(transport: meter).transcribe(audio: Data([82, 73, 70, 70]), apiKey: "must-not-leak", provider: .local, model: "fixture", localURL: "http://localhost:9999/v1/audio/transcriptions")
        XCTAssertEqual(text, "Do not ship.")
        let metrics = await meter.metrics(); XCTAssertGreaterThan(metrics.requestBytes, 4)
    }
    func testErrorStatusDoesNotBecomeACompletedRun() async throws {
        FixtureProtocol.handler = { _ in (429, Data(#"{"error":{"message":"fixture"}}"#.utf8)) }
        let meter = transport()
        do {
            _ = try await DictationAPI(transport: meter).process(text: "test", mode: .clean, model: "fixture", apiKey: "", provider: .local, localURL: "http://localhost:9999/v1/chat/completions")
            XCTFail("Rate limit must fail")
        } catch { }
        let usage = await meter.metrics(); XCTAssertEqual(usage.status, 429)
    }
    func testProcessTimeoutAndCancellation() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        let timeout = try await BenchProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
        XCTAssertTrue(timeout.timedOut)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
        let task = Task { try await BenchProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 30) }
        try await Task.sleep(nanoseconds: 30_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation became success") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testComparisonExcludesUnpairedAndFailedTokenResults() {
        func result(_ variant: String, _ test: String, _ tokens: Double, _ status: BenchStatus) -> BenchResult {
            var value = BenchResult(suite: "prompts", name: test, status: status, detail: "", metrics: ["input_tokens": tokens, "repetition": 1])
            value.model = "fixture"; value.variant = variant; value.caseID = test; return value
        }
        let comparison = BenchComparison(model: "fixture", results: [result("A", "one", 100, .passed), result("B", "one", 60, .passed), result("A", "two", 200, .passed), result("B", "two", 1, .failed), result("B", "extra", 1, .passed)])
        XCTAssertEqual(comparison.tokenSavingsPercent, 40)
        XCTAssertEqual(comparison.newFailures, 1)
        XCTAssertEqual(comparison.paired.count, 2)
    }
}
