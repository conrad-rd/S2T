import Foundation

public enum ProcessingProvider: String, CaseIterable, Identifiable, Sendable {
    case openRouter = "openrouter"
    case xai
    case local
    case codex

    public var requiresAPIKey: Bool { self == .openRouter || self == .xai }

    public var modelPreferenceKey: String { self == .xai ? "xaiProcessingModel" : self == .codex ? "codexProcessingModel" : self == .openRouter ? "fallbackModel" : "localProcessingModel" }

    public static let defaultOpenRouterModel = "openai/gpt-oss-120b"
    public var id: String { rawValue }
    public var title: String { self == .xai ? "xAI · Grok" : self == .codex ? "Codex CLI" : self == .local ? "Local endpoint" : "OpenRouter" }
    public var defaultModel: String { self == .xai ? "grok-4.6" : self == .codex ? "default" : self == .local ? "local-model" : Self.defaultOpenRouterModel }
    public var defaultEndpoint: String? { nil }
    public var completionURL: String {
        self == .xai ? "https://api.x.ai/v1/chat/completions" : self == .codex ? "" : self == .local ? LocalEndpoint.defaultProcessingURL : "https://openrouter.ai/api/v1/chat/completions"
    }
    public var modelCatalogURL: URL {
        URL(string: self == .xai ? "https://docs.x.ai/developers/models" : "https://openrouter.ai/models")!
    }
    public func validModelID(_ value: String) -> Bool {
        if self == .local { return LocalEndpoint.validModelID(value) }
        if self == .openRouter && value == "cerebras/fp16" { return false }
        if self == .xai { return value.range(of: #"^grok-[A-Za-z0-9_.-]{1,190}$"#, options: .regularExpression) != nil }
        if self == .openRouter { return value.range(of: #"^[A-Za-z0-9_~.-]+/[A-Za-z0-9_~.:-]+$"#, options: .regularExpression) != nil && value.count <= 200 }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,199}$"#, options: .regularExpression) != nil
    }
}
