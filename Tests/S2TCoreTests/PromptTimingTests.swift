import XCTest
@testable import S2TCore

final class PromptTimingTests: XCTestCase {
    func testTwelveRapidReferencesAreAllMatchedToFinalWordTimes() {
        let words = (0..<12).map { TimedWord(text: "here", start: Double($0) * 0.3, end: Double($0) * 0.3 + 0.15) }
        let references = PromptTiming.references(transcript: Array(repeating: "here", count: 12).joined(separator: ", "), words: words)
        XCTAssertEqual(references.count, 12)
        XCTAssertEqual(references.compactMap(\.seconds), words.map(\.start))
        XCTAssertTrue(references.allSatisfy { !$0.approximate })
    }

    func testFinalTranscriptCorrectsLocalRecognitionUsingNeighboringTimes() {
        let words = [TimedWord(text: "zoom", start: 1, end: 1.2), TimedWord(text: "in", start: 1.2, end: 1.4), TimedWord(text: "dear", start: 1.4, end: 1.7), TimedWord(text: "showing", start: 1.8, end: 2), TimedWord(text: "notch", start: 2, end: 2.4)]
        let reference = PromptTiming.references(transcript: "Zoom in here showing notch.", words: words)
        XCTAssertEqual(reference.count, 1)
        XCTAssertEqual(reference[0].seconds!, 1.6, accuracy: 0.001)
        XCTAssertTrue(reference[0].approximate)
    }

    func testMissingWordsOrLongGapsNeverInventCaptureTimes() {
        XCTAssertNil(PromptTiming.references(transcript: "look here", words: []).first?.seconds)
        let words = [TimedWord(text: "before", start: 1, end: 2), TimedWord(text: "after", start: 9, end: 10)]
        XCTAssertNil(PromptTiming.references(transcript: "before here after", words: words).first?.seconds)
        XCTAssertTrue(PromptTiming.references(transcript: "Don't look here", words: words).isEmpty)
    }

    func testFrameSelectionUsesAudioOriginAndRejectsStaleOrAbsentFrames() {
        let times = [100.0, 100.25, 100.5, 100.75]
        XCTAssertEqual(PromptTiming.nearestFrame(to: 100 + 0.4, times: times), 2)
        XCTAssertNil(PromptTiming.nearestFrame(to: 5, times: times))
        XCTAssertNil(PromptTiming.nearestFrame(to: 101.5, times: times))
        XCTAssertNil(PromptTiming.nearestFrame(to: .nan, times: times))
        XCTAssertNil(PromptTiming.nearestFrame(to: 1, times: []))
    }

    func testTimestampOptionsAreOptInAndAssemblyMillisecondsBecomeSeconds() async throws {
        let audio = WaveAudio.encode(samples: Array(repeating: 0, count: 16000), sampleRate: 16000)
        let response = ScriptedTransport.Response(path: "/transcribe", status: 200, json: #"{"text":"look here","words":[{"text":"look","start":120,"end":300},{"text":"here","start":350,"end":620}]}"#)
        let transport = ScriptedTransport([response, response])
        let api = DictationAPI(transport: transport)
        let result = try await api.transcribeDetailed(audio: audio, apiKey: "fixture", includeTimestamps: true)
        XCTAssertEqual(result.words, [.init(text: "look", start: 0.12, end: 0.3), .init(text: "here", start: 0.35000000000000003, end: 0.62)])
        _ = try await api.transcribe(audio: audio, apiKey: "fixture")
        let requests = await transport.requests
        XCTAssertTrue(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("{\"timestamps\":true}"))
        XCTAssertFalse(String(decoding: requests[1].httpBody!, as: UTF8.self).contains("name=\"config\""))
        XCTAssertNotNil(requests[0].httpBody?.range(of: audio))
    }

    func testElevenLabsSecondTimestampsAndMalformedEntriesPreserveText() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/speech-to-text", status: 200, json: #"{"text":"here","words":[{"text":"here","start":1.2,"end":1.5},{"text":"bad","start":"unknown","end":2},{"word":"later","start":2,"end":2.4},{"start":3,"end":4}]}"#)])
        let result = try await DictationAPI(transport: transport).transcribeDetailed(audio: Data([1]), apiKey: "fixture", provider: .elevenLabs, includeTimestamps: true)
        XCTAssertEqual(result.text, "here")
        XCTAssertEqual(result.words, [.init(text: "here", start: 1.2, end: 1.5), .init(text: "later", start: 2, end: 2.4)])
        let requests = await transport.requests
        XCTAssertTrue(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("name=\"timestamps_granularity\"\r\n\r\nword"))
    }

    func testBatchAnalysisHasOneMetadataReadAndOneOrderedImageRequest() async throws {
        let notes = ["The processing animation.", "The nearby notch preview."]
        let content = try JSONSerialization.data(withJSONObject: ["descriptions": notes])
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: content, as: UTF8.self)]]]])
        let transport = ScriptedTransport([
            .init(path: "/api/v1/models/vendor/vision/endpoints", status: 200, json: #"{"data":{"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}}"#),
            .init(path: "/api/v1/chat/completions", status: 200, json: String(decoding: response, as: UTF8.self))
        ])
        let images = [PromptImageInput(number: 1, png: Data([1]), pointer: .zero, seconds: 1, phrase: "here"), PromptImageInput(number: 2, png: Data([2]), pointer: .zero, seconds: 1.3, phrase: "here")]
        let result = try await DictationAPI(transport: transport).describePromptImages(images, transcript: "like here or here", model: "vendor/vision", apiKey: "fixture")
        XCTAssertEqual(result, notes)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertNil(body["provider"])
        XCTAssertEqual(body["model"] as? String, "vendor/vision")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let urls = parts.compactMap { ($0["image_url"] as? [String: String])?["url"] }
        XCTAssertEqual(urls, ["data:image/png;base64,AQ==", "data:image/png;base64,Ag=="])
    }
}
