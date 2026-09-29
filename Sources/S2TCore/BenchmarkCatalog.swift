import Foundation

public enum BenchmarkCatalog {
    public static let checkedAt = "2026-09-21"
    private static let speechSource = "https://artificialanalysis.ai/speech-to-text/non-streaming"
    private static let localCost = BenchmarkMeasurement(0, source: "https://github.com/ml-explore/mlx", note: "No API fees. Hardware and electricity excluded.")

    public static func models(local: [LocalModel]) -> [BenchmarkModel] {
        var localModels = local.filter { !$0.isNative }.map { model in
            var result = BenchmarkModel(id: "local/" + model.id, name: model.name, provider: "Local", task: model.category, cost: localCost)
            if let score = LocalModelBenchmark.scores[model.id] {
                let basis: BenchmarkQuality = model.category == "speech" ? .fleurs : .intelligence
                result.quality[basis] = .init(score.value, source: score.sourceURL,
                    note: score.configuration + ". Parent-model result; local quantization can differ.", estimated: score.estimated)
            }
            if model.id == "whisper-turbo" {
                result.quality[.speech] = .init(4.6, source: speechSource,
                    note: "Whisper Large v3 Turbo tested by AA on Groq. Parent-model reference, not a local measurement.")
            }
            return result
        }
        if local.contains(where: \.isNative) {
            localModels.append(.init(id: "local/apple-speech", name: "Apple Speech", provider: "Local", task: "speech",
                cost: .init(0, source: "https://developer.apple.com/documentation/speech/speechtranscriber",
                            note: "On-device Apple Speech. Language choices share one engine; no API fees. Hardware and electricity excluded.")))
        }
        return hosted + localModels
    }

    public static let hosted: [BenchmarkModel] = {
        func speech(_ id: String, _ name: String, _ provider: String, _ quality: Double, _ speed: Double, _ cost: Double, host: String) -> BenchmarkModel {
            let note = "AA-WER v2, non-streaming. Reference host: " + host + "."
            return .init(id: id, name: name, provider: provider, task: "speech",
                quality: [.speech: .init(quality, source: speechSource, note: note)],
                speed: .init(speed, source: speechSource, note: "AA median speed factor on 10-minute audio. Reference host: " + host + "; not S2T latency or OpenRouter routing."),
                cost: .init(cost, source: speechSource, note: "AA reference price per 1,000 audio minutes at " + host + "; not an S2T credits quote."))
        }
        func text(_ id: String, _ name: String, _ quality: Double, _ speed: Double, input: Double, output: Double, slug: String, configuration: String, estimated: Bool = false, host: String? = nil) -> BenchmarkModel {
            let source = "https://artificialanalysis.ai/models/" + slug
            return .init(id: "reference/" + id, name: name, provider: host ?? "Host unspecified", task: "text",
                quality: [.intelligence: .init(quality, source: source, note: configuration + ". AA Intelligence Index v4.3.2.", estimated: estimated)],
                speed: host.map { .init(speed, source: source, note: "AA output TPS measured on " + $0 + " only. " + configuration + ".") },
                cost: .init((input * 3 + output) / 4, source: source, note: "AA reference list price, 3:1 input/output blend per million tokens. Excludes cached discounts and variable reasoning-token usage."), modelID: id)
        }
        return [
            speech("xai/grok-voice-transcribe-2.0", "Grok Transcribe 2", "xAI", 2.3, 153.7, 1.67, host: "xAI"),
            speech("xai/grok-voice-transcribe-1.0", "Grok Transcribe 1", "xAI", 4, 270.6, 1.67, host: "xAI"),
            speech("assemblyai/universal-3-pro", "Universal 3 Pro", "AssemblyAI", 3.1, 101.4, 3.5, host: "AssemblyAI"),
            .init(id: "assemblyai/universal-3-5-pro", name: "Universal 3.5 Pro", provider: "AssemblyAI", task: "speech"),
            speech("openrouter/deepgram/nova-3", "Nova 3", "OpenRouter", 5.2, 582.9, 4.3, host: "Deepgram"),
            speech("openrouter/mistralai/voxtral-small-24b-2507-stt", "Voxtral Small", "OpenRouter", 2.8, 66.6, 4, host: "Mistral"),
            speech("openrouter/openai/gpt-transcribe", "GPT Transcribe", "OpenRouter", 3.3, 42.8, 4.5, host: "OpenAI"),
            speech("openrouter/microsoft/mai-transcribe-2", "MAI-Transcribe 2", "OpenRouter", 2.0, 374.5, 1.67, host: "Microsoft AI"),
            speech("openrouter/microsoft/mai-transcribe-1.5", "MAI-Transcribe 1.5", "OpenRouter", 2.4, 191.4, 6, host: "Microsoft AI"),
            speech("openrouter/openai/gpt-4o-transcribe", "GPT-4o Transcribe", "OpenRouter", 4, 36.1, 6, host: "OpenAI"),
            speech("openrouter/openai/gpt-4o-mini-transcribe", "GPT-4o Mini Transcribe", "OpenRouter", 4.5, 42.5, 3, host: "OpenAI"),
            speech("openrouter/openai/whisper-large-v3-turbo", "Whisper Large V3 Turbo", "OpenRouter", 4.6, 115.2, 0.67, host: "Groq"),
            speech("openrouter/openai/whisper-large-v3", "Whisper Large V3", "OpenRouter", 4.1, 118.9, 1.15, host: "fal.ai"),
            speech("openrouter/google/chirp-3", "Chirp 3", "OpenRouter", 4.3, 30.5, 16, host: "Google"),
            speech("openrouter/mistralai/voxtral-mini-3b-2507", "Voxtral Mini", "OpenRouter", 3.8, 51.4, 1, host: "DeepInfra"),
            text("openai/gpt-oss-120b", "gpt-oss 120B", 12, 213.6, input: 0.15, output: 0.595, slug: "gpt-oss-120b", configuration: "High reasoning"),
            text("openai/gpt-oss-20b", "gpt-oss 20B", 9, 168, input: 0.06, output: 0.19, slug: "gpt-oss-20b", configuration: "High reasoning"),
            text("openai/gpt-4.1-mini", "GPT-4.1 mini", 10, 148, input: 0.4, output: 1.6, slug: "gpt-4-1-mini", configuration: "Non-reasoning; AA quality estimate", estimated: true, host: "OpenAI"),
            text("openai/gpt-5.4", "GPT-5.4", 39, 148, input: 2.5, output: 15, slug: "gpt-5-4", configuration: "xhigh reasoning; AA quality estimate", estimated: true, host: "OpenAI"),
            text("anthropic/claude-opus-4.6", "Claude Opus 4.6", 26, 41.5, input: 5, output: 25, slug: "claude-opus-4-6", configuration: "Non-reasoning, high effort", host: "Anthropic"),
            text("google/gemini-2.5-flash", "Gemini 2.5 Flash", 10, 214.9, input: 0.3, output: 2.5, slug: "gemini-2-5-flash", configuration: "Non-reasoning; AA quality estimate", estimated: true, host: "Google"),
            .init(id: "reference/cerebras/gpt-oss-120b", name: "gpt-oss 120B", provider: "Cerebras", task: "text",
                quality: [.intelligence: .init(12, source: "https://artificialanalysis.ai/models/gpt-oss-120b", note: "High reasoning. AA Intelligence Index v4.3.2.")],
                speed: .init(1744.5, source: "https://artificialanalysis.ai/models/gpt-oss-120b/providers", note: "AA median output TPS on Cerebras only, 10k input tokens. Reference checked 2026-09-21; not a measurement of another host or your OpenRouter route."), modelID: "openai/gpt-oss-120b"),
        ]
    }()
}
