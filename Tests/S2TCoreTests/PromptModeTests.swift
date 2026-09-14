import XCTest
@testable import S2TCore

final class PromptModeTests: XCTestCase {
    private var visionMetadata: ScriptedTransport.Response {
        .init(path: "/api/v1/models/vendor/vision/endpoints", status: 200, json: #"{"data":{"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}}"#)
    }
    func testNaturalReferencesFromReportedPrompt() {
        let text = "I want the processing animation, like here, or like here, or like here. For the bezel, zoomed in here, and for the notch, zoomed in here showing the notch. This tab here, keep the logo."
        XCTAssertEqual(PromptReferenceDetector.matches(text).count, 6)
        for text in ["this area here", "like there", "zoom in here", "so wie hier", "dieser Bereich hier"] {
            XCTAssertEqual(PromptReferenceDetector.matches(text).count, 1, text)
        }
        for text in ["not here", "nicht hier", "don't look here"] {
            XCTAssertTrue(PromptReferenceDetector.matches(text).isEmpty, text)
        }
    }

    func testReferencePhrasesAndNegativeSpeech() {
        for phrase in ["look here", "look at this", "take a look at that", "check this out", "see this", "look over here", "schau mal hier", "schau dir das an"] {
            XCTAssertFalse(PromptReferenceDetector.matches(phrase).isEmpty, phrase)
        }
        for phrase in ["I look forward to this", "don't look at this", "do not look here", "look at the calendar tomorrow"] {
            XCTAssertTrue(PromptReferenceDetector.matches(phrase).isEmpty, phrase)
        }
    }

    func testPartialRevisionDeduplicatesButLaterReferenceCapturesAgain() {
        var detector = PromptReferenceDetector()
        XCTAssertTrue(detector.consume(text: "look", wordTimes: [0]).isEmpty)
        XCTAssertEqual(detector.consume(text: "look at this", wordTimes: [0, 0.2, 0.4]).count, 1)
        XCTAssertTrue(detector.consume(text: "Look at this button", wordTimes: [0.05, 0.2, 0.4, 0.6]).isEmpty)
        XCTAssertEqual(detector.consume(text: "look at this button and look here", wordTimes: [0, 0.2, 0.4, 0.6, 1, 2, 2.2]).count, 1)
    }

    func testUnsettledTimestampsDoNotSuppressSeparateReferencesAndRolloverDeduplicates() {
        var detector = PromptReferenceDetector()
        XCTAssertEqual(detector.consume(text: "look here", wordTimes: [0, 0]).count, 1)
        XCTAssertEqual(detector.consume(text: "look here and look at this", wordTimes: Array(repeating: 0, count: 6)).count, 1)
        XCTAssertTrue(detector.consume(text: "look here and look at this", wordTimes: [0, 0.2, 1, 2, 2.2, 2.4]).isEmpty)
        var rollover = PromptReferenceDetector()
        XCTAssertEqual(rollover.consume(text: "look here", wordTimes: [44, 44.2], requestID: 1).count, 1)
        XCTAssertTrue(rollover.consume(text: "look here", wordTimes: [44.1, 44.3], requestID: 2).isEmpty)
        XCTAssertEqual(rollover.consume(text: "look here then look at this", wordTimes: [44.1, 44.3, 45, 46, 46.2, 46.4], requestID: 2).count, 1)
    }

    func testCropIsBoundedOnOffsetDisplaysAndPreservesPointerCoordinates() {
        let display = CGRect(x: -1440, y: -900, width: 1440, height: 900)
        let crop = PromptCaptureGeometry.region(pointer: CGPoint(x: -1438, y: -898), display: display)
        XCTAssertTrue(display.contains(crop))
        XCTAssertTrue(crop.contains(CGPoint(x: -1438, y: -898)))
        XCTAssertEqual(crop.size, CGSize(width: 800, height: 600))
        XCTAssertEqual(PromptCaptureGeometry.region(pointer: .zero, display: CGRect(x: 0, y: 0, width: 500, height: 400)).size, CGSize(width: 500, height: 400))
    }

    func testVisionUsesSeparateModelAndNoCleanupHost() async throws {
        let transport = ScriptedTransport([visionMetadata, .init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"description\":\"A blue button next to Save.\",\"needs_image\":true}"}}]}"#)])
        let result = try await DictationAPI(transport: transport).describePromptImage(png: Data([1, 2, 3]), transcript: "match this design", pointer: CGPoint(x: 20, y: 30), model: "vendor/vision", apiKey: "fixture")
        XCTAssertEqual(result.description, "A blue button next to Save.")
        let requests = await transport.requests
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "vendor/vision")
        XCTAssertNil(body["provider"])
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
        XCTAssertTrue(String(data: requests[1].httpBody!, encoding: .utf8)!.contains("data:image/png;base64,AQID"))
    }

    func testVisionAcceptsDescriptionWithoutAnImageDecision() async throws {
        let transport = ScriptedTransport([visionMetadata, .init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"description\":\"The nearby settings panel has uneven row spacing.\"}"}}]}"#)])
        let result = try await DictationAPI(transport: transport).describePromptImage(png: Data([1]), transcript: "The spacing in this area needs fixing, look here.", pointer: CGPoint(x: 400, y: 300), model: "vendor/vision", apiKey: "fixture")
        XCTAssertEqual(result.description, "The nearby settings panel has uneven row spacing.")
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let instructions = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(instructions.contains("entire screenshot"))
        XCTAssertTrue(instructions.contains("1–2 short sentences"))
        XCTAssertTrue(instructions.contains("ambiguous"))
        XCTAssertFalse(instructions.contains("needs_image"))
        XCTAssertLessThanOrEqual(try XCTUnwrap(body["max_tokens"] as? Int), 500)
    }

    func testTextOnlyModelRejectedBeforeAnyImageOrKeyIsSent() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/models/openai/gpt-oss-120b/endpoints", status: 200, json: #"{"data":{"architecture":{"input_modalities":["text"],"output_modalities":["text"]}}}"#)])
        do {
            _ = try await DictationAPI(transport: transport).describePromptImage(png: Data([1, 2, 3]), transcript: "look here", pointer: .zero, model: "openai/gpt-oss-120b", apiKey: "fixture")
            XCTFail("Text-only model accepted an image")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("cannot describe screenshots"))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests[0].httpBody)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    func testDescriptionsCannotLoseSessionAssociation() {
        let text = PromptReferenceText.append(to: "Change this.", session: "abc123", references: [.init(number: 1, seconds: 2.5, description: "Blue Save button", imageName: "abc123-reference-1.png")])
        XCTAssertTrue(text.contains("Prompt set abc123"))
        XCTAssertTrue(text.contains("2.5s"))
        XCTAssertTrue(text.contains("abc123-reference-1.png"))
        XCTAssertTrue(text.contains("Blue Save button"))
        XCTAssertFalse(text.contains("is attached"))
    }
}
