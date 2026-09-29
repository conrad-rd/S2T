import Foundation

public struct SpeechModelCatalog: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    private let architecture: Architecture

    private struct Architecture: Decodable, Equatable, Sendable {
        let output_modalities: [String]
    }

    public init(id: String, name: String) {
        self.id = id; self.name = name
        architecture = Architecture(output_modalities: ["transcription"])
    }

    // Public OpenRouter transcription catalog, checked September 21, 2026.
    public static let reference: [Self] = [
        .init(id: "meta/muse-voice-transcribe-1.0", name: "Muse Voice Transcribe 1.0"),
        .init(id: "microsoft/mai-transcribe-2", name: "MAI-Transcribe 2"),
        .init(id: "nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b", name: "Nemotron 3.5 ASR Streaming Multilingual 0.6B"),
        .init(id: "mistralai/voxtral-small-24b-2507-stt", name: "Voxtral Small 24B 2507 STT"),
        .init(id: "mistralai/voxtral-mini-3b-2507", name: "Voxtral Mini 3B 2507"),
        .init(id: "qwen/qwen3-asr-1.7b", name: "Qwen3 ASR 1.7B"),
        .init(id: "qwen/qwen3-asr-0.6b", name: "Qwen3 ASR 0.6B"),
        .init(id: "openai/gpt-transcribe", name: "GPT Transcribe"),
        .init(id: "fish-audio/transcribe-1", name: "Transcribe 1"),
        .init(id: "x-ai/grok-stt-1.0", name: "Grok STT 1.0"),
        .init(id: "deepgram/nova-3", name: "Nova-3"),
        .init(id: "microsoft/mai-transcribe-1.5", name: "MAI-Transcribe 1.5"),
        .init(id: "nvidia/parakeet-tdt-0.6b-v3", name: "Parakeet TDT 0.6B v3"),
        .init(id: "mistralai/voxtral-mini-transcribe", name: "Voxtral Mini Transcribe"),
        .init(id: "qwen/qwen3-asr-flash-2026-02-10", name: "Qwen3 ASR Flash"),
        .init(id: "google/chirp-3", name: "Chirp 3"),
        .init(id: "openai/gpt-4o-mini-transcribe", name: "GPT-4o Mini Transcribe"),
        .init(id: "openai/whisper-large-v3", name: "Whisper Large V3"),
        .init(id: "openai/whisper-large-v3-turbo", name: "Whisper Large V3 Turbo"),
        .init(id: "openai/whisper-1", name: "Whisper 1"),
        .init(id: "openai/gpt-4o-transcribe", name: "GPT-4o Transcribe")
    ]

    public static func load(transport: any HTTPTransport = SessionTransport()) async throws -> [Self] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models?output_modalities=transcription")!)
        request.timeoutInterval = 20
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> [Self] {
        struct Catalog: Decodable { let data: [SpeechModelCatalog] }
        var seen = Set<String>()
        let models = try JSONDecoder().decode(Catalog.self, from: data).data.filter {
            $0.architecture.output_modalities.contains("transcription") &&
            TranscriptionProvider.openRouter.validModelID($0.id) && seen.insert($0.id).inserted
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
        guard !models.isEmpty else { throw URLError(.cannotParseResponse) }
        return models
    }
}
