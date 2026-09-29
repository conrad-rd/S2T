import Foundation
import CryptoKit
import S2TCore

enum TranscriptHistoryStorage {
    static func makeStore() -> TranscriptHistoryStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T")
        let file = directory.appendingPathComponent("recent-transcripts.enc")
        return TranscriptHistoryStore(file: file, legacyFile: directory.appendingPathComponent("recent-transcripts.json")) {
            let account = "transcript-history-encryption"
            let saved = try Keychain.read(account, allowInteraction: false)
            if !saved.isEmpty {
                guard let key = Data(base64Encoded: saved), key.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
                return key
            }
            let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            guard !existing.contains(where: { $0.hasPrefix("recent-transcripts.enc") || $0.hasSuffix(".enc") && $0.hasPrefix("recent-transcripts.json.unreadable-") }) else {
                throw CocoaError(.fileReadNoPermission)
            }
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try Keychain.save(key.base64EncodedString(), account: account, allowInteraction: false)
            return key
        }
    }
}
