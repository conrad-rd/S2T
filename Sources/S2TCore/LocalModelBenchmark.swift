import Foundation

public enum LocalBenchmarkMetric: String, Sendable {
    case speechError, intelligence

    public var title: String {
        switch self {
        case .speechError: return "FLEURS English · Word error rate · Lower is better"
        case .intelligence: return "Artificial Analysis Intelligence Index v4.3.2 · Higher is better"
        }
    }

    public var chartMaximum: Double {
        switch self {
        case .speechError: return 5
        case .intelligence: return 10
        }
    }

    public static func forCategory(_ category: String) -> Self {
        category == "speech" ? .speechError : .intelligence
    }
}

public struct LocalModelBenchmark: Equatable, Sendable {
    public let value: Double
    public let metric: LocalBenchmarkMetric
    public let sourceName: String
    public let sourceURL: String
    public let configuration: String
    public let estimated: Bool
    public static let checkedAt = "2026-09-21"

    public var fraction: Double { min(1, max(0, value / metric.chartMaximum)) }
    public var formattedValue: String {
        (estimated ? "~" : "") + value.formatted(.number.precision(.fractionLength(0...2))) + (metric == .intelligence ? "" : "%")
    }

    public static let scores: [String: Self] = [
        "qwen-asr": .init(value: 4.39, metric: .speechError, sourceName: "Qwen report", sourceURL: "https://arxiv.org/html/2601.21337v1#S4.T2", configuration: "Qwen3-ASR 0.6B · Offline · Publisher evaluation", estimated: false),
        "qwen-asr-large": .init(value: 3.35, metric: .speechError, sourceName: "Qwen report", sourceURL: "https://arxiv.org/html/2601.21337v1#S4.T2", configuration: "Qwen3-ASR 1.7B · Offline · Publisher evaluation", estimated: false),
        "parakeet": .init(value: 4.85, metric: .speechError, sourceName: "NVIDIA model card", sourceURL: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3#multilingual-asr", configuration: "Parakeet TDT v3 · Greedy decoding · Publisher evaluation", estimated: false),
        "qwen-small": .init(value: 5, metric: .intelligence, sourceName: "Artificial Analysis", sourceURL: "https://artificialanalysis.ai/models/qwen3-0.6b-instruct", configuration: "Qwen3 0.6B · Non-reasoning · AA estimate", estimated: true),
        "qwen-medium": .init(value: 5, metric: .intelligence, sourceName: "Artificial Analysis", sourceURL: "https://artificialanalysis.ai/models/qwen3-1.7b-instruct", configuration: "Qwen3 1.7B · Non-reasoning · AA estimate", estimated: true),
        "qwen-cleanup-4b": .init(value: 7, metric: .intelligence, sourceName: "Artificial Analysis", sourceURL: "https://artificialanalysis.ai/models/qwen3-4b-2507-instruct", configuration: "Qwen3 4B Instruct 2507 · Non-reasoning · AA estimate", estimated: true),
        "qwen-cleanup-8b": .init(value: 6, metric: .intelligence, sourceName: "Artificial Analysis", sourceURL: "https://artificialanalysis.ai/models/qwen3-8b-instruct", configuration: "Qwen3 8B · Non-reasoning · AA estimate", estimated: true),
        "openai-gpt-oss-20b": .init(value: 9, metric: .intelligence, sourceName: "Artificial Analysis", sourceURL: "https://artificialanalysis.ai/models/gpt-oss-20b", configuration: "gpt-oss 20B · High reasoning", estimated: false),
    ]
}
