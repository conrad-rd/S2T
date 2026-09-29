import XCTest
@testable import S2TCore

final class XAITests: XCTestCase {
    func testGrokClipboardReferenceKeepsTheKeyLocal() {
        var history = ClipboardHistory()
        let date = Date()
        let secret = "xai-" + String(repeating: "a", count: 40)
        history.record(secret, at: date)
        let context = history.context(for: "Use this Grok API key", at: date)
        XCTAssertEqual(context.items.count, 1)
        XCTAssertEqual(context.items.first?.value, secret)
        XCTAssertFalse(context.prompt.contains(secret))
    }

    func testSpeechModelsUseXAIUploadAndWordTimestamps() async throws {
        for model in TranscriptionProvider.xaiModels {
            let transport = ScriptedTransport([.init(path: "/v1/stt", status: 200, json: #"{"text":"Hello there.","duration":1.2,"words":[{"text":"Hello","start":0.1,"end":0.6},{"text":"there.","start":0.7,"end":1.1}]}"#)])
            let result = try await DictationAPI(transport: transport).transcribeDetailed(audio: Data("audio-fixture".utf8), apiKey: "xai-only-fixture", provider: .xai, model: model, includeTimestamps: true)
            XCTAssertEqual(result.text, "Hello there.")
            XCTAssertEqual(result.words.map(\.start), [0.1, 0.7])
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.host, "api.x.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-only-fixture")
            let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            let modelRange = try XCTUnwrap(body.range(of: model))
            let fileRange = try XCTUnwrap(body.range(of: "name=\"file\""))
            XCTAssertLessThan(modelRange.lowerBound, fileRange.lowerBound)
            XCTAssertTrue(body.contains("audio-fixture"))
            XCTAssertFalse(body.contains("response_format"))
        }
        XCTAssertFalse(TranscriptionProvider.xai.validModelID("grok-4.6"))
        XCTAssertEqual(TranscriptionProvider.xai.defaultModel, "grok-voice-transcribe-2.0")
    }

    func testXAISpeechRejectsSilenceAndReportsItsAccountFailure() async throws {
        for status in [200, 401] {
            let transport = ScriptedTransport([.init(path: "/v1/stt", status: status, json: #"{"text":" "}"#)])
            do {
                _ = try await DictationAPI(transport: transport).transcribe(audio: Data(), apiKey: "fixture", provider: .xai)
                XCTFail("Empty or rejected transcription succeeded")
            } catch {
                if status == 401 { XCTAssertEqual(error as? ServiceError, .account(.xai, status: 401)) }
                else { XCTAssertTrue(error.localizedDescription.contains("No speech")) }
            }
        }
    }

    func testSubscriptionRoutesXAISpeechWithoutSendingThePersonalKey() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/requests", status: 200, json: #"{"state":"settled","result":{"text":"Hello.","model":"grok-voice-transcribe-2.0","host":"xai"}}"#)])
        let key = "s2t_demo_" + String(repeating: "a", count: 64)
        let audio = WaveAudio.encode(samples: Array(repeating: 120, count: 16000), sampleRate: 16000)
        let result = try await CreditsAPI(transport: transport).transcribe(audio: audio, provider: .xai, model: TranscriptionProvider.xai.defaultModel, endpoint: nil, connection: CreditConnection(address: "http://localhost:4317", key: key))
        XCTAssertEqual(result.text, "Hello.")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["provider"], "xai")
        XCTAssertEqual(body["model"], "grok-voice-transcribe-2.0")
        XCTAssertEqual(Data(base64Encoded: body["audio"] ?? ""), audio)
    }

    func testCleanupDoesNotSendOpenRouterRouting() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200, json: #"{"model":"grok-4.6","choices":[{"finish_reason":"stop","message":{"content":"Hello."}}]}"#)])
        let result = try await DictationAPI(transport: transport).process(text: "hello", mode: .clean, model: "grok-4.6", apiKey: "xai-fixture", provider: .xai, endpoint: "cerebras/fp16")
        XCTAssertEqual(result.text, "Hello.")
        XCTAssertEqual(result.host, "xAI")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.x.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xai-fixture")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertNil(body["provider"])
        XCTAssertNil(body["reasoning"])
        XCTAssertNotEqual(ProcessingProvider.xai.modelPreferenceKey, ProcessingProvider.openRouter.modelPreferenceKey)
    }

    func testSubscriptionUsesItsOwnConnectionAndXAIProvider() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/requests", status: 200, json: #"{"state":"settled","result":{"text":"Hello.","model":"grok-4.6","host":"xai"}}"#)])
        let key = "s2t_demo_" + String(repeating: "a", count: 64)
        let result = try await CreditsAPI(transport: transport).process(text: "hello", mode: .clean, model: "grok-4.6", endpoint: "cerebras/fp16", connection: CreditConnection(address: "http://localhost:4317", key: key), clipboardContext: ClipboardContext(), instructions: nil, provider: .xai)
        XCTAssertEqual(result.text, "Hello.")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body["provider"], "xai")
        XCTAssertEqual(body["host"], "")
        XCTAssertNil(body["reasoning"])
        XCTAssertNil(body["allowDataCollection"])
    }

    func testReadOnlyKeyValidationAndAccountFailure() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/models", status: 401, json: "{}")])
        do {
            try await DictationAPI(transport: transport).validateKey("xai-fixture", account: .xai)
            XCTFail("Invalid key accepted")
        } catch {
            XCTAssertEqual(error as? ServiceError, .account(.xai, status: 401))
        }
    }
}
