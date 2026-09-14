import XCTest
@testable import S2TCore

final class CredentialVaultTests: XCTestCase {
    private final class Storage {
        var items: [String: String] = [:]
        var reads: [(String, Bool)] = []
        var writes = 0
        var locked = Set<String>()
        var rejectWrites = false
        enum Failure: Error { case locked }
        func vault() -> CredentialVault {
            CredentialVault(read: { account, interaction in
                self.reads.append((account, interaction))
                if self.locked.contains(account), !interaction { throw Failure.locked }
                return self.items[account]
            }, write: { account, value, _ in
                if self.rejectWrites { throw Failure.locked }
                self.writes += 1
                self.items[account] = value
            })
        }
    }

    func testExistingKeysMigrateWithoutPromptsOrDeletingOriginals() throws {
        let storage = Storage()
        let original = ["assemblyai": "fixture-a", "openrouter": "fixture-b", "elevenlabs": "fixture-c", "cerebras": "fixture-d", "clipboard-history-encryption": "fixture-encryption"]
        storage.items = original
        let vault = storage.vault()
        for (account, value) in original { XCTAssertEqual(try vault.read(account, allowInteraction: false), value) }
        XCTAssertTrue(storage.reads.allSatisfy { !$0.1 })
        for (account, value) in original { XCTAssertEqual(storage.items[account], value) }
        storage.reads = []
        let relaunched = storage.vault()
        for (account, value) in original { XCTAssertEqual(try relaunched.read(account, allowInteraction: true), value) }
        XCTAssertEqual(storage.reads.count, 1)
        XCTAssertEqual(storage.reads.first?.0, CredentialVault.account)
    }

    func testLockedVaultDoesNotFallBackOrOverwriteAndCanBeRetried() throws {
        let storage = Storage()
        storage.items[CredentialVault.account] = #"{"openrouter":"fixture-secret"}"#
        storage.locked.insert(CredentialVault.account)
        let vault = storage.vault()
        XCTAssertThrowsError(try vault.read("openrouter", allowInteraction: false))
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(try vault.read("openrouter", allowInteraction: true), "fixture-secret")
        XCTAssertEqual(storage.reads.count, 2)
    }

    func testFailedSavePreservesOtherCredentialsAndDoesNotCacheUnsavedValue() throws {
        let storage = Storage()
        storage.items[CredentialVault.account] = #"{"openrouter":"original","cerebras":"other"}"#
        let vault = storage.vault()
        storage.rejectWrites = true
        XCTAssertThrowsError(try vault.save("edited", account: "openrouter", allowInteraction: false))
        XCTAssertEqual(try vault.read("openrouter", allowInteraction: false), "original")
        storage.rejectWrites = false
        try vault.save("edited", account: "openrouter", allowInteraction: false)
        let relaunched = storage.vault()
        XCTAssertEqual(try relaunched.read("openrouter", allowInteraction: false), "edited")
        XCTAssertEqual(try relaunched.read("cerebras", allowInteraction: false), "other")
    }

    func testCorruptVaultIsNeverReplacedWithEmptyCredentials() throws {
        let storage = Storage()
        storage.items[CredentialVault.account] = "broken"
        let vault = storage.vault()
        XCTAssertThrowsError(try vault.save("edited", account: "openrouter", allowInteraction: false))
        XCTAssertEqual(storage.items[CredentialVault.account], "broken")
        XCTAssertEqual(storage.writes, 0)
    }

    func testMigrationWriteFailureStillReturnsReadableLegacyKey() throws {
        let storage = Storage()
        storage.items["openrouter"] = "original"
        storage.rejectWrites = true
        XCTAssertEqual(try storage.vault().read("openrouter", allowInteraction: false), "original")
        XCTAssertEqual(storage.items["openrouter"], "original")
    }
}
