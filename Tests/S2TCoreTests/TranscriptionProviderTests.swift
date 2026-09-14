import XCTest
@testable import S2TCore

final class TranscriptionProviderTests: XCTestCase {
    func testElevenLabsUploadsWAVWithItsOwnAuthentication() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/speech-to-text", status: 200, json: #"{"text":" Hello there. "}"#)])
        let audio = Data([0, 1, 2, 255])
        let result = try await DictationAPI(transport: transport).transcribe(audio: audio, apiKey: "eleven-fixture", provider: .elevenLabs)
        XCTAssertEqual(result, "Hello there.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.elevenlabs.io")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "eleven-fixture")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: audio))
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"dictation.wav\""))
        XCTAssertTrue(text.contains("name=\"tag_audio_events\"\r\n\r\nfalse"))
    }

    func testOpenRouterUsesTranscriptionEndpointAndSeparateModel() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/audio/transcriptions", status: 200, json: #"{"text":"Words."}"#)])
        let audio = Data([1, 2, 3])
        let result = try await DictationAPI(transport: transport).transcribe(audio: audio, apiKey: "router-fixture", provider: .openRouter, model: "openai/whisper-large-v3")
        XCTAssertEqual(result, "Words.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-fixture")
        XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "openai/whisper-large-v3")
        let input = try XCTUnwrap(body["input_audio"] as? [String: String])
        XCTAssertEqual(input, ["data": audio.base64EncodedString(), "format": "wav"])
        XCTAssertNil(body["messages"])
    }

    func testNewProvidersRejectEmptyAndMalformedTranscriptsAndRouteAccountErrors() async throws {
        for provider in [TranscriptionProvider.elevenLabs, .openRouter] {
            let path = provider == .elevenLabs ? "/v1/speech-to-text" : "/api/v1/audio/transcriptions"
            for json in [#"{"text":"  "}"#, "{}", "invalid"] {
                let transport = ScriptedTransport([.init(path: path, status: 200, json: json)])
                do {
                    _ = try await DictationAPI(transport: transport).transcribe(audio: Data(), apiKey: "fixture", provider: provider)
                    XCTFail("Expected invalid transcript to fail")
                } catch { XCTAssertTrue(error is ServiceError) }
            }
            for status in [401, 402, 403] {
                let transport = ScriptedTransport([.init(path: path, status: status, json: #"{"detail":"secret"}"#)])
                do {
                    _ = try await DictationAPI(transport: transport).transcribe(audio: Data(), apiKey: "fixture", provider: provider)
                    XCTFail("Expected account failure")
                } catch {
                    XCTAssertEqual(error as? ServiceError, .account(try XCTUnwrap(provider.account), status: status))
                    XCTAssertFalse(error.localizedDescription.contains("secret"))
                }
            }
        }
    }

    func testElevenLabsKeyCheckIsReadOnlyAndUsesXiAPIKey() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/user", status: 200, json: "{}")])
        try await DictationAPI(transport: transport).validateKey("eleven-fixture", account: .elevenLabs)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.elevenlabs.io")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "eleven-fixture")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.httpBody)
    }
}
