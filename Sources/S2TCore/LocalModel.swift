import Foundation

public struct LocalModel: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let category: String
    public let repository: String
    public let revision: String
    public let speed: Int
    public let quality: Int
    public let memoryGB: Double
    public let diskGB: Double
    public let details: String
    public let license: String

    public var isNative: Bool { id.hasPrefix("apple-speech-") }
    public var nativeLocale: String? { isNative ? String(id.dropFirst("apple-speech-".count)) : nil }

    public static func appleSpeech(locale: String) -> LocalModel {
        LocalModel(id: "apple-speech-" + locale.replacingOccurrences(of: "_", with: "-"), name: "Apple Speech · " + (Locale.current.localizedString(forIdentifier: locale) ?? locale),
            category: "speech", repository: "Apple Speech", revision: "system", speed: 0, quality: 0,
            memoryGB: 0, diskGB: 0, details: "On-device transcription on macOS 26. Apple manages the language download and memory. No API key or Python runtime required.", license: "Apple")
    }

    public var qualityPerGB: Double { memoryGB > 0 ? Double(quality) / memoryGB : 0 }

    public var categoryTitle: String {
        switch category {
        case "speech": return "Speech to text"
        default: return "Text cleanup"
        }
    }

    public static func read(from url: URL) throws -> [LocalModel] {
        let models = try JSONDecoder().decode([LocalModel].self, from: Data(contentsOf: url))
        guard Set(models.map(\.id)).count == models.count,
              models.allSatisfy({ model in
                  !model.id.isEmpty && model.id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
                  && ["speech", "text"].contains(model.category)
                  && model.repository.hasPrefix("mlx-community/")
                  && model.revision.count == 40 && model.revision.allSatisfy(\.isHexDigit)
                  && (1...5).contains(model.speed) && (1...5).contains(model.quality)
                  && model.memoryGB > 0 && model.diskGB > 0
              }) else { throw ServiceError.message("The local model catalog is invalid.") }
        return models
    }
}
