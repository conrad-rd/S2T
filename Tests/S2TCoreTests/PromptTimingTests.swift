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

    func testLeadingToleranceCoversReferencesBeforeTheFirstFrame() {
        let times = [100.0, 100.25, 100.5]
        XCTAssertNil(PromptTiming.nearestFrame(to: 98.5, times: times))
        XCTAssertEqual(PromptTiming.nearestFrame(to: 98.5, times: times, leadingTolerance: 2), 0)
        XCTAssertNil(PromptTiming.nearestFrame(to: 97.9, times: times, leadingTolerance: 2))
        // The wider window applies only before recording started, never after the last frame.
        XCTAssertNil(PromptTiming.nearestFrame(to: 101.5, times: times, leadingTolerance: 2))
        XCTAssertEqual(PromptTiming.nearestFrame(to: 100.3, times: times, leadingTolerance: 2), 1)
    }

    func testTimestampOptionsAreOptInAndAssemblyMillisecondsBecomeSeconds() async throws {
        let audio = WaveAudio.encode(samples: Array(repeating: 0, count: 16000), sampleRate: 16000)
        let response = ScriptedTransport.Response(path: "/v1/transcribe", status: 200, json: #"{"text":"look here","words":[{"text":"look","start":120,"end":300},{"text":"here","start":350,"end":620}]}"#)
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

    func testLocalSecondTimestampsAndMalformedEntriesPreserveText() async throws {
        let transport = ScriptedTransport([.init(path: "/v1/audio/transcriptions", status: 200, json: #"{"text":"here","words":[{"text":"here","start":1.2,"end":1.5},{"text":"bad","start":"unknown","end":2},{"word":"later","start":2,"end":2.4},{"start":3,"end":4}]}"#)])
        let result = try await DictationAPI(transport: transport).transcribeDetailed(audio: Data([1]), apiKey: "fixture", provider: .local, localURL: "http://localhost:4317/v1/audio/transcriptions", includeTimestamps: true)
        XCTAssertEqual(result.text, "here")
        XCTAssertEqual(result.words, [.init(text: "here", start: 1.2, end: 1.5), .init(text: "later", start: 2, end: 2.4)])
        let requests = await transport.requests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    }


}
