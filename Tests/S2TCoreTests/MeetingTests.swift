import XCTest
@testable import S2TCore

final class MeetingTests: XCTestCase {
    func testGrokMeetingRequiresSpeakerLabelsAndKeepsSeconds() async throws {
        let transport = GrokMeetingTransport()
        let api = MeetingTranscriber(transport: transport)
        let result = try await api.transcribeGrok(audio: Data([1, 2, 3]), key: "grok-fixture", model: .grok2)
        XCTAssertEqual(result.map(\.speaker), ["Speaker 0", "Speaker 1"])
        XCTAssertEqual(result.map(\.start), [0.25, 1.5])
        let last = await transport.last()
        let request = try XCTUnwrap(last)
        XCTAssertEqual(request.url?.host, "api.x.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer grok-fixture")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"diarize\"\r\n\r\ntrue"))
        XCTAssertTrue(body.contains("grok-voice-transcribe-2.0"))
        XCTAssertLessThan(body.range(of: "name=\"diarize\"")!.lowerBound, body.range(of: "name=\"file\"")!.lowerBound)
        await transport.omitSpeakers()
        do {
            _ = try await api.transcribeGrok(audio: Data([1]), key: "grok-fixture", model: .grok1)
            XCTFail("Unlabelled speech must never be accepted as a speaker-separated meeting")
        } catch { }
    }
    func testSpeakerLabelsCanSwapBetweenPartsWithoutSwappingPeople() {
        let anchors = [MeetingSpeakerAnchor(speaker: "Alex", start: 0, end: 5), MeetingSpeakerAnchor(speaker: "Sam", start: 6, end: 11)]
        let input = [MeetingUtterance(speaker: "B", start: 0, end: 4, text: "old Alex"), MeetingUtterance(speaker: "A", start: 6, end: 10, text: "old Sam"),
                     MeetingUtterance(speaker: "A", start: 12, end: 13, text: "Hello"), MeetingUtterance(speaker: "B", start: 14, end: 15, text: "Hi")]
        let output = MeetingSpeakers.resolve(input, anchors: anchors, prefix: 12, offset: 120, namespace: "part2")
        XCTAssertEqual(output.map(\.speaker), ["Sam", "Alex"])
        XCTAssertEqual(output.map(\.start), [120, 122])
        XCTAssertEqual(output.map(\.text), ["Hello", "Hi"])
    }
    func testAmbiguousAnchorDoesNotConfidentlyMergePeople() {
        let anchors = [MeetingSpeakerAnchor(speaker: "Alex", start: 0, end: 5), MeetingSpeakerAnchor(speaker: "Sam", start: 6, end: 11)]
        let output = MeetingSpeakers.resolve([.init(speaker: "A", start: 0, end: 4, text: "one"), .init(speaker: "A", start: 6, end: 10, text: "two"), .init(speaker: "A", start: 12, end: 13, text: "new")], anchors: anchors, prefix: 12, offset: 120, namespace: "Part 2")
        XCTAssertEqual(output.first?.speaker, "Part 2 · A")
    }
    func testChronologicalExportsRetainUnicodeAndSpeakerNames() {
        var record = MeetingRecord(title: "Planning [draft]", model: .universal2)
        record.utterances = [.init(speaker: "B", start: 121, end: 125, text: "Grüße 日本語"), .init(speaker: "A", start: 3, end: 5, text: "First")]
        record.speakerNames["A"] = "You"
        XCTAssertTrue(record.markdown.contains("Planning \\[draft\\]"))
        XCTAssertTrue(record.plainText.contains("[00:00:03] You: First"))
        XCTAssertTrue(record.plainText.contains("Grüße 日本語"))
        XCTAssertLessThan(record.plainText.range(of: "First")!.lowerBound, record.plainText.range(of: "Grüße")!.lowerBound)
    }
    func testPersistentMeetingRoundTripKeepsJobsAndNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MeetingStore(directory: folder)
        var record = MeetingRecord(title: "Review", model: .universal35)
        var chunk = MeetingChunk(index: 0, start: 0, duration: 120, filename: "room-0.wav")
        chunk.jobID = "saved-job"; record.chunks = [chunk]; record.speakerNames["A"] = "You"
        try store.save(record)
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.id, record.id); XCTAssertEqual(loaded.chunks.first?.jobID, "saved-job")
        XCTAssertEqual(loaded.speakerNames["A"], "You"); XCTAssertEqual(loaded.model, .universal35)
    }
    func testMeetingRequestUsesIndependentModelAndDiarization() async throws {
        let transport = MeetingTransport()
        let api = MeetingTranscriber(transport: transport, pollNanoseconds: 0)
        let id = try await api.submit(audio: Data([1, 2, 3]), key: "fake-key", model: .universal2)
        let result = try await api.result(id: id, key: "fake-key")
        XCTAssertEqual(result.first?.text, "Hello"); XCTAssertEqual(result.first?.start, 0.25)
        let calls = await transport.calls
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: calls[1].httpBody!) as? [String: Any])
        XCTAssertEqual(body["speech_models"] as? [String], ["universal-2"])
        XCTAssertEqual(body["speaker_labels"] as? Bool, true)
        XCTAssertEqual(calls.map { $0.value(forHTTPHeaderField: "Authorization") }, ["fake-key", "fake-key", "fake-key"])
    }
}
private actor MeetingTransport: HTTPTransport {
    var calls: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls.append(request)
        let value = request.url!.path.hasSuffix("upload") ? #"{"upload_url":"https://cdn.assemblyai.com/test"}"# : request.httpMethod == "POST" ? #"{"id":"test-job","status":"queued"}"# : #"{"id":"test-job","status":"completed","utterances":[{"speaker":"A","start":250,"end":800,"text":"Hello"}]}"#
        return (Data(value.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor GrokMeetingTransport: HTTPTransport {
    var request: URLRequest?
    var missing = false
    func last() -> URLRequest? { request }
    func omitSpeakers() { missing = true }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let value = missing ? #"{"text":"Hello","words":[{"text":"Hello","start":0,"end":1}]}"# : #"{"text":"Hello there","words":[{"text":"Hello","start":0.25,"end":0.8,"speaker":0},{"text":"there","start":1.5,"end":2,"speaker":1}]}"#
        return (Data(value.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
