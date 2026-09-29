import XCTest
@testable import S2TCore

final class WritingDocumentTests: XCTestCase {
    func testEditsPreserveExactTextAndRejectExternalChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = WritingDocumentFile(directory: root, kind: .dictionary)
        let initial = try file.read()
        let draft = "# My dictionary\n\n- S2T\n"
        try file.save(draft, replacing: initial)
        XCTAssertEqual(try file.read(), draft)
        try "External correction\n".write(to: file.url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try file.save("New draft", replacing: draft))
        XCTAssertEqual(try file.read(), "External correction\n")
    }

    func testEmptyPromptAndOversizedDocumentsDoNotReplaceSavedText() throws {
        let file = WritingDocumentFile(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), kind: .instructions)
        let original = try file.read()
        XCTAssertThrowsError(try file.save(" \n", replacing: original))
        XCTAssertThrowsError(try file.save(String(repeating: "a", count: 65_537), replacing: original))
        XCTAssertEqual(try file.read(), original)
    }

    func testAIRequestUsesDocumentEditingAndIndependentRouting() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Preserve names.\n"}}]}"#)])
        let result = try await DictationAPI(transport: transport).improveWritingDocument("Keep names", kind: .instructions, instruction: "Make it clearer", model: "vendor/model", apiKey: "fixture", endpoint: "fixture/host", routerOptions: .init(reasoning: .high, fast: true))
        XCTAssertEqual(result, "Preserve names.\n")
        let requests = await transport.requests
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "vendor/model")
        let routing = try XCTUnwrap(body["provider"] as? [String: Any])
        XCTAssertEqual(routing["only"] as? [String], ["fixture/host"])
        XCTAssertEqual(routing["data_collection"] as? String, "deny")
        XCTAssertNil(routing["sort"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertTrue(messages[0]["content"]!.contains("instructions for a dictation cleanup tool"))
        XCTAssertTrue(messages[0]["content"]!.contains("Markdown by default"))
        XCTAssertTrue(messages[0]["content"]!.contains("without a surrounding code fence"))
        XCTAssertTrue(messages[1]["content"]!.contains("Make it clearer"))
        XCTAssertTrue(messages[1]["content"]!.contains("Keep names"))
        XCTAssertFalse(messages[0]["content"]!.contains("clipboard"))
    }

    func testIncompleteAIResponseIsRejected() async throws {
        let transport = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"length","message":{"content":"Partial"}}]}"#)])
        do {
            _ = try await DictationAPI(transport: transport).improveWritingDocument("Original", kind: .dictionary, instruction: "Tidy", model: "vendor/model", apiKey: "fixture")
            XCTFail("Incomplete replacement accepted")
        } catch { }
    }
}

extension WritingDocumentTests {
    func testWritingRoutesXAIAndLocalWithTheirOwnContract() async throws {
        for provider in [ProcessingProvider.xai, .local] {
            let transport = ScriptedTransport([.init(path: "/v1/chat/completions", status: 200, json: ##"{"choices":[{"finish_reason":"stop","message":{"content":"# Revised\nKeep spelling."}}]}"##)])
            let model = provider == .xai ? "grok-4.6" : "local-model"
            let output = try await DictationAPI(transport: transport).improveWritingDocument("Original instructions", kind: .instructions, instruction: "Preserve spelling", model: model, apiKey: "xai-fixture", provider: provider, endpoint: "must-not-route", localURL: "http://127.0.0.1:1234/v1/chat/completions")
            XCTAssertEqual(output, "# Revised\nKeep spelling.")
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.host, provider == .xai ? "api.x.ai" : "127.0.0.1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), provider == .xai ? "Bearer xai-fixture" : nil)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, model)
            XCTAssertNil(body["provider"])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertTrue(messages[0]["content"]!.contains("Markdown by default"))
            XCTAssertTrue(messages[1]["content"]!.contains("Preserve spelling"))
            XCTAssertTrue(messages[1]["content"]!.contains("Original instructions"))
        }
    }

    func testCodexUsesItsOwnOptionsWithoutNetworkOrImages() async throws {
        let transport = ScriptedTransport([])
        let codex = FixtureCodex(output: "# Dictionary\n- S2T\n")
        let output = try await DictationAPI(transport: transport, codex: codex).improveWritingDocument("# Dictionary", kind: .dictionary, instruction: "Add S2T", model: "fixture-model", apiKey: "", provider: .codex, endpoint: "must-not-route", codexOptions: .init(reasoning: "high", fast: true))
        XCTAssertEqual(output, "# Dictionary\n- S2T\n")
        let options = await codex.options
        let requests = await transport.requests
        XCTAssertEqual(options, .init(reasoning: "high", fast: true))
        XCTAssertTrue(requests.isEmpty)
    }
}
