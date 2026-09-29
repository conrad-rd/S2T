import XCTest
@testable import S2TCore

final class MeetingProcessingTests: XCTestCase {
    func testProcessingKeepsOriginalTextAndSpeakerTimestamps() throws {
        let original = MeetingUtterance(speaker: "You", start: 120.3, end: 122, text: "hello there")
        let reply = "[{\"id\":\"\(original.id)\",\"text\":\"Hello there.\"}]"
        let result = try XCTUnwrap(MeetingProcessing.apply(reply, to: [original]).first)
        XCTAssertEqual(result.text, "hello there")
        XCTAssertEqual(result.displayText, "Hello there.")
        XCTAssertEqual(result.speaker, original.speaker)
        XCTAssertEqual(result.start, original.start)
        XCTAssertEqual(result.end, original.end)
        XCTAssertEqual(result.id, original.id)
    }
    func testProcessingRejectsDroppedRepeatedAndUnknownEntries() {
        let original = MeetingUtterance(speaker: "A", start: 0, end: 1, text: "Words")
        for reply in ["[]", "[{\"id\":\"\(UUID())\",\"text\":\"Words\"}]", "[{\"id\":\"\(original.id)\",\"text\":\"\"}]",
                      "[{\"id\":\"\(original.id)\",\"text\":\"Words\"},{\"id\":\"\(original.id)\",\"text\":\"Again\"}]"] {
            XCTAssertThrowsError(try MeetingProcessing.apply(reply, to: [original]))
        }
        XCTAssertNil(original.processedText)
    }
    func testProviderSettingsAndMeetingSnapshotsStayIndependent() throws {
        var settings = MeetingProcessingSettings()
        settings.enabled = true; settings.model = "openai/gpt-oss-20b"; settings.host = "custom-host"
        settings.provider = "xai"; settings.model = "grok-example"
        settings.provider = "openrouter"
        XCTAssertEqual(settings.model, "openai/gpt-oss-20b")
        var record = MeetingRecord(title: "Review", model: .universal2)
        record.processingSettings = settings
        settings.model = "another/model"
        let restored = try JSONDecoder().decode(MeetingRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.model, .universal2)
        XCTAssertEqual(restored.processingSettings?.model, "openai/gpt-oss-20b")
        XCTAssertEqual(restored.processingSettings?.host, "custom-host")
    }
    func testProcessingRoutesOnlyTheSelectedProviderKeyAndOptions() async throws {
        let transport = ProcessingTransport()
        let api = DictationAPI(transport: transport)
        let original = MeetingUtterance(speaker: "You", start: 0, end: 1, text: "hello")
        var settings = MeetingProcessingSettings()
        settings.provider = "xai"; settings.model = "grok-example"
        _ = try await api.processMeeting([original], settings: settings, apiKey: "fake-xai")
        settings.provider = "local"; settings.localURL = "http://127.0.0.1:9999/v1/chat/completions"
        _ = try await api.processMeeting([original], settings: settings, apiKey: "must-not-send")
        settings.provider = "openrouter"; settings.model = "openai/gpt-oss-120b"; settings.host = "cerebras/fp16"
        _ = try await api.processMeeting([original], settings: settings, apiKey: "fake-router")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.host, "api.x.ai")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fake-xai")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[2].url?.host, "openrouter.ai")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fake-router")
        for request in requests.prefix(2) {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            XCTAssertNil(body["provider"])
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[2].httpBody!) as? [String: Any])
        XCTAssertEqual((body["provider"] as? [String: Any])?["only"] as? [String], ["cerebras/fp16"])
    }
}
private actor ProcessingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        let reply: [String: Any] = ["model": "actual-model", "choices": [["finish_reason": "stop", "message": ["content": messages[1]["content"]!]]]]
        return (try JSONSerialization.data(withJSONObject: reply), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
