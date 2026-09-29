import Foundation
import CryptoKit

public struct RecordingRecovery: Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var audio: Data
    public var requestID: String
    public var completedParts: [String: String]
    public var transcript: String
    public var mode: WritingMode
    public var directAssemblyStreaming: Bool?
    public var streamingReceipt: CreditStreamingReceipt?
    public var creditCleanupDraft: CreditCleanupDraft?
    public var creditCleanupRequest: CreditCleanupRequest?
    public var creditSpeechRequest: CreditSpeechRequest?
    public var creditSpeechSnapshotVersion: Int?
    /// Cloud speech uploads use this rate. Older records keep uploading their original bytes so retries reuse the same request identity.
    public var speechUploadRate: Int?
    public var speechSegmentEnds: [Int]?

    public init(id: UUID = UUID(), audio: Data, requestID: String, mode: WritingMode, completedParts: [String: String] = [:], transcript: String = "", createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.audio = audio
        self.requestID = requestID
        self.mode = mode
        creditSpeechSnapshotVersion = 1
        self.completedParts = completedParts
        self.transcript = transcript
    }
}

public struct CreditCleanupDraft: Codable, Sendable {
    public let requestID: String
    public let original: String
    public let text: String
    public init(requestID: String, original: String, text: String) {
        self.requestID = requestID; self.original = original; self.text = text
    }
}

public actor RecordingRecoveryStore {
    private let directory: URL
    private let keyProvider: @Sendable () throws -> Data
    private var cachedKey: SymmetricKey?
    public private(set) var unreadableFiles: [String] = []

    public init(directory: URL, key: @escaping @Sendable () throws -> Data) {
        self.directory = directory
        keyProvider = key
    }

    public func save(_ recording: RecordingRecovery) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(recording)
        guard let encrypted = try AES.GCM.seal(data, using: key()).combined else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(recording.id.uuidString + ".enc")
        try encrypted.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func pending() throws -> [RecordingRecovery] {
        try readRecords().filter { !$0.audio.isEmpty }.sorted { $0.createdAt > $1.createdAt }
    }

    public func pendingStreamingReports() throws -> [RecordingRecovery] {
        try readRecords().filter { $0.streamingReceipt != nil }
    }

    private func readRecords() throws -> [RecordingRecovery] {
        unreadableFiles = []
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let encryptionKey = try key()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "enc" }
        var records: [RecordingRecovery] = []
        var firstError: Error?
        for url in files {
            do {
                let encrypted = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
                let saved = try PropertyListDecoder().decode(RecordingRecovery.self, from: AES.GCM.open(encrypted, using: encryptionKey))
                records.append(saved)
                if saved.audio.isEmpty, saved.streamingReceipt == nil { try? FileManager.default.removeItem(at: url) }
            } catch {
                unreadableFiles.append(url.lastPathComponent)
                if firstError == nil { firstError = error }
            }
        }
        // A missing/wrong key must remain visible instead of looking like an empty archive.
        if records.isEmpty, let firstError { throw firstError }
        return records
    }

    public func clearStreamingReport(id: UUID, authorizationID: String) throws {
        let url = directory.appendingPathComponent(id.uuidString + ".enc")
        let encrypted = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        var saved = try PropertyListDecoder().decode(RecordingRecovery.self, from: AES.GCM.open(encrypted, using: key()))
        guard saved.streamingReceipt?.authorizationID == authorizationID else { return }
        saved.streamingReceipt = nil
        if saved.audio.isEmpty { try FileManager.default.removeItem(at: url) }
        else { try save(saved) }
    }

    public func complete(_ recording: RecordingRecovery) throws {
        var receipt = recording
        receipt.audio = Data()
        receipt.transcript = ""
        receipt.completedParts = [:]
        receipt.creditCleanupDraft = nil
        receipt.creditCleanupRequest = nil
        receipt.creditSpeechRequest = nil
        if receipt.streamingReceipt != nil { try save(receipt) }
        else {
            let url = directory.appendingPathComponent(receipt.id.uuidString + ".enc")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
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
