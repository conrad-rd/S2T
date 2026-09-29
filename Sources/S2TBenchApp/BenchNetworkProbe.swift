import Foundation
import S2TBenchCore

private actor ProbeResults {
    var results: [BenchResult] = []
    func add(_ result: BenchResult) { results.append(result) }
}

enum BenchNetworkProbe {
    static func run(address: String) async throws {
        _ = try BenchEndpoint.local(address)
        let config = PromptRunConfiguration(provider: .local, address: address, host: "", models: ["fixture"], key: "never-send-this-fixture-key",
            baseline: "BASELINE", candidate: "CANDIDATE", repetitions: 2, requestLimit: 4, maxTokens: 256, timeout: 3, seed: 42)
        let collected = ProbeResults()
        try await PromptBenchmark.run(config, cases: PromptCorpus.cases.filter { ["question", "negation"].contains($0.id) }) { result in await collected.add(result) }
        let results = await collected.results
        guard results.count == 5, results.filter({ $0.status == .failed }).count == 1,
              results.last?.status == .skipped, results.last?.metrics["unrun_requests"] == 4,
              results.prefix(4).allSatisfy({ $0.metrics["http_status"] == 200 && ($0.metrics["request_bytes"] ?? 0) > 0 }),
              BenchComparison(model: "fixture", results: results).tokenSavingsPercent == 60 else {
            throw BenchError.message("Live loopback comparison lost failures, usage, matched pairs or request limits.")
        }
        let report = BenchReport(results: results, settings: ["fixture": "loopback"])
        let encoded = try report.encoded(includeText: false)
        let restored = try BenchReport.decode(encoded)
        guard restored.results.count == 5, !String(decoding: encoded, as: UTF8.self).contains("never-send-this-fixture-key") else { throw BenchError.message("Report round trip or secret isolation failed.") }
        print("PASS: real loopback HTTP, production request envelope, adversarial failure, A/B pairing, actual token usage, hard request cap and redacted report round trip.")
    }
}
