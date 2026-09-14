import Foundation

public enum LocalEndpoint {
    public static let defaultProcessingURL = "http://localhost:1234/v1/chat/completions"
    public static let defaultTranscriptionURL = "http://localhost:8080/v1/audio/transcriptions"

    public static func url(_ value: String) throws -> URL {
        guard let parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil,
              let url = parts.url else {
            throw ServiceError.message("Enter a complete HTTP or HTTPS endpoint URL without credentials, query parameters or a fragment.")
        }
        return url
    }

    public static func validModelID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }
    }
}
