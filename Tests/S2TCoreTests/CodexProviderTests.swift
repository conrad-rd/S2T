import XCTest
@testable import S2TCore

final class CodexProviderTests: XCTestCase {
    func testCodexCleanupKeepsFormattingAndClipboardResolutionWithoutHTTP() async throws {
        let transport = ScriptedTransport([])
        let codex = FixtureCodex(output: "Clean words.")
        let api = DictationAPI(transport: transport, codex: codex)
        let output = try await api.process(text: "rough words", mode: .clean, model: "default", apiKey: "must-not-leak", provider: .codex, instructions: "Custom editor instruction", codexOptions: CodexOptions(reasoning: "high", fast: true))
        XCTAssertEqual(output.text, "Clean words.")
        XCTAssertEqual(output.host, "Codex CLI")
        let options = await codex.options
        XCTAssertEqual(options, CodexOptions(reasoning: "high", fast: true))
        let received = await codex.prompts
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].contains("Custom editor instruction"))
        XCTAssertTrue(received[0].contains("rough words"))
        XCTAssertFalse(received[0].contains("must-not-leak"))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

}

actor FixtureCodex: CodexServing {
    let output: String
    var prompts: [String] = []
    var options = CodexOptions()
    init(output: String) { self.output = output }
    func complete(instructions: String, prompt: String, model: String, executable: String, options: CodexOptions) async throws -> String {
        prompts.append(instructions + prompt)
        self.options = options
        return output
    }
}
