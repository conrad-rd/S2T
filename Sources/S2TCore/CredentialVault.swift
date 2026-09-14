import Foundation

/// The caller serializes access. Existing per-account items remain available during migration.
public final class CredentialVault {
    public static let account = "credentials-v1"
    private let readItem: (String, Bool) throws -> String?
    private let writeItem: (String, String, Bool) throws -> Void
    private var cached: [String: String]?

    public init(read: @escaping (String, Bool) throws -> String?, write: @escaping (String, String, Bool) throws -> Void) {
        readItem = read
        writeItem = write
    }

    private func values(allowInteraction: Bool) throws -> [String: String] {
        if let cached { return cached }
        let result: [String: String]
        if let text = try readItem(Self.account, allowInteraction) {
            result = try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
        } else { result = [:] }
        cached = result
        return result
    }

    public func read(_ account: String, allowInteraction: Bool) throws -> String {
        let current = try values(allowInteraction: allowInteraction)
        if let value = current[account] { return value }
        guard let legacy = try readItem(account, allowInteraction) else { return "" }
        // A blocked migration write must not prevent use of a readable existing key.
        try? save(legacy, account: account, allowInteraction: false)
        return legacy
    }

    public func save(_ value: String, account: String, allowInteraction: Bool) throws {
        var current = try values(allowInteraction: allowInteraction)
        current[account] = value
        let text = String(decoding: try JSONEncoder().encode(current), as: UTF8.self)
        try writeItem(Self.account, text, allowInteraction)
        cached = current
    }
}
