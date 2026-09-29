import Foundation

public struct InstructionsFile: Sendable {
    public static let filename = "instructions.txt"
    /// Earlier builds called these instructions a system prompt and saved them under this name.
    public static let legacyFilename = "system-prompt.txt"
    public let url: URL
    public init(url: URL) { self.url = url }

    /// Renames a saved system-prompt.txt beside this file so existing edits carry over. Never replaces a newer file.
    public func adoptLegacyFile() throws {
        let manager = FileManager.default
        let legacy = url.deletingLastPathComponent().appendingPathComponent(Self.legacyFilename)
        guard url.lastPathComponent == Self.filename, !manager.fileExists(atPath: url.path),
              manager.fileExists(atPath: legacy.path) else { return }
        do { try manager.moveItem(at: legacy, to: url) } catch CocoaError.fileWriteFileExists { }
    }

    public func ensureExists() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try adoptLegacyFile()
        guard !manager.fileExists(atPath: url.path) else { return }
        do {
            try Data(WritingMode.defaultEditingInstruction.utf8).write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists { }
    }

    public func read() throws -> String {
        try ensureExists()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 65_536 else { throw ServiceError.message("Your instructions are too large. Keep them under 64 KB in Settings → Writing.") }
        let instructions = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else { throw ServiceError.message("Your instructions are empty. Add them in Settings → Writing and save.") }
        return instructions
    }
}
