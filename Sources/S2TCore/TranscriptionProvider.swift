import Foundation

public enum TranscriptionProvider: String, CaseIterable, Sendable {
    case local
    case assemblyAI = "assemblyai", elevenLabs = "elevenlabs", openRouter = "openrouter"

    public var account: APIAccount? {
        switch self {
        case .local: return nil
        case .assemblyAI: return .assemblyAI
        case .elevenLabs: return .elevenLabs
        case .openRouter: return .openRouter
        }
    }
    public var title: String { account?.title ?? "Local endpoint" }
    public var defaultModel: String {
        switch self {
        case .local: return "whisper-1"
        case .assemblyAI: return "universal-3-5-pro"
        case .elevenLabs: return "scribe_v2"
        case .openRouter: return "openai/whisper-large-v3"
        }
    }
    public func validModelID(_ value: String) -> Bool {
        if self == .local { return LocalEndpoint.validModelID(value) }
        if self == .openRouter { return ProcessingProvider.openRouter.validModelID(value) }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,199}$"#, options: .regularExpression) != nil
    }
}
