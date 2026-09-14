import Foundation
import Security
import LocalAuthentication
import S2TCore

enum Keychain {
    private static let service = "com.s2t.dictation"
    private static let lock = NSRecursiveLock()
    private static let vault = CredentialVault(read: { account, allowInteraction in
        if let value = try read(account, service: service, allowInteraction: allowInteraction) { return value }
        guard account != CredentialVault.account else { return nil }
        return try read(account, service: "com.sotto.dictation", allowInteraction: allowInteraction)
    }, write: { account, value, allowInteraction in
        try writeItem(value, account: account, allowInteraction: allowInteraction)
    })

    static func read(_ account: String, allowInteraction: Bool = false) throws -> String {
        lock.lock(); defer { lock.unlock() }
        return try vault.read(account, allowInteraction: allowInteraction)
    }

    static func save(_ value: String, account: String, allowInteraction: Bool = true) throws {
        lock.lock(); defer { lock.unlock() }
        try vault.save(value, account: account, allowInteraction: allowInteraction)
    }
    private static func read(_ account: String, service: String, allowInteraction: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return value
    }
    private static func writeItem(_ value: String, account: String, allowInteraction: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not access macOS Keychain, error \(status). Unlock your login keychain and try again." }
    }
}
