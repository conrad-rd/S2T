import XCTest
@testable import S2TCore

final class EditingHarnessTests: XCTestCase {
    func testSpokenCorrectionsRemainActiveWithCustomStyles() throws {
        for mode in [WritingMode.clean, .email, .notes] {
            let request = try DictationEditingRequest(text: "Use Friday, oh wait, actually I meant Monday.", mode: mode, instructions: "Keep my casual tone.", clipboardContext: ClipboardContext())
            XCTAssertTrue(request.instructions.contains("Resolve corrections before removing hesitation sounds"))
            XCTAssertTrue(request.instructions.contains("ignore that"))
            XCTAssertTrue(request.instructions.contains("42, not 24"))
            XCTAssertTrue(request.instructions.contains("Blah blah blah"))
            XCTAssertTrue(request.instructions.contains("Keep my casual tone."))
            XCTAssertFalse(request.instructions.contains("Composition cues may adjust punctuation or layout of existing words"))
        }
    }

    func testExplicitDiscardIsDistinctFromBrokenEmptyCompletion() async throws {
        for provider in [ProcessingProvider.openRouter, .local] {
            let path = provider == .openRouter ? "/api/v1/chat/completions" : "/v1/chat/completions"
            let reply = #"{"choices":[{"finish_reason":"stop","message":{"content":"__S2T_NO_TEXT_0__"}}]}"#
            let transport = ScriptedTransport([.init(path: path, status: 200, json: reply)])
            let result = try await DictationAPI(transport: transport).process(text: "Book the early flight. Oh, ignore all of that.", mode: .clean, model: provider.defaultModel, apiKey: "fixture", provider: provider, localURL: LocalEndpoint.defaultProcessingURL)
            XCTAssertEqual(result.text, "")
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        for reply in [#"{"choices":[{"finish_reason":"stop","message":{"content":""}}]}"#,
                      #"{"choices":[{"finish_reason":"length","message":{"content":"__S2T_NO_TEXT_0__"}}]}"#] {
            let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: reply)])
            do {
                _ = try await DictationAPI(transport: transport).process(text: "Keep the team meeting.", mode: .clean, model: "openai/gpt-oss-120b", apiKey: "fixture")
                XCTFail("An empty or truncated completion must retain the original transcript through the failure path")
            } catch { XCTAssertTrue(error.localizedDescription.contains("incomplete")) }
        }
    }

    func testLiteralMarkerAndRecipientInstructionsAreNotDiscarded() throws {
        let literal = "__S2T_NO_TEXT_0__"
        let request = try DictationEditingRequest(text: literal, mode: .clean, instructions: nil, clipboardContext: ClipboardContext())
        XCTAssertEqual(try request.finish(literal), literal)
        XCTAssertEqual(try request.finish("Please ignore that warning."), "Please ignore that warning.")
        XCTAssertThrowsError(try request.finish("Here is __S2T_NO_TEXT_1__"))
    }

    func testVerbatimDoesNotConsumeEditingSignals() throws {
        let text = "Book Friday, sorry, Monday. Ignore that."
        let request = try DictationEditingRequest(text: text, mode: .verbatim, instructions: nil, clipboardContext: ClipboardContext())
        XCTAssertFalse(request.instructions.contains("__S2T_NO_TEXT_"))
        XCTAssertEqual(try request.finish(text), text)
    }
}
