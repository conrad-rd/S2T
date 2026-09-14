import XCTest
@testable import S2TCore

final class DictionaryTests: XCTestCase {
    func testSmallCorrectionsAndUnrelatedEdits() {
        XCTAssertEqual(DictionaryCorrections.words(original: "We use cloud flair daily", corrected: "We use Cloudflare daily"), [])
        XCTAssertEqual(DictionaryCorrections.words(original: "We use cloudflare daily", corrected: "We use Cloudflare daily"), ["Cloudflare"])
        XCTAssertEqual(DictionaryCorrections.words(original: "Send this to conrad today", corrected: "Send this to Konrad today"), ["Konrad"])
        XCTAssertEqual(DictionaryCorrections.words(original: "Send this to conrad today", corrected: "Send this to Konrad tomorrow"), ["Konrad", "tomorrow"])
        XCTAssertEqual(DictionaryCorrections.words(original: "Send this to conrad today", corrected: "Please deliver it somewhere tomorrow"), [])
        XCTAssertEqual(DictionaryCorrections.words(original: "Send this today", corrected: "Send this today please"), [])
        XCTAssertEqual(DictionaryCorrections.words(original: "Send this today.", corrected: "Send this today!"), [])
        XCTAssertEqual(DictionaryCorrections.words(original: "hello world", corrected: "other words"), [])
    }
    func testFilePreservesEditsAndDeduplicates() throws {
        let file = DictionaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("dictionary.md"))
        _ = try file.read()
        try "# My names\n\n- Konrad\n".write(to: file.url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try file.append(["Konrad", "Cerebras", "Cerebras"]), ["Cerebras"])
        XCTAssertTrue(try file.read().hasPrefix("# My names\n\n- Konrad\n"))
        XCTAssertTrue(try file.prompt().contains("- Cerebras"))
    }
}
