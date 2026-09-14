import XCTest
@testable import S2TCore

final class LocalEndpointTests: XCTestCase {
    func testLocalCleanupUsesSelectedURLModelAndNoCloudCredentialsOrRouting() async throws {
        let transport = ScriptedTransport([.init(path: "/custom/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Clean words."}}],"model":"loaded-model"}"#)])
        let result = try await DictationAPI(transport: transport).process(text: "words", mode: .clean,
            model: "org/model:latest", apiKey: "cloud-secret", provider: .local, endpoint: "cerebras/fp16",
            localURL: "http://127.0.0.1:1234/custom/chat/completions")
        XCTAssertEqual(result.text, "Clean words.")
        XCTAssertEqual(result.model, "loaded-model")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:1234/custom/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "org/model:latest")
        XCTAssertNil(body["provider"])
        XCTAssertNil(body["reasoning_effort"])
    }

    func testLocalSpeechUsesOpenAIMultipartAndPreservesAudio() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/audio/transcriptions", status: 200, json: #"{"text":" Spoken words. "}"#)])
        let audio = Data([0, 255, 13, 10, 128])
        let result = try await DictationAPI(transport: transport).transcribe(audio: audio, apiKey: "cloud-secret",
            provider: .local, model: "whisper/large-v3", localURL: "http://[::1]:8080/v1/audio/transcriptions")
        XCTAssertEqual(result, "Spoken words.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.port, 8080)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: audio))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\nwhisper/large-v3"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"dictation.wav\""))
        XCTAssertFalse(text.contains("model_id"))
        XCTAssertFalse(text.contains("cloud-secret"))
    }

    func testInvalidEndpointsNeverSendAndLocalFailuresNeverFallBack() async throws {
        for url in ["", "file:///tmp/model", "http://user:secret@localhost/v1", "http://localhost/v1?key=secret", "http://localhost/v1#fragment"] {
            let transport = ScriptedTransport([])
            do {
                _ = try await DictationAPI(transport: transport).transcribe(audio: Data(), apiKey: "", provider: .local, localURL: url)
                XCTFail("Accepted invalid URL")
            } catch {}
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        }
        for response in ["{}", #"{"text":" "}"#] {
            let transport = ScriptedTransport([.init(path: "/transcribe", status: 200, json: response)])
            do {
                _ = try await DictationAPI(transport: transport).transcribe(audio: Data(), apiKey: "", provider: .local, localURL: "http://localhost/transcribe")
                XCTFail("Accepted missing transcript")
            } catch {}
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }
}
