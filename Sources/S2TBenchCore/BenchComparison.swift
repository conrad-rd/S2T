import Foundation

public struct BenchComparison: Identifiable {
    public let model: String
    public var id: String { model }
    public let a: [BenchResult]
    public let b: [BenchResult]
    public init(model: String, results: [BenchResult]) {
        self.model = model
        a = results.filter { $0.model == model && $0.variant == "A" }
        b = results.filter { $0.model == model && $0.variant == "B" }
    }
    public var paired: [(BenchResult, BenchResult)] {
        a.compactMap { baseline in
            guard let candidate = b.first(where: { $0.caseID == baseline.caseID && $0.metrics["repetition"] == baseline.metrics["repetition"] }) else { return nil }
            return (baseline, candidate)
        }
    }
    public var newFailures: Int { paired.filter { $0.0.status == .passed && $0.1.status == .failed }.count }
    public var tokenSavingsPercent: Double? {
        let pairs = paired.filter { $0.0.status == .passed && $0.1.status == .passed && $0.0.metrics["input_tokens"] != nil && $0.1.metrics["input_tokens"] != nil }
        guard !pairs.isEmpty else { return nil }
        let baseline = pairs.reduce(0) { $0 + $1.0.metrics["input_tokens"]! }
        let candidate = pairs.reduce(0) { $0 + $1.1.metrics["input_tokens"]! }
        return baseline > 0 ? (1 - candidate / baseline) * 100 : nil
    }
    public static func all(_ results: [BenchResult]) -> [Self] { Set(results.compactMap(\.model)).sorted().map { Self(model: $0, results: results) } }
}
