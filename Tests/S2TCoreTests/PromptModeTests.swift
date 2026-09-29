import XCTest
@testable import S2TCore

final class PromptModeTests: XCTestCase {
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







    func testScreenshotMentionsStayBetweenTheirSpokenReferenceAndFollowingWords() {
        let source = PromptReferenceText(transcript: "Make this like here, and that like here. Keep the footer.", session: "abc123")
        let references: [PromptReferenceText.Reference] = [
            .init(number: 1, seconds: 2.5, description: "Blue Save button", imageName: "abc123-reference-1.png", cueIndex: 0),
            .init(number: 2, seconds: 3.5, description: "Sidebar", imageName: "abc123-reference-2.png", cueIndex: 1)
        ]
        XCTAssertEqual(source.resolve(source.text, references: references),
                       "Make this like here [attached screenshot: [1]], and that like here [attached screenshot: [2]]. Keep the footer.")
        XCTAssertEqual(source.resolve(source.text.replacingOccurrences(of: "Make this", with: "Change this"), references: references),
                       "Change this like here [attached screenshot: [1]], and that like here [attached screenshot: [2]]. Keep the footer.")
        XCTAssertEqual(source.resolve(source.text, references: []), "Make this like here, and that like here. Keep the footer.")
    }

    func testMissingFirstScreenshotDoesNotMoveSecondMentionToFirstCue() {
        let source = PromptReferenceText(transcript: "Look here for the header, and here for the sidebar. Keep the colors.", session: "test")
        let references: [PromptReferenceText.Reference] = [
            .init(number: 1, seconds: 3, description: "Sidebar", imageName: "1.png", cueIndex: 1),
            .init(number: 2, seconds: -1, description: "Manual crop", imageName: "2.png")
        ]
        XCTAssertEqual(source.resolve(source.text, references: references),
                       "Look here for the header, and here [attached screenshot: [1]] for the sidebar. Keep the colors.")
        let silent = PromptReferenceText(transcript: "", session: "test")
        XCTAssertEqual(silent.resolve(silent.text, references: references), "[attached screenshot: [1]]\n[attached screenshot: [2]]")
    }

    func testInlineMarkersPreserveUnicodePunctuationAndNegativeReferences() {
        let transcript = "İ 👩🏽‍💻 Schau mal hier, dann LOOK HERE! Don't look here. Nicht hier. Keep it."
        let source = PromptReferenceText(transcript: transcript, session: "unicode")
        let references = (0..<2).map {
            PromptReferenceText.Reference(number: $0 + 1, seconds: Double($0), description: "", imageName: nil, cueIndex: $0)
        }
        XCTAssertEqual(source.resolve(source.text, references: references),
                       "İ 👩🏽‍💻 Schau mal hier [attached screenshot: [1]], dann LOOK HERE [attached screenshot: [2]]! Don't look here. Nicht hier. Keep it.")
        XCTAssertEqual(source.resolve(source.text, references: []), transcript)
    }

    func testCleanupRequestContainsInlineMarkersAndPreservationRuleWithCustomInstructions() throws {
        let source = PromptReferenceText(transcript: "Look here. Keep the footer.", session: "test")
        for mode in [WritingMode.clean, .notes, .email] {
            let request = try DictationEditingRequest(text: source.text, mode: mode, instructions: "Use short sentences.", clipboardContext: ClipboardContext())
            let payload = try JSONDecoder().decode([String: String].self, from: Data(request.source.utf8))
            XCTAssertEqual(payload["dictated_text"], "Look here __S2T_SCREENSHOT_test_0__. Keep the footer.")
            XCTAssertTrue(request.instructions.contains(PromptReferenceText.editingInstruction))
            XCTAssertTrue(request.instructions.contains("Use short sentences."))
        }
        let ordinary = try DictationEditingRequest(text: "Keep the footer.", mode: .clean, instructions: nil, clipboardContext: ClipboardContext())
        XCTAssertFalse(ordinary.instructions.contains(PromptReferenceText.editingInstruction))
    }

    func testRecoveredCleanupWithoutItsScreenSessionDoesNotPasteInternalMarkers() {
        let source = PromptReferenceText(transcript: "Look here. Keep this here too.", session: "a1b2c3d4e5f6")
        XCTAssertEqual(PromptReferenceText.removingMarkers(from: source.text), "Look here. Keep this here too.")
    }
}
