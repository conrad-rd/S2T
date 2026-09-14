import Foundation

public struct SystemPromptFile: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func ensureExists() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: url.path) else { return }
        do {
            try Data(WritingMode.defaultEditingInstruction.utf8).write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists { }
    }

    public func read() throws -> String {
        try ensureExists()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 65_536 else { throw ServiceError.message("The system prompt file is too large. Keep system-prompt.txt under 64 KB.") }
        let prompt = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw ServiceError.message("The system prompt file is empty. Add editing instructions to system-prompt.txt and save it.") }
        return prompt
    }
}
