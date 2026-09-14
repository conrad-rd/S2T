import Foundation

public enum APIAccount: String, CaseIterable, Sendable {
    case assemblyAI = "assemblyai", openRouter = "openrouter", cerebras, elevenLabs = "elevenlabs"

    public var title: String {
        switch self {
        case .assemblyAI: return "AssemblyAI"
        case .openRouter: return "OpenRouter"
        case .cerebras: return "Cerebras"
        case .elevenLabs: return "ElevenLabs"
        }
    }

    var validationURL: URL {
        switch self {
        case .elevenLabs: return URL(string: "https://api.elevenlabs.io/v1/user")!
        case .assemblyAI: return URL(string: "https://api.assemblyai.com/v2/transcript?limit=1")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/key")!
        case .cerebras: return URL(string: "https://api.cerebras.ai/v1/models")!
        }
    }
}
