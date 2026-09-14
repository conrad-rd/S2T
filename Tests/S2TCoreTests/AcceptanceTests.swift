import XCTest
@testable import S2TCore

final class AcceptanceTests: XCTestCase {
    func testRecordingBecomesAStandardMonoPCM16WaveFile() {
        let wav = WaveAudio.encode(samples: [0, 32767, -32768], sampleRate: 48000)
        XCTAssertEqual(wav.count, 50)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(Array(wav[22..<24]), [1, 0])
        XCTAssertEqual(Array(wav[24..<28]), [128, 187, 0, 0])
        XCTAssertEqual(Array(wav[40..<44]), [6, 0, 0, 0])
        XCTAssertEqual(Array(wav.suffix(6)), [0, 0, 255, 127, 0, 128])
    }

    func testFullProviderWorkflowUsesSeparateCredentialsAndPreservesLanguage() async throws {
        let transport = ScriptedTransport([
            .init(path: "/v2/upload", status: 200, json: #"{"upload_url":"https://cdn.assemblyai.com/recording"}"#),
            .init(path: "/v2/transcript", status: 200, json: #"{"id":"job-1","status":"queued"}"#),
            .init(path: "/v2/transcript/job-1", status: 200, json: #"{"id":"job-1","status":"processing"}"#),
            .init(path: "/v2/transcript/job-1", status: 200, json: #"{"id":"job-1","status":"completed","text":"äh hallo welt"}"#),
            .init(path: "/api/v1/chat/completions", status: 200, json: #"{"model":"provider/actual","choices":[{"message":{"content":"Hallo Welt."},"finish_reason":"stop"}]}"#)
        ])
        let api = DictationAPI(transport: transport, pollInterval: 0, maxPolls: 3)
        let transcript = try await api.transcribe(audio: Data([0, 1]), apiKey: "assembly-test")
        let result = try await api.process(text: transcript, mode: .clean, model: "provider/selected", apiKey: "router-test")
        XCTAssertEqual(result.text, "Hallo Welt.")
        XCTAssertEqual(result.model, "provider/actual")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "assembly-test")
        XCTAssertEqual(requests[4].value(forHTTPHeaderField: "Authorization"), "Bearer router-test")
        let submission = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertEqual(submission["language_detection"] as? Bool, true)
        let completion = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[4].httpBody!) as? [String: Any])
        XCTAssertEqual(completion["model"] as? String, "provider/selected")
        XCTAssertTrue(String(data: requests[4].httpBody!, encoding: .utf8)!.contains("äh hallo welt"))
    }

    func testUnauthorizedKeyProducesActionableErrorWithoutEchoingResponse() async {
        let transport = ScriptedTransport([.init(path: "/v2/upload", status: 401, json: #"{"error":"secret-key-from-provider"}"#)])
        do {
            _ = try await DictationAPI(transport: transport).transcribe(audio: Data([1]), apiKey: "private-key")
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("AssemblyAI"))
            XCTAssertTrue(error.localizedDescription.contains("API key"))
            XCTAssertFalse(error.localizedDescription.contains("private-key"))
            XCTAssertFalse(error.localizedDescription.contains("secret-key"))
        }
    }

    func testProcessingRefusesTruncatedOutput() async {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#)])
        do {
            _ = try await DictationAPI(transport: transport).process(text: "original", mode: .clean, model: "provider/model", apiKey: "test")
            XCTFail("Must not silently replace original with truncated output")
        } catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
    }

    func testPollingHasAnUpperBound() async {
        let transport = ScriptedTransport([
            .init(path: "/v2/upload", status: 200, json: #"{"upload_url":"https://cdn.assemblyai.com/recording"}"#),
            .init(path: "/v2/transcript", status: 200, json: #"{"id":"job-2","status":"queued"}"#),
            .init(path: "/v2/transcript/job-2", status: 200, json: #"{"id":"job-2","status":"processing"}"#)
        ])
        do {
            _ = try await DictationAPI(transport: transport, pollInterval: 0, maxPolls: 1).transcribe(audio: Data([1]), apiKey: "test")
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("longer")) }
    }


}

actor ScriptedTransport: HTTPTransport {
    struct Response {
        let path: String
        let status: Int
        let json: String
    }
    var responses: [Response]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [Response]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let next = responses.removeFirst()
        XCTAssertEqual(request.url?.path, next.path)
        return (Data(next.json.utf8), HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil)!)
    }
}
