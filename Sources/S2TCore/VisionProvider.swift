import Foundation

public enum VisionProvider: String, CaseIterable, Sendable {
    case openRouter = "openrouter"
    case local
    case codex

    public var title: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .local: return "Local endpoint"
        case .codex: return "Codex CLI"
        }
    }
    public var modelPreferenceKey: String { self == .openRouter ? "promptVisionModel" : "promptVisionModel." + rawValue }
    public var defaultModel: String {
        switch self {
        case .openRouter: return "google/gemini-2.5-flash"
        case .local: return "local-vision-model"
        case .codex: return "default"
        }
    }
    public func validModelID(_ model: String) -> Bool {
        switch self {
        case .openRouter: return ProcessingProvider.openRouter.validModelID(model)
        case .local: return LocalEndpoint.validModelID(model)
        case .codex: return ProcessingProvider.codex.validModelID(model)
        }
    }
}
