import XCTest
@testable import S2TCore

final class DictionaryLearningTests: XCTestCase {
    func testReturningToLastStableEditResubmitsCancelledJudgment() throws {
        var observation = try XCTUnwrap(DictionaryObservation(output: "Ask conrad today", baseline: "Ask conrad today", startedAt: 0))
        _ = observation.sample("Ask Konrad today", at: 1)
        guard case .suggestions = observation.sample("Ask Konrad today", at: 1.25) else { return XCTFail("No initial correction") }
        _ = observation.sample("Ask Konrady today", at: 1.3)
        _ = observation.sample("Ask Konrad today", at: 1.4)
        guard case .suggestions(let entries, _) = observation.sample("Ask Konrad today", at: 1.65) else {
            return XCTFail("A transient edit cancelled the request permanently")
        }
        XCTAssertEqual(entries.first?.replacement, "Konrad")
    }
    func testPersonalAndCreditConnectionsUseOnlyTheirOwnKeyAndCreditReplayIsStable() async throws {
        let transport = DictionaryDecisionTransport()
        let plan = try plan()
        guard case .accepted(let direct) = try await DictationAPI(transport: transport).learnDictionaryCorrection(plan, apiKey: "fake-router-key") else {
            return XCTFail("Personal OpenRouter learning did not finish")
        }
        XCTAssertEqual(direct.categories, ["c021"])
        guard case .accepted(let jev) = try await DictationAPI(transport: transport).learnDictionaryCorrection(plan, apiKey: "fake-jev-key", route: .typeSafe) else {
            return XCTFail("Direct Jev categorization did not finish")
        }
        XCTAssertEqual(jev, direct)
        let key = "s2t_demo_" + String(repeating: "d", count: 64)
        let connection = try CreditConnection(address: "http://localhost:4317", key: key)
        for _ in 0..<2 {
            guard case .accepted(let paid) = try await CreditsAPI(transport: transport).learnDictionaryCorrection(plan, connection: connection, requestID: "fixture-learning") else {
                return XCTFail("S2T learning did not finish")
            }
            XCTAssertEqual(paid, direct)
        }
        let requests = await transport.requests
        let personal = requests.filter { $0.url?.host == "openrouter.ai" }
        let jevRequests = requests.filter { $0.url?.host == "api.typesafe.ai" }
        let paid = requests.filter { $0.url?.host == "localhost" }
        XCTAssertEqual(personal.count, 3)
        XCTAssertEqual(jevRequests.count, 3)
        XCTAssertTrue(jevRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fake-jev-key" && $0.url?.path == "/v1/systemone" })
        XCTAssertEqual(paid.count, 6)
        XCTAssertTrue(personal.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fake-router-key" && $0.url?.path == "/api/alpha/decisions" })
        XCTAssertTrue(paid.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + key })
        let identities = paid.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(Set(identities).count, 3)
        XCTAssertTrue(Set(identities).allSatisfy { id in identities.filter { $0 == id }.count == 2 })
    }

    func testOnlyFailedBatchRetriesAndCancellationDoesNotRetry() async throws {
        let transport = DictionaryDecisionTransport(failOnce: true)
        let result = try await DictationAPI(transport: transport).learnDictionaryCorrection(plan(), apiKey: "fake")
        guard case .accepted = result else { return XCTFail("Transient failure did not recover") }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 4)
        let task = Task { try await DictationAPI(transport: transport).learnDictionaryCorrection(plan(), apiKey: "fake") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled learning succeeded") } catch { }
        let after = await transport.requests.count
        XCTAssertEqual(after, 4)
    }

    func testContextReachesNormalCleanupAndJevCleanupWithoutGlobalReplacement() throws {
        let dictionary = "- Cloudflare\n  - Replaces: \"cloud flair\"\n  - Context: \"Use Cloudflare for DNS.\"\n  - Categories: [\"c021\",\"c030\"]\n"
        let plan = try XCTUnwrap(JevCleanupPlan(text: "Use cloud flair for DNS.", dictionary: dictionary, allowFastPath: false))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: plan.requestBody()) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        let reference = try XCTUnwrap(state["dictionary_reference"] as? String)
        XCTAssertTrue(reference.contains("Use Cloudflare for DNS."))
        XCTAssertTrue(reference.contains("Cloud services"))
        XCTAssertTrue(reference.contains("never as a global substitution"))
    }
    func testExactCorrectionsIncludeDigitsAndPreserveSpacingAndContext() throws {
        let entries = DictionaryCorrections.entries(original: "Please use gpt 5 with cloud flair today.", corrected: "Please use GPT-6 with Cloudflare today.")
        XCTAssertEqual(entries.map(\.original), ["gpt 5", "cloud flair"])
        XCTAssertEqual(entries.map(\.replacement), ["GPT-6", "Cloudflare"])
        XCTAssertTrue(entries.allSatisfy { $0.context.contains("GPT-6") && $0.context.contains("Cloudflare") })
        let joined = DictionaryCorrections.entries(original: "Ask Maryann today.", corrected: "Ask Mary  Ann today.")
        XCTAssertEqual(joined.first?.replacement, "Mary  Ann")
        XCTAssertEqual(DictionaryCorrections.entries(original: "Ship version 5 today.", corrected: "Ship version 6 today.").first?.replacement, "6")
    }

    func testAllOneHundredCategoriesAreJudgedWithinExistingCreditLimits() throws {
        XCTAssertEqual(DictionaryCategory.all.count, 100)
        XCTAssertEqual(Set(DictionaryCategory.all.map(\.id)).count, 100)
        let plan = try plan()
        let bodies = try plan.requestBodies()
        if let path = ProcessInfo.processInfo.environment["S2T_DICTIONARY_REQUEST_FIXTURE"] {
            let fixtures = try bodies.map { try JSONSerialization.jsonObject(with: $0) }
            try JSONSerialization.data(withJSONObject: fixtures).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        XCTAssertEqual(bodies.count, 3)
        var questions = 0
        for data in bodies {
            XCTAssertLessThanOrEqual(data.count, 65_536)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "typesafe/jev-1.13")
            let batch = try XCTUnwrap(json["questions"] as? [String: Any])
            XCTAssertLessThanOrEqual(batch.count, 49)
            XCTAssertTrue(batch.keys.allSatisfy { $0.range(of: #"^edit[0-9]{1,2}$"#, options: .regularExpression) != nil })
            questions += batch.count
        }
        XCTAssertEqual(questions, 101)
    }

    func testAcceptsOnlyValidatedCorrectionsAndOneBestKnownCategory() throws {
        let plan = try plan()
        let accepted = try plan.finish(responses(approval: 0.995, categories: [0: 0.99, 1: 0.98, 2: 0.95, 3: 0.9]))
        guard case .accepted(let entry) = accepted else { return XCTFail("Valid correction rejected") }
        XCTAssertEqual(entry.original, "cloud flair")
        XCTAssertEqual(entry.replacement, "Cloudflare")
        XCTAssertEqual(entry.context, "Use Cloudflare for DNS.")
        XCTAssertEqual(entry.categories, [DictionaryCategory.all[0].id])
        guard case .uncertain = try plan.finish(responses(approval: 0.7, categories: [0: 1])) else { return XCTFail("Uncertain edit saved") }
        guard case .rejected = try plan.finish(responses(approval: 0.01, categories: [0: 1])) else { return XCTFail("Changed intent saved") }
        guard case .uncertain = try plan.finish(responses(approval: 1, categories: [:])) else { return XCTFail("Unclassified edit saved") }
    }

    func testMalformedAndIncompleteDecisionsNeverSave() throws {
        let plan = try plan()
        var values = responses(approval: 1, categories: [0: 1])
        values[1] = JevCleanupResponse(model: "typesafe/jev-1.13", answers: [:])
        XCTAssertThrowsError(try plan.finish(values))
        XCTAssertThrowsError(try plan.finish(Array(values.prefix(1))))
        values = responses(approval: 1, categories: [0: 1])
        values[2] = JevCleanupResponse(model: "some-other-model", answers: values[2].answers)
        XCTAssertThrowsError(try plan.finish(values))
    }

    func testLocalCorrectionDoesNotDuplicateAnAlreadyCategorizedEntry() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        let categorized = DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare for DNS.", categories: ["c021"])
        _ = try file.append([categorized])
        let originalFile = try file.read()
        let local = DictionaryCorrection(original: categorized.original, replacement: categorized.replacement, context: categorized.context)
        XCTAssertEqual(try file.append([local]), [])
        XCTAssertEqual(try file.read(), originalFile)
        XCTAssertEqual(DictionaryList.entries(in: try file.read()).count, 1)
    }

    func testContextCategoriesSurviveReloadAndManualEditing() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        let entry = DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare for DNS.", categories: ["c021", "c030"])
        XCTAssertEqual(try file.append([entry]), ["Cloudflare"])
        XCTAssertEqual(try file.append([entry]), [])
        let saved = try file.read()
        XCTAssertTrue(saved.contains("Context: \"Use Cloudflare for DNS.\""))
        XCTAssertTrue(saved.contains("Categories: [\"c021\",\"c030\"]"))
        let row = try XCTUnwrap(DictionaryList.entries(in: saved).first)
        XCTAssertEqual(row.context, entry.context)
        XCTAssertEqual(row.categories, entry.categories)
        let revised = try DictionaryList.updating(id: row.id, term: row.term, context: "My DNS service", in: saved)
        XCTAssertTrue(revised.contains("Context: \"My DNS service\""))
        XCTAssertTrue(revised.contains("Categories: [\"c021\",\"c030\"]"))
        XCTAssertTrue(DictionaryFile.prompt(content: saved).contains("Cloud services"))
    }

    func testContextualDuplicatesRemainEditableAndManualMetadataCannotBePartiallyRemoved() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        let first = DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare for DNS.", categories: ["c021"])
        let second = DictionaryCorrection(original: "cloud flare", replacement: "Cloudflare", context: "Use Cloudflare for storage.", categories: ["c021"])
        _ = try file.append([first, second])
        let source = try file.read()
        let row = try XCTUnwrap(DictionaryList.entries(in: source).first)
        let revised = try DictionaryList.updating(id: row.id, term: row.term, context: "My hosting provider", in: source)
        XCTAssertTrue(revised.contains("My hosting provider"))
        XCTAssertFalse(try file.remove(DictionaryCorrection(original: first.original, replacement: first.replacement)))
        XCTAssertEqual(try file.read(), source)
    }

    private func plan() throws -> DictionaryLearningPlan {
        try DictionaryLearningPlan(correction: DictionaryCorrection(original: "cloud flair", replacement: "Cloudflare", context: "Use Cloudflare for DNS."))
    }

    private func responses(approval: Double, categories: [Int: Double]) -> [JevCleanupResponse] {
        let probabilities = [approval] + (0..<100).map { categories[$0] ?? 0 }
        return stride(from: 0, to: probabilities.count, by: 49).map { offset in
            JevCleanupResponse(model: "jev-1.13.0", answers: Dictionary(uniqueKeysWithValues:
                probabilities[offset..<min(offset + 49, probabilities.count)].enumerated().map {
                    ("edit\($0.offset)", JevCleanupResponse.Answer(type: "noul", noul: $0.element))
                }))
        }
    }
}

private actor DictionaryDecisionTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var failOnce: Bool
    init(failOnce: Bool = false) { self.failOnce = failOnce }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if failOnce { failOnce = false; throw URLError(.networkConnectionLost) }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let credit = request.url?.host == "localhost"
        if credit {
            XCTAssertEqual(json["operation"] as? String, "decisions")
            XCTAssertNil(json["host"])
            json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data((json["text"] as! String).utf8)) as? [String: Any])
        }
        XCTAssertEqual(json["model"] as? String, request.url?.host == "api.typesafe.ai" ? "jev-1.13.0" : "typesafe/jev-1.13")
        let questions = try XCTUnwrap(json["questions"] as? [String: [String: Any]])
        let answers = questions.mapValues { value -> [String: Any] in
            let question = value["instructions"] as! String
            return ["type": "noul", "noul": question.contains("Did the user replace") || question.contains("'Cloud services'") ? 0.999 : 0.001]
        }
        let response = try JSONSerialization.data(withJSONObject: ["model": "jev-1.13.0", "answers": answers])
        let data = credit ? try JSONSerialization.data(withJSONObject: ["state": "settled", "result": ["text": String(decoding: response, as: UTF8.self), "model": "typesafe/jev-1.13"]]) : response
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
