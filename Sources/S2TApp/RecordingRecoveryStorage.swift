import Foundation
import CryptoKit
import S2TCore

enum RecordingRecoveryStorage {
    static func makeStore() -> RecordingRecoveryStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("S2T/Recording recovery")
        return RecordingRecoveryStore(directory: directory) {
            let account = "recording-recovery-encryption"
            let saved = try Keychain.read(account, allowInteraction: false)
            if !saved.isEmpty {
                guard let key = Data(base64Encoded: saved), key.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
                return key
            }
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            guard files.isEmpty else { throw CocoaError(.fileReadNoPermission) }
            let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try Keychain.save(key.base64EncodedString(), account: account, allowInteraction: false)
            return key
        }
    }
}
