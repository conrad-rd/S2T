import Foundation

public struct CodexOptions: Codable, Equatable, Sendable {
    public var reasoning: String
    public var fast: Bool
    public init(reasoning: String = "", fast: Bool = false) {
        self.reasoning = reasoning
        self.fast = fast
    }
    public var arguments: [String] {
        var result: [String] = []
        if !reasoning.isEmpty { result += ["-c", "model_reasoning_effort=\"\(reasoning)\""] }
        if fast { result += ["-c", "service_tier=\"fast\"", "-c", "features.fast_mode=true"] }
        return result
    }
    public var isValid: Bool {
        ["", "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"].contains(reasoning)
    }
}

public struct CodexModel: Decodable, Equatable, Sendable {
    public struct Effort: Decodable, Equatable, Sendable { public let effort: String; public let description: String }
    public struct Tier: Decodable, Equatable, Sendable { public let id: String; public let name: String }
    public let slug: String
    public let display_name: String
    public let supported_reasoning_levels: [Effort]
    public let default_reasoning_level: String?
    public let visibility: String?
    public let service_tiers: [Tier]?
    public let additional_speed_tiers: [String]?
    public let input_modalities: [String]?
    public var supportsFast: Bool {
        service_tiers?.contains(where: { ["fast", "priority"].contains($0.id) }) == true || additional_speed_tiers?.contains("fast") == true
    }
    public func normalized(_ options: CodexOptions) -> CodexOptions {
        CodexOptions(reasoning: supported_reasoning_levels.contains(where: { $0.effort == options.reasoning }) ? options.reasoning : "", fast: supportsFast && options.fast)
    }
}

public enum CodexModelCatalog {
    public static func decode(_ data: Data) throws -> [CodexModel] {
        struct Cache: Decodable { let models: [CodexModel] }
        var seen = Set<String>()
        return try JSONDecoder().decode(Cache.self, from: data).models.filter {
            ProcessingProvider.codex.validModelID($0.slug) && seen.insert($0.slug).inserted
        }
    }
    public static func read() throws -> [CodexModel] {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let url = home.appendingPathComponent("models_cache.json")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16_000_000 else { throw ServiceError.message("The Codex model catalog is too large.") }
        return try decode(Data(contentsOf: url))
    }
}
