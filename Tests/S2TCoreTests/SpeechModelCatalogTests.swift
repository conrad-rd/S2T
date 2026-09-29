import XCTest
@testable import S2TCore

final class SpeechModelCatalogTests: XCTestCase {
    func testLoadsOnlyTranscriptionModelsWithoutCredentials() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/models", status: 200, json: #"{"data":[{"id":"openai/whisper-1","name":"Whisper","architecture":{"output_modalities":["transcription"]}},{"id":"example/chat","name":"Chat","architecture":{"output_modalities":["text"]}},{"id":"openai/whisper-1","name":"Duplicate","architecture":{"output_modalities":["transcription"]}}]}"#)])
        let models = try await SpeechModelCatalog.load(transport: transport)
        XCTAssertEqual(models.map(\.id), ["openai/whisper-1"])
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.query, "output_modalities=transcription")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRejectsFailedEmptyAndMalformedCatalogs() async {
        for (status, json) in [(503, "{}"), (200, #"{"data":[]}"#), (200, "invalid")] {
            let transport = ScriptedTransport([.init(path: "/api/v1/models", status: status, json: json)])
            do {
                _ = try await SpeechModelCatalog.load(transport: transport)
                XCTFail("Unavailable catalogs must expose a retryable error")
            } catch {}
        }
    }
}
