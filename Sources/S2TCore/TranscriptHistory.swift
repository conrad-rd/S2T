import Foundation
import CryptoKit

public struct RecentTranscript: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let appName: String?
    public let bundleID: String?
    public let clipboardDerived: Bool?

    public init(id: UUID, date: Date, text: String, appName: String?, bundleID: String?, clipboardDerived: Bool = false) {
        self.id = id; self.date = date; self.text = text; self.appName = appName; self.bundleID = bundleID
        self.clipboardDerived = clipboardDerived
    }
}

public enum TranscriptPrivacy {
    public static func redacted(_ text: String, copiedValues: [String] = []) -> String {
        var value = text
        for copied in copiedValues.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            value = value.replacingOccurrences(of: copied, with: "[Copied content]")
        }
        // Legacy archives can contain locally substituted credentials with no provenance metadata.
        let patterns = APIKeyPatterns.providers.map { $0.1 } + [#"\bs2t_(?:live|test|demo)_[A-Za-z0-9_-]{20,}"#]
        for pattern in patterns {
            value = value.replacingOccurrences(of: pattern, with: "[API key]", options: .regularExpression)
        }
        return value
    }
}

public final class TranscriptHistoryStore {
    public static let retention: TimeInterval = 30 * 86400
    public static let maximumEntries = 500
    public static let maximumBytes = 8_000_000
    private let file: URL
    private let legacyFile: URL?
    private let keyProvider: () throws -> Data
    private var cachedKey: SymmetricKey?
    public private(set) var notice: String?

    public init(file: URL, legacyFile: URL? = nil, key: @escaping () throws -> Data) {
        self.file = file; self.legacyFile = legacyFile; keyProvider = key
    }

    public func load(at date: Date = Date()) throws -> [RecentTranscript] {
        let manager = FileManager.default
        var entries: [RecentTranscript] = []
        if manager.fileExists(atPath: file.path) {
            let encryptionKey = try key()
            do {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maximumBytes + 64 else { throw CocoaError(.fileReadTooLarge) }
                let encrypted = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
                entries = try JSONDecoder().decode([RecentTranscript].self, from: AES.GCM.open(encrypted, using: encryptionKey))
            } catch {
                try manager.moveItem(at: file, to: file.appendingPathExtension("unreadable-" + UUID().uuidString))
                notice = "An unreadable encrypted archive was preserved separately. New transcripts can be saved."
            }
        }
        if let legacyFile, manager.fileExists(atPath: legacyFile.path) {
            let encryptionKey = try key()
            let legacy: [RecentTranscript]?
            do {
                let size = try legacyFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64_000_000 else { throw CocoaError(.fileReadTooLarge) }
                legacy = try JSONDecoder().decode([RecentTranscript].self, from: Data(contentsOf: legacyFile))
            } catch {
                try protectUnreadableLegacy(legacyFile, key: encryptionKey)
                notice = "An unreadable older archive was preserved as an encrypted recovery file. New transcripts can be saved."
                legacy = nil
            }
            if let legacy {
                let known = Set(entries.map(\.id))
                entries += legacy.filter { !known.contains($0.id) }
                entries = try save(entries, at: date)
                // Keep the original until its encrypted replacement has reached disk.
                try manager.removeItem(at: legacyFile)
            }
        }
        let limited = Self.bounded(entries, at: date)
        if limited != entries { return try save(limited, at: date) }
        return limited
    }

    @discardableResult public func save(_ entries: [RecentTranscript], at date: Date = Date()) throws -> [RecentTranscript] {
        var limited = Self.bounded(entries, at: date)
        var data = try JSONEncoder().encode(limited)
        while data.count > Self.maximumBytes, limited.count > 1 {
            limited.removeLast()
            data = try JSONEncoder().encode(limited)
        }
        guard data.count <= Self.maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        guard let encrypted = try AES.GCM.seal(data, using: key()).combined else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encrypted.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return limited
    }

    public func clear() throws {
        let directory = file.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let names = [file.lastPathComponent, legacyFile?.lastPathComponent].compactMap { $0 }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if names.contains(where: { url.lastPathComponent == $0 || url.lastPathComponent.hasPrefix($0 + ".unreadable-") }) {
                try FileManager.default.removeItem(at: url)
            }
        }
        notice = nil
    }

    public static func bounded(_ entries: [RecentTranscript], at date: Date = Date()) -> [RecentTranscript] {
        var seen = Set<UUID>()
        return Array(entries.sorted { $0.date > $1.date }.filter {
            $0.date >= date.addingTimeInterval(-retention) && $0.date <= date.addingTimeInterval(86400) &&
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted
        }.prefix(maximumEntries)).map {
            .init(id: $0.id, date: $0.date, text: TranscriptPrivacy.redacted($0.text),
                  appName: $0.appName, bundleID: $0.bundleID, clipboardDerived: $0.clipboardDerived ?? false)
        }
    }

    private func key() throws -> SymmetricKey {
        if let cachedKey { return cachedKey }
        let data = try keyProvider()
        guard data.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        let result = SymmetricKey(data: data)
        cachedKey = result
        return result
    }

    // A damaged or very large plaintext archive is encrypted in bounded chunks before removing its original.
    private func protectUnreadableLegacy(_ legacy: URL, key: SymmetricKey) throws {
        let backup = legacy.appendingPathExtension("unreadable-" + UUID().uuidString + ".enc")
        guard FileManager.default.createFile(atPath: backup.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        do {
            let input = try FileHandle(forReadingFrom: legacy), output = try FileHandle(forWritingTo: backup)
            defer { try? input.close(); try? output.close() }
            try output.write(contentsOf: Data("S2T encrypted archive chunks v1\n".utf8))
            while let chunk = try input.read(upToCount: 1_000_000), !chunk.isEmpty {
                let encrypted = try AES.GCM.seal(chunk, using: key).combined!
                var length = UInt32(encrypted.count).littleEndian
                try withUnsafeBytes(of: &length) { try output.write(contentsOf: $0) }
                try output.write(contentsOf: encrypted)
            }
            try output.synchronize()
            try FileManager.default.removeItem(at: legacy)
        } catch {
            try? FileManager.default.removeItem(at: backup)
            throw error
        }
    }
}
