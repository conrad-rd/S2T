import Foundation

public enum WritingDocumentKind: String, CaseIterable, Codable, Sendable {
    case instructions, dictionary
    public var title: String { self == .instructions ? "Instructions" : "Dictionary" }
    public var filename: String { self == .instructions ? InstructionsFile.filename : "dictionary.md" }
    public var seed: String {
        self == .instructions ? WritingMode.defaultEditingInstruction : "# Dictionary\n\nAdd preferred words or names below, one per line.\n"
    }
}

public struct WritingDocumentFile: Sendable {
    public let url: URL
    public let kind: WritingDocumentKind
    public init(directory: URL, kind: WritingDocumentKind) {
        self.kind = kind
        url = directory.appendingPathComponent(kind.filename)
    }
    public func read() throws -> String {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if kind == .instructions { try InstructionsFile(url: url).adoptLegacyFile() }
        if !FileManager.default.fileExists(atPath: url.path) {
            do { try Data(kind.seed.utf8).write(to: url, options: .withoutOverwriting) }
            catch CocoaError.fileWriteFileExists { }
        }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 65_536 else {
            throw ServiceError.message("Keep \(kind.filename) under 64 KB.")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
    public func save(_ text: String, replacing original: String) throws {
        try Self.validate(text, kind: kind)
        guard try read() == original else {
            throw ServiceError.message("This file changed outside the editor. Your draft is kept. Reload the file before saving again.")
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    public static func validate(_ text: String, kind: WritingDocumentKind) throws {
        guard text.utf8.count <= 65_536 else { throw ServiceError.message("Keep \(kind.filename) under 64 KB.") }
        if kind == .instructions && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ServiceError.message("Add instructions before saving.")
        }
    }
}
