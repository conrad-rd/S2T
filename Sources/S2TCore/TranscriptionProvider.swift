import Foundation

public enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case local
    case assemblyAI = "assemblyai", openRouter = "openrouter"

    case xai

    public static let xaiModels = ["grok-voice-transcribe-2.0", "grok-voice-transcribe-1.0"]

    public var account: APIAccount? {
        switch self {
        case .xai: return .xai
        case .local: return nil
        case .assemblyAI: return .assemblyAI
        case .openRouter: return .openRouter
        }
    }
    public var title: String { account?.title ?? "Local endpoint" }
    public var defaultModel: String {
        switch self {
        case .xai: return Self.xaiModels[0]
        case .local: return "whisper-1"
        case .assemblyAI: return "universal-3-5-pro"
        case .openRouter: return "openai/whisper-large-v3"
        }
    }
    public func validModelID(_ value: String) -> Bool {
        if self == .xai { return Self.xaiModels.contains(value) }
        if self == .local { return LocalEndpoint.validModelID(value) }
        if self == .openRouter { return ProcessingProvider.openRouter.validModelID(value) }
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,199}$"#, options: .regularExpression) != nil
    }
}
