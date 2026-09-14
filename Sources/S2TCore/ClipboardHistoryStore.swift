import Foundation
import CryptoKit

public struct ClipboardArchive: Codable {
    public var history: ClipboardHistory
    public var changeCount: Int
    public var fingerprint: String?

    public init(history: ClipboardHistory = ClipboardHistory(), changeCount: Int = -1, fingerprint: String? = nil) {
        self.history = history
        self.changeCount = changeCount
        self.fingerprint = fingerprint
    }
}

public protocol ClipboardHistoryPersistence {
    func load(at date: Date) throws -> ClipboardArchive
    func save(_ archive: ClipboardArchive) throws
}

public final class ClipboardHistoryStore: ClipboardHistoryPersistence {
    private let url: URL
    private let keyProvider: () throws -> Data
    private var cachedKey: SymmetricKey?

    public init(url: URL, key: @escaping () throws -> Data) {
        self.url = url
        keyProvider = key
    }

    public func load(at date: Date = Date()) throws -> ClipboardArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return ClipboardArchive() }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(sealed, using: key())
        var archive = try JSONDecoder().decode(ClipboardArchive.self, from: data)
        archive.history = ClipboardHistory(restoring: archive.history.entries, at: date)
        return archive
    }

    public func save(_ archive: ClipboardArchive) throws {
        let data = try JSONEncoder().encode(archive)
        let sealed = try AES.GCM.seal(data, using: key())
        guard let encrypted = sealed.combined else { throw CocoaError(.fileWriteUnknown) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try encrypted.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        let data = try keyProvider()
        guard data.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        let key = SymmetricKey(data: data)
        cachedKey = key
        return key
    }
}
