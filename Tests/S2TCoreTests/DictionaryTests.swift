import XCTest
@testable import S2TCore

final class DictionaryTests: XCTestCase {
    func testMultiwordPhraseReplacement() {
        XCTAssertEqual(words(original: "Use the old account name today", corrected: "Use our new company identity today"), ["our new company identity"])
        XCTAssertEqual(words(original: "Ask the sales team today", corrected: "Ask customer success today"), ["customer success"])
    }

    func testSingleWordDictationCorrection() {
        XCTAssertEqual(words(original: "yew", corrected: "you"), ["you"])
    }

    func testEditorWhitespaceDoesNotPreventObservation() {
        XCTAssertNotNil(DictionaryObservation(output: "Ask conrad today.\nUse cloud flair.", baseline: "Ask conrad today. Use cloud flair.", startedAt: 0))
    }
    private func words(original: String, corrected: String) -> [String] {
        DictionaryCorrections.entries(original: original, corrected: corrected).map(\.replacement)
    }
    func testSmallCorrectionsAndUnrelatedEdits() {
        XCTAssertEqual(words(original: "We use cloud flair daily", corrected: "We use Cloudflare daily"), ["Cloudflare"])
        XCTAssertEqual(words(original: "We use cloudflare daily", corrected: "We use Cloudflare daily"), ["Cloudflare"])
        XCTAssertEqual(words(original: "Send this to conrad today", corrected: "Send this to Konrad today"), ["Konrad"])
        XCTAssertEqual(words(original: "Send this to conrad today", corrected: "Send this to Konrad tomorrow"), ["Konrad tomorrow"])
        XCTAssertEqual(words(original: "Send this to conrad today", corrected: "Please deliver it somewhere tomorrow"), [])
        XCTAssertEqual(words(original: "Send this today", corrected: "Send this today please"), [])
        XCTAssertEqual(words(original: "Send this today.", corrected: "Send this today!"), [])
        XCTAssertEqual(words(original: "hello world", corrected: "other words"), ["other words"])
    }
    func testShortDictationAndSplitNames() {
        XCTAssertEqual(words(original: "Hello conrad", corrected: "Hello Konrad"), ["Konrad"])
        XCTAssertEqual(words(original: "Ask Maryann today", corrected: "Ask Mary Ann today"), ["Mary Ann"])
        XCTAssertEqual(words(original: "Send this today", corrected: "Send this tomorrow please"), ["tomorrow please"])
        XCTAssertEqual(words(original: "one", corrected: "something else"), ["something else"])
        XCTAssertEqual(words(original: "We use this daily", corrected: "We use daily"), [])
    }
    func testMultipleCorrections() {
        let entries = DictionaryCorrections.entries(original: "Use cloud flair, open router. Ask conrad today.", corrected: "Use Cloudflare, OpenRouter. Ask Konrad today.")
        XCTAssertEqual(entries.map(\.replacement), ["Cloudflare", "OpenRouter", "Konrad"])
        XCTAssertEqual(entries.map(\.original), ["cloud flair", "open router", "conrad"])
    }
    func testAdjacentCorrectionsAndSeparatePhrases() {
        XCTAssertEqual(DictionaryCorrections.entries(original: "Ask conrad meier today", corrected: "Ask Konrad Meyer today").map(\.replacement), ["Konrad Meyer"])
        XCTAssertEqual(DictionaryCorrections.entries(original: "Ask maryann, johnsmith today.", corrected: "Ask Mary Ann, John Smith today.").map(\.replacement), ["Mary Ann", "John Smith"])
        XCTAssertEqual(DictionaryCorrections.entries(original: "Use cloud flair and open router with conrad", corrected: "Use Cloudflare and OpenRouter with Konrad").map(\.replacement), ["Cloudflare", "OpenRouter", "Konrad"])
    }
    func testConsecutiveCorrectionsAndBoundedInput() {
        XCTAssertEqual(words(original: "Ask conrad meier schmidt today", corrected: "Ask Konrad Meyer Schmidt today"), ["Konrad Meyer Schmidt"])
        XCTAssertEqual(words(original: "Use cloudflare, openrouter, cerebras today.", corrected: "Use Cloudflare, OpenRouter, Cerebras today."), ["Cloudflare", "OpenRouter", "Cerebras"])
        XCTAssertEqual(words(original: String(repeating: "word ", count: 1100), corrected: String(repeating: "Word ", count: 1100)), [])
    }
    func testCorrectionsPersistWithUsageContext() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        let manual = "# My words\n\n- Konrad\n"
        _ = try file.read()
        try manual.write(to: file.url, atomically: true, encoding: .utf8)
        let entries = DictionaryCorrections.entries(original: "Ask conrad today", corrected: "Ask Konrad today")
        XCTAssertEqual(try file.append(entries), ["Konrad"])
        XCTAssertEqual(try file.append(entries), [])
        let reloaded = DictionaryFile(url: file.url)
        XCTAssertEqual(try reloaded.append(entries), [])
        XCTAssertTrue(try reloaded.read().hasPrefix(manual))
        XCTAssertTrue(try reloaded.prompt().contains("Ask Konrad today"))
        XCTAssertTrue(try reloaded.read().contains("Context:"))
        XCTAssertTrue(try reloaded.prompt().contains("conrad"))
    }
    func testLegacyContextAndManualNotesRemainUntouched() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        _ = try file.read()
        let source = "# My dictionary\n\nContext: personal notes\n- Manual phrase\n\n- Konrad\n  - Replaces: \"conrad\"\n  - Context: \"Ask Konrad today\"\n  - My pronunciation note\n"
        try source.write(to: file.url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try file.read(), source)
        XCTAssertEqual(try String(contentsOf: file.url, encoding: .utf8), source)
        XCTAssertTrue(try file.prompt().contains("Ask Konrad today"))
        let entries = DictionaryCorrections.entries(original: "Ask conrad today", corrected: "Ask Konrad today")
        XCTAssertEqual(try file.append(entries), [])
    }
    func testFilePreservesEditsAndDeduplicates() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        _ = try file.read()
        try "# My names\n\n- Konrad\n".write(to: file.url, atomically: true, encoding: .utf8)
        let entries = DictionaryCorrections.entries(original: "We use cerebras daily", corrected: "We use Cerebras daily")
        XCTAssertEqual(try file.append(entries + entries), ["Cerebras"])
        XCTAssertTrue(try file.read().hasPrefix("# My names\n\n- Konrad\n"))
        XCTAssertTrue(try file.prompt().contains("- Cerebras"))
    }

    func testStructuredListSortsAndPreservesMarkdownAndLearnedCorrections() throws {
        let source = """
        # Personal dictionary

        Keep this manual note.

        - GPT-6 Astra
          - Category: "common AI model"
        - Conrad
          - Category: "name"
        - Cloudflare
          - Replaces: "cloud flair"
          - Pronunciation note
        """
        let entries = DictionaryList.entries(in: source)
        XCTAssertEqual(entries.map(\.term), ["Cloudflare", "Conrad", "GPT-6 Astra"])
        XCTAssertEqual(entries.map(\.context), ["", "name", "common AI model"])
        XCTAssertEqual(entries.first?.learnedFrom, "cloud flair")

        let conrad = try XCTUnwrap(entries.first(where: { $0.term == "Conrad" }))
        let updated = try DictionaryList.updating(id: conrad.id, term: "Conrad Baulig", context: "person", in: source)
        XCTAssertTrue(updated.contains("# Personal dictionary"))
        XCTAssertTrue(updated.contains("Keep this manual note."))
        XCTAssertTrue(updated.contains("- Conrad Baulig\n  - Category: \"person\""))
        XCTAssertTrue(updated.contains("- Cloudflare\n  - Replaces: \"cloud flair\"\n  - Pronunciation note"))

        let added = try DictionaryList.adding(term: "OpenAI", context: "AI company", to: updated)
        XCTAssertEqual(DictionaryList.entries(in: added).map(\.term), ["Cloudflare", "Conrad Baulig", "GPT-6 Astra", "OpenAI"])
        let astra = try XCTUnwrap(DictionaryList.entries(in: added).first(where: { $0.term == "GPT-6 Astra" }))
        let removed = try DictionaryList.removing(id: astra.id, from: added)
        XCTAssertFalse(removed.contains("GPT-6 Astra"))
        XCTAssertTrue(removed.contains("Keep this manual note."))
    }
}

final class DictionarySuggestionTests: XCTestCase {
    func testRapidTypingContinuedPhraseAndUndoProduceCurrentCorrectionOnly() throws {
        var observed = try XCTUnwrap(DictionaryObservation(output: "Ask conrad today", baseline: "Ask conrad today", startedAt: 0))
        for (time, text) in [(0.0, "Ask Ko today"), (0.10, "Ask Kon today"), (0.18, "Ask Konrad today"), (0.30, "Ask Konrad today")] {
            guard case .waiting = observed.sample(text, at: time) else { return XCTFail("Saved during rapid typing") }
        }
        guard case .suggestions(let first, _) = observed.sample("Ask Konrad today", at: 0.4) else { return XCTFail("Missing completed correction") }
        XCTAssertEqual(first.map(\.replacement), ["Konrad"])
        _ = observed.sample("Ask Konrad Meyer today", at: 0.5)
        guard case .suggestions(let phrase, _) = observed.sample("Ask Konrad Meyer today", at: 0.71) else { return XCTFail("Missed continued phrase") }
        XCTAssertEqual(phrase.map(\.original), ["conrad"])
        XCTAssertEqual(phrase.map(\.replacement), ["Konrad Meyer"])
        _ = observed.sample("Ask conrad today", at: 1)
        guard case .suggestions(let reverted, _) = observed.sample("Ask conrad today", at: 1.21) else { return XCTFail("Missed undo") }
        XCTAssertTrue(reverted.isEmpty)
        _ = observed.sample("", at: 2)
        guard case .stopped = observed.sample("", at: 2.21) else { return XCTFail("Submitting the field should end observation") }
    }

    func testAtomicRevisionRetainsOldEntryIfNewEntryCannotBeSaved() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        let old = DictionaryCorrection(original: "name", replacement: "Konra")
        _ = try file.append([old])
        let saved = try file.read()
        let oversized = DictionaryCorrection(original: "name", replacement: String(repeating: "x", count: 70_000))
        XCTAssertThrowsError(try file.update(adding: [oversized], removing: [old]))
        XCTAssertEqual(try file.read(), saved)
    }

    func testFastCorrectionSettlesWithinQuarterSecond() throws {
        var observed = try XCTUnwrap(DictionaryObservation(output: "Ask conrad today", baseline: "Ask conrad today", startedAt: 0))
        var detected: Double?
        for tick in 0...200 {
            let time = Double(tick) / 100
            if case .suggestions = observed.sample("Ask Konrad today", at: time) { detected = time; break }
        }
        let latency = try XCTUnwrap(detected)
        print("Dictionary observer settling delay: \(latency) seconds")
        XCTAssertLessThanOrEqual(latency, 0.25)
    }
    func testSuggestionsDoNotWriteAndRemainActiveForSequentialEdits() throws {
        var observation = try XCTUnwrap(DictionaryObservation(output: "Ask conrad and maryann today", baseline: "📝 Ask conrad and maryann today", startedAt: 0))
        _ = observation.sample("📝 Ask Konrad and maryann today", at: 1)
        guard case .suggestions(let first, let range) = observation.sample("📝 Ask Konrad and maryann today", at: 2.5) else { return XCTFail("Missing first suggestion") }
        XCTAssertEqual(first.map(\.replacement), ["Konrad"])
        XCTAssertEqual(range.location, 3)
        _ = observation.sample("📝 Ask Konrad and Mary Ann today", at: 3)
        guard case .suggestions(let second, _) = observation.sample("📝 Ask Konrad and Mary Ann today", at: 4.5) else { return XCTFail("Missing next suggestion") }
        XCTAssertEqual(second.map(\.replacement), ["Konrad", "Mary Ann"])
        guard case .waiting = observation.sample("📝 Ask Konrad and Mary Ann today", at: 8) else { return XCTFail("Repeated suggestion") }
        guard case .stopped = observation.sample(nil, at: 9), case .stopped = observation.sample("📝 Ask Konrad and Mary Ann today", at: 10) else { return XCTFail("Resumed after field loss") }
    }

    func testRepeatedOutputUsesSelectionAndRejectsAmbiguity() {
        XCTAssertNil(DictionaryObservation(output: "hello", baseline: "hello hello", startedAt: 0))
        XCTAssertNotNil(DictionaryObservation(output: "hello", baseline: "hello hello", startedAt: 0, selection: NSRange(location: 11, length: 0)))
    }

    func testCorrectionCompletedBeforeBaselineAttaches() throws {
        var observed = try XCTUnwrap(DictionaryObservation(
            output: "Ask conrad today",
            baseline: "Ask Konrad today",
            startedAt: 0,
            selection: NSRange(location: 11, length: 0),
            insertionSelection: NSRange(location: 0, length: 0), insertionBaseline: ""
        ))
        guard case .waiting = observed.sample("Ask Konrad today", at: 0.1),
              case .suggestions(let entries, _) = observed.sample("Ask Konrad today", at: 0.21) else {
            return XCTFail("A correction made immediately after delivery was not detected")
        }
        XCTAssertEqual(entries.map(\.replacement), ["Konrad"])
    }

    func testSingleWordCorrectionCompletedBeforeBaselineAttaches() throws {
        var observed = try XCTUnwrap(DictionaryObservation(
            output: "conrad",
            baseline: "Konrad",
            startedAt: 0,
            selection: NSRange(location: 6, length: 0),
            insertionSelection: NSRange(location: 0, length: 0), insertionBaseline: ""
        ))
        guard case .suggestions(let entries, _) = observed.sample("Konrad", at: 0.21) else {
            return XCTFail("A corrected single-word delivery was not detected")
        }
        XCTAssertEqual(entries.map(\.replacement), ["Konrad"])
    }

    func testInsertionPositionDoesNotAttachToAnOlderOccurrenceWhilePasteIsPending() {
        XCTAssertNil(DictionaryObservation(output: "hello", baseline: "hello ", startedAt: 0,
            insertionSelection: NSRange(location: 6, length: 0)))
    }

    func testEarlyCorrectionUsesSurroundingTextForChangedLengthAndReplacedSelection() throws {
        var observed = try XCTUnwrap(DictionaryObservation(output: "Use cloud flair today.", baseline: "📝 Use Cloudflare today. End.", startedAt: 0,
            insertionSelection: NSRange(location: 3, length: 5), insertionBaseline: "📝 draft End."))
        guard case .suggestions(let entries, let range) = observed.sample("📝 Use Cloudflare today. End.", at: 0.21) else {
            return XCTFail("Early correction with a different length was missed")
        }
        XCTAssertEqual(entries.map(\.replacement), ["Cloudflare"])
        XCTAssertEqual(range.location, 3)
        XCTAssertFalse(entries[0].context.contains("End."))
        XCTAssertNil(DictionaryObservation(output: "new word", baseline: "old word", startedAt: 0,
            insertionSelection: NSRange(location: 0, length: 8), insertionBaseline: "old word"))
        XCTAssertNil(DictionaryObservation(output: "new word", baseline: "old word", startedAt: 0,
            insertionSelection: NSRange(location: 0, length: 0)))
    }

    func testRepeatedSingleWordUsesRecordedInsertionWithoutCaretMetadata() {
        XCTAssertNotNil(DictionaryObservation(
            output: "hello",
            baseline: "hello hello",
            startedAt: 0,
            insertionSelection: NSRange(location: 6, length: 0)
        ))
    }

    func testConfirmDeduplicateAndRemovePreservesManualEdits() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        _ = try file.read()
        let manual = "# My dictionary\n\n- you\n- Manual phrase\n"
        try manual.write(to: file.url, atomically: true, encoding: .utf8)
        let entry = DictionaryCorrection(original: "yew", replacement: "you")
        XCTAssertEqual(try file.append([entry]), ["you"])
        XCTAssertEqual(try file.append([DictionaryCorrection(original: "yew", replacement: "you")]), [])
        var edited = try file.read()
        edited += "\nPersonal note added later.\n"
        try edited.write(to: file.url, atomically: true, encoding: .utf8)
        XCTAssertTrue(try file.remove(entry))
        XCTAssertFalse(try file.contains(entry))
        let content = try file.read()
        XCTAssertTrue(content.hasPrefix(manual))
        XCTAssertTrue(content.hasSuffix("Personal note added later.\n"))
        XCTAssertFalse(content.contains("Replaces:"))
        XCTAssertFalse(try file.remove(entry))
    }
}
