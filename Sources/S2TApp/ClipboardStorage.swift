import Foundation
import CryptoKit
import S2TCore

enum ClipboardStorage {
    static func makeStore() -> ClipboardHistoryStore {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("S2T/clipboard-history.enc")
        return ClipboardHistoryStore(url: url) {
            let account = "clipboard-history-encryption"
            let saved = try Keychain.read(account, allowInteraction: false)
            if !saved.isEmpty {
                guard let key = Data(base64Encoded: saved), key.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
                return key
            }
            guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileReadNoPermission) }
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try Keychain.save(key.base64EncodedString(), account: account, allowInteraction: false)
            return key
        }
    }
}
