import XCTest
@testable import S2TCore

final class TranscriptionProviderTests: XCTestCase {
    func testOnlySupportedProvidersAndAccountsAreAvailable() {
        XCTAssertEqual(Set(TranscriptionProvider.allCases.map(\.rawValue)), ["assemblyai", "openrouter", "local", "xai"])
        XCTAssertEqual(Set(APIAccount.allCases.map(\.rawValue)), ["assemblyai", "openrouter", "xai", "typesafe", "artificialanalysis"])
        XCTAssertNil(TranscriptionProvider(rawValue: "elevenlabs"))
        XCTAssertNil(APIAccount(rawValue: "elevenlabs"))
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

    func testOpenRouterRejectsInvalidTranscriptsAndRoutesAccountErrors() async throws {
        for provider in [TranscriptionProvider.openRouter] {
            let path = "/api/v1/audio/transcriptions"
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

}
