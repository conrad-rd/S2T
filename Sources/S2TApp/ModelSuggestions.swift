import AppKit
import S2TCore

struct ModelSuggestion {
    let model: String
    let title: String
    var host = ""
    /// A short factual reason shown under the title in the model menu.
    var detail = ""
    static let speech = SpeechModelCatalog.reference.map { ModelSuggestion(model: $0.id, title: $0.name) }
    static let cleanup = CreditModel.suggestions.map { ModelSuggestion(model: $0.model, title: $0.title, host: $0.host) }
}

/// A bounded OpenRouter shortlist per task. Other IDs remain available through Custom model ID.
/// Speech notes come from the bundled Artificial Analysis table (BenchmarkCatalog, checked 2026-09-21);
/// "newest" notes come from the OpenRouter catalog dates on 2026-09-25.
enum ModelRecommendations {
    static let cleanup = [
        ModelSuggestion(model: "openai/gpt-oss-120b", title: "GPT-OSS 120B", host: "cerebras/fp16", detail: "S2T default · Cerebras hosting"),
        ModelSuggestion(model: "google/gemini-3.8-flash", title: "Gemini 3.8 Flash", detail: "Google’s newest Flash model"),
        ModelSuggestion(model: "openai/gpt-6-luna", title: "GPT-6 Luna", detail: "OpenAI’s newest small model"),
        ModelSuggestion(model: "google/gemini-3.1-flash-lite", title: "Gemini 3.1 Flash Lite", detail: "Lower-cost Google option"),
        ModelSuggestion(model: "anthropic/claude-haiku-4.5", title: "Claude Haiku 4.5", detail: "Compact Anthropic model"),
        ModelSuggestion(model: "openai/gpt-oss-20b", title: "GPT-OSS 20B", detail: "Small open-weight model · automatic hosting")
    ]
    static let creditSpeech = [
        ModelSuggestion(model: "universal-3-5-pro", title: "Universal 3.5 Pro", detail: "AssemblyAI · S2T default"),
        ModelSuggestion(model: "microsoft/mai-transcribe-2", title: "MAI-Transcribe 2", detail: "Fewest errors in Artificial Analysis tests")
    ]
    static let openRouterSpeech = [
        ModelSuggestion(model: "microsoft/mai-transcribe-2", title: "MAI-Transcribe 2", detail: "Fewest errors in Artificial Analysis tests"),
        ModelSuggestion(model: "openai/whisper-large-v3-turbo", title: "Whisper Large V3 Turbo", detail: "Compact Whisper speech model"),
        ModelSuggestion(model: "openai/gpt-4o-mini-transcribe", title: "GPT-4o Mini Transcribe", detail: "Compact OpenAI speech model"),
        ModelSuggestion(model: "google/chirp-3", title: "Chirp 3", detail: "Google speech model"),
        ModelSuggestion(model: "deepgram/nova-3", title: "Nova-3", detail: "Deepgram speech model"),
        ModelSuggestion(model: "mistralai/voxtral-mini-transcribe", title: "Voxtral Mini Transcribe", detail: "Mistral speech model")
    ]
    static let xaiSpeech = [
        ModelSuggestion(model: "grok-voice-transcribe-2.0", title: "Grok Voice 2.0", detail: "Newest xAI speech model")
    ]
    /// Cleanup picks favor speed, so a recommended model starts with low reasoning unless the user saved another level.
    static let cleanupReasoning = OpenRouterOptions.Effort.low
}
