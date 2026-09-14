import XCTest
@testable import S2TCore

final class ClipboardPersistenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 200_000)
    private let key = Data(repeating: 42, count: 32)

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("history.enc")
    }

    func testReopeningEncryptedHistoryPreservesTextDatesAndClipboardCheckpoint() throws {
        let file = url()
        var history = ClipboardHistory()
        history.record("copied fixture text", at: now)
        history.record("sk-or-v1-" + String(repeating: "a", count: 40), at: now.addingTimeInterval(1))
        let archive = ClipboardArchive(history: history, changeCount: 27, fingerprint: "fixture digest")
        try ClipboardHistoryStore(url: file, key: { self.key }).save(archive)
        let reopened = try ClipboardHistoryStore(url: file, key: { self.key }).load(at: now.addingTimeInterval(47 * 3600))
        XCTAssertEqual(reopened.history.entries, history.entries)
        XCTAssertEqual(reopened.changeCount, 27)
        XCTAssertEqual(reopened.fingerprint, "fixture digest")
        let bytes = try Data(contentsOf: file)
        for entry in history.entries { XCTAssertNil(bytes.range(of: Data(entry.text.utf8))) }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testExpirationSurvivesRelaunchWithoutResettingCopyDates() throws {
        let file = url()
        let store = ClipboardHistoryStore(url: file, key: { self.key })
        var history = ClipboardHistory()
        history.record("old", at: now)
        history.record("new", at: now.addingTimeInterval(3600))
        try store.save(ClipboardArchive(history: history))
        let restored = try store.load(at: now.addingTimeInterval(48 * 3600 + 1))
        XCTAssertEqual(restored.history.entries.map(\.text), ["new"])
        XCTAssertEqual(restored.history.entries.first?.copiedAt, now.addingTimeInterval(3600))
    }

    func testEqualCopyDatesKeepNewestFirstOrdering() throws {
        var history = ClipboardHistory()
        for text in ["first", "second", "third"] { history.record(text, at: now) }
        let store = ClipboardHistoryStore(url: url(), key: { self.key })
        try store.save(ClipboardArchive(history: history))
        XCTAssertEqual(try store.load(at: now).history.entries.map(\.text), ["third", "second", "first"])
    }

    func testClearRemainsEmptyAfterReopening() throws {
        let store = ClipboardHistoryStore(url: url(), key: { self.key })
        var history = ClipboardHistory()
        history.record("clear fixture", at: now)
        try store.save(ClipboardArchive(history: history))
        try store.save(ClipboardArchive(changeCount: 12, fingerprint: "cleared clipboard"))
        let reopened = try store.load(at: now)
        XCTAssertTrue(reopened.history.entries.isEmpty)
        XCTAssertEqual(reopened.fingerprint, "cleared clipboard")
    }

    func testMissingHistoryDoesNotNeedKeyAndWrongKeyDoesNotAlterSavedFile() throws {
        let file = url()
        let empty = try ClipboardHistoryStore(url: file, key: { throw CocoaError(.fileReadNoPermission) }).load(at: now)
        XCTAssertTrue(empty.history.entries.isEmpty)
        let store = ClipboardHistoryStore(url: file, key: { self.key })
        var history = ClipboardHistory()
        history.record("saved fixture", at: now)
        try store.save(ClipboardArchive(history: history))
        let saved = try Data(contentsOf: file)
        XCTAssertThrowsError(try ClipboardHistoryStore(url: file, key: { Data(repeating: 99, count: 32) }).load(at: now))
        XCTAssertEqual(try Data(contentsOf: file), saved)
        XCTAssertEqual(try store.load(at: now).history.entries, history.entries)
    }
}
