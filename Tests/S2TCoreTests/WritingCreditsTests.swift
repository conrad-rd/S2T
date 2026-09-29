import XCTest
@testable import S2TCore

final class WritingCreditsTests: XCTestCase {
    private let key = "s2t_test_" + String(repeating: "b", count: 64)
    private func connection() throws -> CreditConnection { try .init(address: "https://credits.example.com", key: key) }

    func testBothDocumentsSharePersonalEditingContractAndCreditRetryIdentity() async throws {
        for kind in WritingDocumentKind.allCases {
            let source = "# Original\n- S2T\n", instruction = "Keep names 😀"
            let personal = ScriptedTransport([.init(path: "/api/v1/chat/completions", status: 200, json: #"{"choices":[{"finish_reason":"stop","message":{"content":"Revised"}}]}"#)])
            _ = try await DictationAPI(transport: personal).improveWritingDocument(source, kind: kind, instruction: instruction,
                model: "vendor/model", apiKey: "personal-fixture")
            let credits = WritingCreditTransport(retry: true)
            let result = try await CreditsAPI(transport: credits).improveWritingDocument(source, kind: kind, instruction: instruction,
                model: "vendor/model", endpoint: "fixture/host", options: .init(reasoning: .high),
                connection: connection(), requestID: "writing-fixture")
            XCTAssertEqual(result, "Revised")
            let personalRequests = await personal.requests, requests = await credits.requests
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: personalRequests[0].httpBody!) as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            let paidBody = try JSONDecoder().decode([String: String].self, from: requests[0].httpBody!)
            XCTAssertEqual(paidBody["instructions"], messages[0]["content"])
            XCTAssertEqual(paidBody["text"], messages[1]["content"])
            XCTAssertEqual(paidBody["host"], "fixture/host")
            XCTAssertEqual(paidBody["reasoning"], "high")
            XCTAssertEqual(paidBody["operation"], "cleanup")
            XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
            for request in requests {
                XCTAssertEqual(request.url?.host, "credits.example.com")
                XCTAssertEqual(request.url?.path, "/api/v1/requests")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "writing-fixture")
            }
        }
    }

    func testCreditPreflightBoundsWholeUTF8PromptAndRequiresContributorConsent() async throws {
        let overhead = try WritingDocumentRequest(text: "", kind: .instructions, instruction: "Tidy").prompt.utf8.count
        let transport = WritingCreditTransport()
        let api = CreditsAPI(transport: transport)
        _ = try await api.improveWritingDocument(String(repeating: "a", count: 16_000 - overhead), kind: .instructions,
            instruction: "Tidy", model: "vendor/model", endpoint: nil, connection: connection(), requestID: "boundary")
        for (source, instruction, model, provider) in [
            (String(repeating: "a", count: 16_001 - overhead), "Tidy", "vendor/model", ProcessingProvider.openRouter),
            (String(repeating: "😀", count: 4_000), "Tidy", "vendor/model", .openRouter),
            ("Document", String(repeating: "x", count: 4_097), "vendor/model", .openRouter),
            ("Document", "Tidy", OpenRouterOptions.contributorModel, .openRouter),
            ("Document", "Tidy", "default", .codex),
            ("Document", "Tidy", "local-model", .local)
        ] {
            do {
                _ = try await api.improveWritingDocument(source, kind: .instructions, instruction: instruction,
                    model: model, endpoint: nil, provider: provider, connection: connection(), requestID: "rejected")
                XCTFail("Invalid or oversized paid writing request accepted")
            } catch { }
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "Preflight failures must not reserve credits")
    }

    func testXAIHasNoOpenRouterOptionsAndInvalidOutputCannotBecomeSuggestion() async throws {
        let transport = WritingCreditTransport()
        _ = try await CreditsAPI(transport: transport).improveWritingDocument("Dictionary", kind: .dictionary,
            instruction: "Tidy", model: "grok-4.6", endpoint: "must-not-route", options: .init(reasoning: .high, fast: true),
            provider: .xai, connection: connection(), requestID: "xai")
        let requests = await transport.requests
        let body = try JSONDecoder().decode([String: String].self, from: requests[0].httpBody!)
        XCTAssertEqual(body["provider"], "xai")
        XCTAssertEqual(body["host"], "")
        XCTAssertNil(body["reasoning"]); XCTAssertNil(body["fast"]); XCTAssertNil(body["allowDataCollection"])
        for (state, output, error) in [("settled", "Partial", "Incomplete output. Your original transcription is preserved."),
                                       ("released", "", "Provider rejected"), ("uncertain", "", ""),
                                       ("settled", " ", ""), ("settled", String(repeating: "x", count: 65_537), "")] {
            let failed = WritingCreditTransport(state: state, output: output, error: error)
            do {
                _ = try await CreditsAPI(transport: failed).improveWritingDocument("Original", kind: .dictionary,
                    instruction: "Tidy", model: "vendor/model", endpoint: nil, connection: connection(), requestID: "invalid")
                XCTFail("Invalid credit result accepted")
            } catch { XCTAssertFalse(error.localizedDescription.contains("original transcription")) }
        }
    }
}

private actor WritingCreditTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let retry: Bool
    let state: String, output: String, error: String
    init(retry: Bool = false, state: String = "settled", output: String = "Revised", error: String = "") {
        self.retry = retry; self.state = state; self.output = output; self.error = error
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if retry && requests.count == 1 { throw URLError(.networkConnectionLost) }
        var body: [String: Any] = ["state": state, "result": ["text": output, "model": "vendor/model", "host": "Fixture"]]
        if !error.isEmpty { body["error"] = error }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
