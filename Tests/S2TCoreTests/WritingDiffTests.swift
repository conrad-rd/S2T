import XCTest
@testable import S2TCore

final class WritingDiffTests: XCTestCase {
    private func assertRoundTrip(_ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) {
        let diff = WritingDiff(from: old, to: new)
        XCTAssertEqual(diff.segments.filter { $0.kind != .inserted }.map(\.text).joined(), old, file: file, line: line)
        XCTAssertEqual(diff.segments.filter { $0.kind != .removed }.map(\.text).joined(), new, file: file, line: line)
    }
    func testExactReconstructionForUnicodeWhitespaceAndRepeatedWords() {
        for (old, new) in [("", "α😀\r\nβ"), ("Delete me", ""), ("same", "same"),
            ("Keep all names intact.\n", "Keep every proper name intact.\n"),
            ("a b c a b", "a d c b a"), ("Hello,  world!\r\n", "Hello world.\n"),
            ("café 👩🏽‍💻\n中文", "Café 👩🏽‍💻\n中文!"), ("x\ty", "x y")] { assertRoundTrip(old, new) }
        let diff = WritingDiff(from: "Keep all names intact.", to: "Keep every proper name intact.")
        XCTAssertEqual(diff.changeCount, 1)
        XCTAssertEqual(diff.removedWords, 2)
        XCTAssertEqual(diff.insertedWords, 3)
    }
    func testLargeAndHighlyChangedDocumentsStayBoundedAndExact() {
        let original = String(repeating: "old word\n", count: 6_000)
        let revised = String(repeating: "new value\n", count: 6_000)
        let start = Date()
        assertRoundTrip(original, revised)
        assertRoundTrip(String(repeating: "a ", count: 16_000), String(repeating: "b ", count: 16_000))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testRulesPreserveManualSectionsAndDeduplicate() throws {
        let original = "# Instructions\r\nKeep exact.\r\n\n# My rules\n\n- Keep names\n\n# Other\nUnchanged\n"
        let result = try WritingRules.adding(["Keep names", "Use bullets", "Use bullets"], to: original)
        XCTAssertEqual(result, original.replacingOccurrences(of: "- Keep names\n", with: "- Keep names\n- Use bullets\n"))
        XCTAssertThrowsError(try WritingRules.adding(["KEEP NAMES"], to: result))
        XCTAssertThrowsError(try WritingRules.adding(["  "], to: original))
        XCTAssertThrowsError(try WritingRules.adding([String(repeating: "x", count: 601)], to: original))
        XCTAssertEqual(WritingRules.bullets(in: try WritingRules.adding(["Use\rplain\nwords"], to: "")), ["Use plain words"])
    }
    func testDictionarySpellingEditsPreserveContextCategoriesAndNotes() throws {
        let source = "# Dictionary\n\n- S2T\n  - Replaces: \"S to T\"\n  - Context: \"I use S2T\"\n  - Categories: [\"technology\"]\n  - Note: Keep this note\n\nManual paragraph.\n"
        let entry = try XCTUnwrap(DictionaryList.entries(in: source).first)
        let result = try DictionaryList.updating(id: entry.id, term: "S2T", context: "", replaces: "speech to tea", in: source)
        let updated = try XCTUnwrap(DictionaryList.entries(in: result).first)
        XCTAssertEqual(updated.learnedFrom, "speech to tea")
        XCTAssertEqual(updated.categories, ["technology"])
        XCTAssertEqual(updated.context, "")
        XCTAssertTrue(result.contains("  - Note: Keep this note"))
        XCTAssertTrue(result.hasSuffix("Manual paragraph.\n"))
        let cleared = try DictionaryList.updating(id: updated.id, term: "S2T", context: "", replaces: "", in: result)
        XCTAssertNil(DictionaryList.entries(in: cleared).first?.learnedFrom)
        XCTAssertEqual(DictionaryList.entries(in: cleared).first?.categories, ["technology"])
        let added = try DictionaryList.adding(term: "Codex", context: "Product", replaces: "codex", to: "")
        XCTAssertEqual(DictionaryList.entries(in: added).first?.learnedFrom, "codex")
        XCTAssertThrowsError(try DictionaryList.adding(term: "word", context: "", replaces: "bad\rentry", to: ""))
    }
}
