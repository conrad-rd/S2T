import XCTest
@testable import S2TCore

final class JevCleanupTests: XCTestCase {
    func testS2TJevUsesCreditKeyAndStableReplayIdentity() async throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: true))
        let decisions = String(decoding: try JSONEncoder().encode(response(for: plan)), as: UTF8.self)
        let payload: [String: Any] = ["state": "settled", "result": ["text": decisions, "model": "typesafe/jev-1.13"]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let transport = ScriptedTransport([.init(path: "/api/v1/requests", status: 200, json: json), .init(path: "/api/v1/requests", status: 200, json: json)])
        let key = "s2t_demo_" + String(repeating: "a", count: 64)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        for _ in 0..<2 {
            let result = try await CreditsAPI(transport: transport).cleanWithJev(plan, connection: connection, requestID: "same-recording-request")
            XCTAssertEqual(result.text, "Hello.")
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer " + key)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Idempotency-Key"), requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertEqual(body["operation"], "decisions")
        XCTAssertEqual(body["model"], "typesafe/jev-1.13")
        XCTAssertNil(body["host"])
    }

    func testOpenRouterUsesDecisionsEndpointAndSelectedModel() async throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: true))
        for route in [JevRoute.openRouter, .openRouterLatest] {
            let json = String(decoding: try JSONEncoder().encode(response(for: plan)), as: UTF8.self)
            let transport = ScriptedTransport([.init(path: "/api/alpha/decisions", status: 200, json: json)])
            let result = try await DictationAPI(transport: transport).cleanWithJev(plan, apiKey: "router-fixture", route: route)
            XCTAssertEqual(result.text, "Hello.")
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/alpha/decisions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer router-fixture")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, route == .openRouter ? "typesafe/jev-1.13" : "~typesafe/jev-latest")
            XCTAssertNotNil(body["questions"])
            XCTAssertNil(body["messages"])
            XCTAssertNil(body["provider"])
            XCTAssertNil(body["reasoning"])
        }
    }

    func testFastPathNeverOverridesCustomInstructionsOrFormatting() {
        let standard = WritingMode.defaultEditingInstruction
        XCTAssertTrue(JevCleanupMode.adaptive.permitsFastPath(writingMode: .clean, instructions: standard, clipboardContextEnabled: false, hasVisualReferences: false))
        for mode in [WritingMode.email, .notes, .verbatim] {
            XCTAssertFalse(JevCleanupMode.adaptive.permitsFastPath(writingMode: mode, instructions: standard, clipboardContextEnabled: false, hasVisualReferences: false))
        }
        XCTAssertFalse(JevCleanupMode.adaptive.permitsFastPath(writingMode: .clean, instructions: standard + "\nWrite in German.", clipboardContextEnabled: false, hasVisualReferences: false))
        XCTAssertFalse(JevCleanupMode.adaptive.permitsFastPath(writingMode: .clean, instructions: standard, clipboardContextEnabled: true, hasVisualReferences: false))
        XCTAssertFalse(JevCleanupMode.adaptive.permitsFastPath(writingMode: .clean, instructions: standard, clipboardContextEnabled: false, hasVisualReferences: true))
        XCTAssertFalse(JevCleanupMode.beforeCleanup.permitsFastPath(writingMode: .clean, instructions: standard, clipboardContextEnabled: false, hasVisualReferences: false))
    }

    func testCreditRetryDraftSurvivesEncodingWithoutChangingOriginal() throws {
        var saved = RecordingRecovery(audio: Data([1, 2]), requestID: "request-fixture", mode: .clean, transcript: "Uh, hello.")
        saved.creditCleanupDraft = CreditCleanupDraft(requestID: "request-fixture-cleanup", original: saved.transcript, text: "Hello.")
        let restored = try PropertyListDecoder().decode(RecordingRecovery.self, from: PropertyListEncoder().encode(saved))
        XCTAssertEqual(restored.transcript, "Uh, hello.")
        XCTAssertEqual(restored.creditCleanupDraft?.original, restored.transcript)
        XCTAssertEqual(restored.creditCleanupDraft?.text, "Hello.")
        XCTAssertEqual(restored.creditCleanupDraft?.requestID, "request-fixture-cleanup")
        saved.creditCleanupDraft = nil
        let legacy = try PropertyListDecoder().decode(RecordingRecovery.self, from: PropertyListEncoder().encode(saved))
        XCTAssertNil(legacy.creditCleanupDraft)
    }

    func testInitialFillerRemovalDoesNotChangeExactSpellings() throws {
        for source in ["Uh, iPhone is fine.", "Uh, https://example.com is fine.", "Uh, person@example.com is fine."] {
            let plan = try XCTUnwrap(JevCleanupPlan(text: source, dictionary: "", allowFastPath: false))
            XCTAssertEqual(try plan.finish(response(for: plan)).text, String(source.dropFirst(4)))
        }
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, ios is fine.", dictionary: "- iOS\n", allowFastPath: false))
        XCTAssertEqual(try plan.finish(response(for: plan)).text, "iOS is fine.")
    }

    func testDictionaryAndHesitationEditsPreserveMeaningfulWords() throws {
        let source = "Uh, send type safe the probably necessary update."
        let plan = try XCTUnwrap(JevCleanupPlan(text: source, dictionary: "- TypeSafe\n", allowFastPath: true))
        XCTAssertEqual(plan.candidates.map(\.original), ["Uh", "type safe"])
        let result = try plan.finish(response(for: plan))
        XCTAssertEqual(result.text, "Send TypeSafe the probably necessary update.")
        XCTAssertTrue(result.canSkipRewrite)
    }

    func testExplicitDictionaryCorrectionAndUnicodeOffsets() throws {
        let source = "🎉 Ähm, schicke Jef die Datei."
        let dictionary = "- Jev\n  - Replaces: \"Jef\"\n"
        let plan = try XCTUnwrap(JevCleanupPlan(text: source, dictionary: dictionary, allowFastPath: false))
        XCTAssertEqual(try plan.finish(response(for: plan)).text, "🎉 schicke Jev die Datei.")
        XCTAssertFalse(try plan.finish(response(for: plan)).canSkipRewrite)
    }

    func testUncertainAndRejectedEditsAreKeptAndPreventFastPathWhenUncertain() throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Ha, um, that is funny.", dictionary: "", allowFastPath: true))
        var values = Dictionary(uniqueKeysWithValues: plan.candidates.map { ($0.id, 0.0) })
        values[plan.candidates.first(where: { $0.original == "um" })!.id] = 0.6
        let result = try plan.finish(response(for: plan, values: values))
        XCTAssertEqual(result.text, "Ha, um, that is funny.")
        XCTAssertFalse(result.canSkipRewrite)
    }

    func testQuotedCodeURLsAndPlaceholdersAreNeverEditCandidates() throws {
        let source = #"Say "uh" and `um`; https://example.com/uh __S2T_CLIPBOARD_0__ person@um.com. Probably just keep this."#
        let plan = try XCTUnwrap(JevCleanupPlan(text: source, dictionary: "- UH\n- UM\n", allowFastPath: true))
        XCTAssertTrue(plan.candidates.isEmpty)
        XCTAssertEqual(try plan.finish(response(for: plan)).text, source)
    }

    func testFillerOnlyAndSentencePunctuation() throws {
        for (source, expected) in [("Uh, um.", ""), ("Send it um.", "Send it."), ("Keep it, uh, tomorrow.", "Keep it, tomorrow.")] {
            let plan = try XCTUnwrap(JevCleanupPlan(text: source, dictionary: "", allowFastPath: false))
            XCTAssertEqual(try plan.finish(response(for: plan)).text, expected)
        }
    }

    func testOverlappingDictionaryAlternativesNeverApplyTogether() throws {
        XCTAssertNil(JevCleanupPlan(text: "Ask Jef today.", dictionary: "- Jev\n  - Replaces: \"Jef\"\n- Jeff\n  - Replaces: \"Jef\"\n", allowFastPath: true))
    }

    func testBoundsAndUnsupportedDictionaryNotesDisableShortcut() throws {
        XCTAssertNil(JevCleanupPlan(text: String(repeating: "uh ", count: 5000), dictionary: "", allowFastPath: true))
        XCTAssertNil(JevCleanupPlan(text: String(repeating: "uh ", count: 60), dictionary: "", allowFastPath: true))
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "Always use formal German wording.", allowFastPath: true))
        XCTAssertFalse(try plan.finish(response(for: plan)).canSkipRewrite)
    }

    func testMalformedMissingAndExtraDecisionsRejectWholeResult() throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: true))
        for json in [#"{"model":"jev-1.13.0","answers":{}}"#,
                     #"{"model":"jev-1.13.0","answers":{"edit0":{"type":"noul","noul":1.1},"simple":{"type":"noul","noul":1}}}"#,
                     #"{"model":"jev-1.13.0","answers":{"edit0":{"type":"choice","noul":1},"simple":{"type":"noul","noul":1}}}"#] {
            XCTAssertThrowsError(try plan.finish(JSONDecoder().decode(JevCleanupResponse.self, from: Data(json.utf8))))
        }
    }

    func testRequestUsesOnlyTypeSafeKeyAndBoundedStructuredEdits() async throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: true))
        let json = String(decoding: try JSONEncoder().encode(response(for: plan)), as: UTF8.self)
        let transport = ScriptedTransport([.init(path: "/v1/systemone", status: 200, json: json)])
        let result = try await DictationAPI(transport: transport).cleanWithJev(plan, apiKey: "typesafe-fixture")
        XCTAssertEqual(result.text, "Hello.")
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.host, "api.typesafe.ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer typesafe-fixture")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertLessThanOrEqual(request.timeoutInterval, 3)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "jev-1.13.0")
        XCTAssertNotNil(body["questions"])
        XCTAssertNil(body["messages"])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        XCTAssertEqual(state["editing_preferences"] as? String, WritingMode.defaultEditingInstruction)
    }

    func testCustomPreferencesReachTheDecisionModel() throws {
        let preferences = "Keep hesitation words. Preserve my casual wording."
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: false, editingPreferences: preferences))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.requestBody()) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        XCTAssertEqual(state["editing_preferences"] as? String, preferences)
        let result = try plan.finish(response(for: plan, values: ["edit0": 0]))
        XCTAssertEqual(result.text, "Uh, hello.")
        XCTAssertFalse(result.canSkipRewrite)
    }

    func testFastPathChecksDictionaryTermsOutsideLocalCandidates() throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Ask Jeff tomorrow.", dictionary: "- Jev\n  - Category: \"name\"\n", allowFastPath: true))
        XCTAssertTrue(plan.candidates.isEmpty)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.requestBody()) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        XCTAssertEqual(state["dictionary_spellings"] as? [String], ["Jev"])
        let result = try plan.finish(JevCleanupResponse(model: "jev-1.13.0", answers: ["simple": .init(type: "noul", noul: 0)]))
        XCTAssertFalse(result.canSkipRewrite)
        XCTAssertEqual(result.text, "Ask Jeff tomorrow.")
    }

    func testStalledJevRequestHasDeadlineAndCancelsTransport() async throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: false))
        let transport = StalledJevTransport()
        let start = Date()
        do {
            _ = try await DictationAPI(transport: transport).cleanWithJev(plan, apiKey: "fixture")
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 4.5)
        let cancelled = await transport.cancelled
        XCTAssertTrue(cancelled)
    }

    func testAccountFailureIsSanitizedAndCancellationStopsBeforeRequest() async throws {
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Uh, hello.", dictionary: "", allowFastPath: false))
        let transport = ScriptedTransport([.init(path: "/v1/systemone", status: 401, json: #"{"error":"secret transcript"}"#)])
        do {
            _ = try await DictationAPI(transport: transport).cleanWithJev(plan, apiKey: "fixture")
            XCTFail("Expected authentication failure")
        } catch { XCTAssertEqual(error as? ServiceError, .account(.typeSafe, status: 401)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DictationAPI(transport: transport).cleanWithJev(plan, apiKey: "fixture")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
    }

    private func response(for plan: JevCleanupPlan, values: [String: Double] = [:]) -> JevCleanupResponse {
        var answers = Dictionary(uniqueKeysWithValues: plan.candidates.map { ($0.id, JevCleanupResponse.Answer(type: "noul", noul: values[$0.id] ?? 1)) })
        if plan.allowFastPath { answers["simple"] = .init(type: "noul", noul: 1) }
        return JevCleanupResponse(model: "jev-1.13.0", answers: answers)
    }
}

private actor StalledJevTransport: HTTPTransport {
    private(set) var cancelled = false
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { try await Task.sleep(nanoseconds: 10_000_000_000) }
        catch { cancelled = true; throw error }
        throw URLError(.badServerResponse)
    }
}
