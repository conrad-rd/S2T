import Foundation

public struct WritingDraft: Codable, Equatable, Sendable {
    public let original: String
    public let text: String
    public init(original: String, text: String) { self.original = original; self.text = text }
}

/// Recovery journal; document files still change only through an explicit save.
public struct WritingDraftStore: Sendable {
    public let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("writing-drafts.json") }

    public func load() throws -> [WritingDocumentKind: WritingDraft] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8 * 1024 * 1024 else {
            throw ServiceError.message("The saved writing drafts are too large to open safely.")
        }
        return try JSONDecoder().decode([WritingDocumentKind: WritingDraft].self, from: Data(contentsOf: url))
    }

    public func save(_ drafts: [WritingDocumentKind: WritingDraft]) throws {
        let manager = FileManager.default
        if drafts.isEmpty {
            if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            return
        }
        let data = try JSONEncoder().encode(drafts)
        guard data.count <= 8 * 1024 * 1024 else {
            throw ServiceError.message("This draft is too large to recover automatically. Save a copy before quitting.")
        }
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
