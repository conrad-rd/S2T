import XCTest
@testable import S2TCore

final class VisualProviderTests: XCTestCase {
    func testLocalVisionSendsOrderedImagesOnlyToSelectedEndpointWithoutCredentials() async throws {
        let transport = ScriptedTransport([.init(path: "/vision", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"descriptions\":[\"Red button.\",\"Blue panel.\"]}"}}]}"#)])
        let images = [1, 2].map { PromptImageInput(number: $0, png: Data([$0 == 1 ? 1 : 2]), pointer: .zero, seconds: Double($0), phrase: "here") }
        let result = try await DictationAPI(transport: transport).describePromptImages(images, transcript: "Change this.", model: "vision:local", apiKey: "cloud-secret", provider: .local, localURL: "http://localhost:1234/vision")
        XCTAssertEqual(result, ["Red button.", "Blue panel."])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("cloud-secret"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "vision:local")
        XCTAssertNil(json["provider"])
    }

    func testVisionFailureDoesNotTryCloudAndRejectsMissingDescriptions() async throws {
        let transport = ScriptedTransport([.init(path: "/vision", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"descriptions\":[]}"}}]}"#)])
        do {
            _ = try await DictationAPI(transport: transport).describePromptImages([.init(number: 1, png: Data([1]), pointer: .zero, seconds: 0, phrase: "here")], transcript: "here", model: "vision", apiKey: "secret", provider: .local, localURL: "http://localhost/vision")
            XCTFail("Accepted missing description")
        } catch {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCodexCleanupKeepsFormattingAndClipboardResolutionWithoutHTTP() async throws {
        let transport = ScriptedTransport([])
        let codex = FixtureCodex(output: "Clean words.")
        let api = DictationAPI(transport: transport, codex: codex)
        let output = try await api.process(text: "rough words", mode: .clean, model: "default", apiKey: "must-not-leak", provider: .codex, systemPrompt: "Custom editor instruction", codexOptions: CodexOptions(reasoning: "high", fast: true))
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

    func testCodexVisionUsesImagesAndStrictResponseOrderWithoutHTTP() async throws {
        let transport = ScriptedTransport([])
        let codex = FixtureCodex(output: #"{"descriptions":["A red button."]}"#)
        let image = Data([1, 2, 3])
        let result = try await DictationAPI(transport: transport, codex: codex).describePromptImages([.init(number: 1, png: image, pointer: .zero, seconds: 1, phrase: "here")], transcript: "Here.", model: "default", apiKey: "secret", provider: .codex, codexOptions: CodexOptions(reasoning: "low"))
        XCTAssertEqual(result, ["A red button."])
        let sent = await codex.images
        XCTAssertEqual(sent, [image])
        let options = await codex.options
        XCTAssertEqual(options, CodexOptions(reasoning: "low"))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

actor FixtureCodex: CodexServing {
    let output: String
    var prompts: [String] = []
    var images: [Data] = []
    var options = CodexOptions()
    init(output: String) { self.output = output }
    func complete(instructions: String, prompt: String, model: String, images: [Data], executable: String, options: CodexOptions) async throws -> String {
        prompts.append(instructions + prompt)
        self.images = images
        self.options = options
        return output
    }
}
