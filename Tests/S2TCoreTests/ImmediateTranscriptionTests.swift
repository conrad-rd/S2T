import XCTest
@testable import S2TCore

final class ImmediateTranscriptionTests: XCTestCase {
    func testShortDictationUsesOneRequestAndPreservesAudioAndKey() async throws {
        let wav = WaveAudio.encode(samples: Array(repeating: 120, count: 16000), sampleRate: 16000)
        let transport = ScriptedTransport([.init(path: "/v1/transcribe", status: 200, json: #"{"text":"Hallo Welt."}"#)])
        let text = try await DictationAPI(transport: transport).transcribe(audio: wav, apiKey: "user-key")
        XCTAssertEqual(text, "Hallo Welt.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.host, "sync.assemblyai.com")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "user-key")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-AAI-Model"), "universal-3-5-pro")
        XCTAssertNotNil(requests[0].httpBody?.range(of: wav))
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    func testLongRecordingsAndUnsupportedRatesUseBatchPath() {
        XCTAssertTrue(WaveAudio.supportsImmediateTranscription(WaveAudio.encode(samples: Array(repeating: 0, count: 16000 * 120), sampleRate: 16000)))
        XCTAssertFalse(WaveAudio.supportsImmediateTranscription(WaveAudio.encode(samples: Array(repeating: 0, count: 16000 * 120 + 1), sampleRate: 16000)))
        XCTAssertFalse(WaveAudio.supportsImmediateTranscription(WaveAudio.encode(samples: Array(repeating: 0, count: 96000), sampleRate: 96000)))
        XCTAssertFalse(WaveAudio.supportsImmediateTranscription(Data([0, 1, 2])))
    }

    func testEmptySpeechIsAnErrorInsteadOfSuccessfulEmptyPaste() async {
        let transport = ScriptedTransport([.init(path: "/v1/transcribe", status: 200, json: #"{"text":"   "}"#)])
        do {
            _ = try await DictationAPI(transport: transport).transcribeImmediately(audio: Data(), apiKey: "key")
            XCTFail("Expected no-speech error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No speech")) }
    }

    func testConnectionWarmupContainsNoCredentialsOrAudio() async {
        let transport = ScriptedTransport([.init(path: "/warm", status: 200, json: #"{"warm":"toasty"}"#)])
        await DictationAPI(transport: transport).warmTranscriptionConnection()
        let requests = await transport.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[0].httpBody)
    }
    func testMissingSyncRouteFallsBackOnceToBatchWithoutLosingAudio() async throws {
        let wav = WaveAudio.encode(samples: Array(repeating: 120, count: 16000), sampleRate: 16000)
        let transport = ScriptedTransport([
            .init(path: "/v1/transcribe", status: 404, json: "{}"),
            .init(path: "/v2/upload", status: 200, json: #"{"upload_url":"https://cdn.assemblyai.com/fixture"}"#),
            .init(path: "/v2/transcript", status: 200, json: #"{"id":"fixture","status":"completed","text":"Recovered words."}"#)
        ])
        let result = try await DictationAPI(transport: transport).transcribe(audio: wav, apiKey: "fixture")
        XCTAssertEqual(result, "Recovered words.")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].httpBody, wav)
        let submitted = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[2].httpBody!) as? [String: Any])
        XCTAssertEqual(submitted["speech_models"] as? [String], ["universal-3-5-pro", "universal-2"])
    }

    func testSyncServerFailureDoesNotStartAnotherPotentiallyBilledRequest() async {
        let wav = WaveAudio.encode(samples: Array(repeating: 120, count: 16000), sampleRate: 16000)
        let transport = ScriptedTransport([.init(path: "/v1/transcribe", status: 500, json: "{}")])
        do { _ = try await DictationAPI(transport: transport).transcribe(audio: wav, apiKey: "fixture"); XCTFail("Must fail") }
        catch { }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    func testCompletedSilentBatchStopsWithoutAnotherPoll() async {
        let transport = ScriptedTransport([
            .init(path: "/v2/upload", status: 200, json: #"{"upload_url":"https://cdn.assemblyai.com/fixture"}"#),
            .init(path: "/v2/transcript", status: 200, json: #"{"id":"fixture","status":"completed","text":" "}"#)
        ])
        do {
            _ = try await DictationAPI(transport: transport).transcribe(audio: Data([1]), apiKey: "fixture")
            XCTFail("Silent recording accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("No speech")) }
        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
    }

}
