import Foundation

public enum APIAccount: String, CaseIterable, Sendable {
    case artificialAnalysis = "artificialanalysis"
    case xai
    case assemblyAI = "assemblyai", openRouter = "openrouter", typeSafe = "typesafe"

    public var title: String {
        switch self {
        case .artificialAnalysis: return "Artificial Analysis"
        case .xai: return "xAI · Grok"
        case .assemblyAI: return "AssemblyAI"
        case .openRouter: return "OpenRouter"
        case .typeSafe: return "TypeSafe"
        }
    }

    var validationURL: URL {
        switch self {
        case .artificialAnalysis: return URL(string: "https://artificialanalysis.ai/api/v2/data/llms/models")!
        case .xai: return URL(string: "https://api.x.ai/v1/models")!
        case .assemblyAI: return URL(string: "https://api.assemblyai.com/v2/transcript?limit=1")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/key")!
        case .typeSafe: return URL(string: "https://api.typesafe.ai/v1/models")!
        }
    }
}
