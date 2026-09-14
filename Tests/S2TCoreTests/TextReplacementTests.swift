import XCTest
@testable import S2TCore

final class TextReplacementTests: XCTestCase {
    func testSearchFieldInsertionPreservesExistingQuery() {
        XCTAssertEqual(TextReplacement.apply("tomorrow", to: "calendar ", selection: NSRange(location: 9, length: 0)), "calendar tomorrow")
    }
    func testOnlySelectedTextIsReplaced() {
        XCTAssertEqual(TextReplacement.apply("Thursday", to: "meet Friday morning", selection: NSRange(location: 5, length: 6)), "meet Thursday morning")
    }
    func testAccessibilitySelectionUsesUTF16Offsets() {
        XCTAssertEqual(TextReplacement.apply("hello", to: "🎙 test", selection: NSRange(location: 3, length: 4)), "🎙 hello")
        XCTAssertNil(TextReplacement.apply("x", to: "🎙", selection: NSRange(location: 1, length: 0)))
    }
    func testInvalidOrStaleSelectionDoesNotOverwriteText() {
        XCTAssertNil(TextReplacement.apply("x", to: "old", selection: NSRange(location: NSNotFound, length: 0)))
        XCTAssertNil(TextReplacement.apply("x", to: "old", selection: NSRange(location: 4, length: 0)))
        XCTAssertNil(TextReplacement.apply("x", to: "old", selection: NSRange(location: 2, length: Int.max)))
    }
}
