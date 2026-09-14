import Foundation

public enum ProcessingProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter = "openrouter"
    case cerebras
    case local
    case codex

    public var requiresAPIKey: Bool { self == .openRouter || self == .cerebras }

    public var modelPreferenceKey: String { self == .codex ? "codexProcessingModel" : self == .openRouter ? "fallbackModel" : self == .cerebras ? "cerebrasModel" : "localProcessingModel" }

    public static let cerebrasOpenRouterModel = "openai/gpt-oss-120b"
    public var id: String { rawValue }
    public var title: String { self == .codex ? "Codex CLI" : self == .local ? "Local endpoint" : self == .openRouter ? "OpenRouter" : "Cerebras" }
    public var defaultModel: String { self == .codex ? "default" : self == .local ? "local-model" : self == .openRouter ? Self.cerebrasOpenRouterModel : "qwen-3.8-27b" }
    public var defaultEndpoint: String? { self == .openRouter ? "cerebras/fp16" : nil }
    public var completionURL: String {
        self == .codex ? "" : self == .local ? LocalEndpoint.defaultProcessingURL : self == .openRouter ? "https://openrouter.ai/api/v1/chat/completions" : "https://api.cerebras.ai/v1/chat/completions"
    }
    public var modelCatalogURL: URL {
        URL(string: self == .openRouter ? "https://openrouter.ai/models" : "https://inference-docs.cerebras.ai/api-reference/models/public-models")!
    }
    public func validModelID(_ value: String) -> Bool {
        if self == .local { return LocalEndpoint.validModelID(value) }
        if self == .openRouter && value == "cerebras/fp16" { return false }
        if self == .openRouter { return value.range(of: #"^[A-Za-z0-9_~.-]+/[A-Za-z0-9_~.:-]+$"#, options: .regularExpression) != nil && value.count <= 200 }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,199}$"#, options: .regularExpression) != nil
    }
}
