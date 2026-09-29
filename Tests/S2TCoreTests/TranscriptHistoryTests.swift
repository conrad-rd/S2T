import XCTest
import CryptoKit
@testable import S2TCore

final class TranscriptHistoryTests: XCTestCase {
    func testMigrationEncryptsRedactsAndRemovesLegacyOnlyAfterSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent("history.json"), file = folder.appendingPathComponent("history.enc")
        let secret = "sk-proj-" + String(repeating: "a", count: 30)
        let old = RecentTranscript(id: UUID(), date: Date(), text: "Use " + secret, appName: "Editor", bundleID: nil)
        try JSONEncoder().encode([old]).write(to: legacy)
        let blocked = TranscriptHistoryStore(file: file, legacyFile: legacy, key: { throw CocoaError(.fileReadNoPermission) })
        XCTAssertThrowsError(try blocked.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        let store = TranscriptHistoryStore(file: file, legacyFile: legacy, key: { Data(repeating: 42, count: 32) })
        let migrated = try store.load()
        XCTAssertEqual(migrated.first?.text, "Use [API key]")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertNil(try Data(contentsOf: file).range(of: Data("Use ".utf8)))
        XCTAssertEqual(try store.load(), migrated)
    }

    func testCorruptArchivesDoNotDisableNewSavesAndPlaintextBackupIsEncrypted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("history.enc"), legacy = folder.appendingPathComponent("history.json")
        let bytes = Data("broken private plaintext archive".utf8)
        try bytes.write(to: legacy)
        try Data([1]).write(to: file)
        let store = TranscriptHistoryStore(file: file, legacyFile: legacy, key: { Data(repeating: 42, count: 32) })
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertNotNil(store.notice)
        let new = RecentTranscript(id: UUID(), date: Date(), text: "New entry", appName: nil, bundleID: nil)
        try store.save([new])
        XCTAssertEqual(try store.load(), [new])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for url in files { XCTAssertNil(try Data(contentsOf: url).range(of: bytes)) }
        try store.clear()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).isEmpty)
    }

    func testLegacyMigrationRedactsAllRecognizedCredentialFormats() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent("history.json"), file = folder.appendingPathComponent("history.enc")
        let prefixes = ["csk-", "xai-", "sk-or-v1-", "sk-ant-", "sk-proj-", "sk-", "s2t_live_", "s2t_test_", "s2t_demo_"]
        let now = Date()
        let entries = prefixes.enumerated().map { index, prefix in
            RecentTranscript(id: UUID(), date: now.addingTimeInterval(-Double(index)),
                text: "Use " + prefix + String(repeating: "a", count: 30), appName: "Editor", bundleID: nil)
        }
        try JSONEncoder().encode(entries).write(to: legacy)
        let key = Data(repeating: 42, count: 32)
        let store = TranscriptHistoryStore(file: file, legacyFile: legacy, key: { key })
        XCTAssertEqual(try store.load(at: now).map(\.text), Array(repeating: "Use [API key]", count: prefixes.count))
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
        let persisted = try JSONDecoder().decode([RecentTranscript].self, from: AES.GCM.open(sealed, using: SymmetricKey(data: key)))
        XCTAssertTrue(persisted.allSatisfy { $0.text == "Use [API key]" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testRetentionBoundAndCopiedValueRedaction() throws {
        let now = Date()
        let entries = (0..<510).map { RecentTranscript(id: UUID(), date: now.addingTimeInterval(-Double($0)), text: "Entry \($0)", appName: nil, bundleID: nil) }
        let expired = RecentTranscript(id: UUID(), date: now.addingTimeInterval(-31 * 86400), text: "Expired", appName: nil, bundleID: nil)
        let kept = TranscriptHistoryStore.bounded(entries + [expired], at: now)
        XCTAssertEqual(kept.count, 500)
        XCTAssertFalse(kept.contains { $0.id == expired.id })
        XCTAssertEqual(TranscriptPrivacy.redacted("Include secret-private-material", copiedValues: ["secret-private-material"]), "Include [Copied content]")
    }
}
