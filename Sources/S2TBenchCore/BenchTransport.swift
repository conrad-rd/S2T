import Foundation
import S2TCore

public struct BenchUsage: Sendable {
    public var requestBytes = 0
    public var inputTokens: Double?
    public var outputTokens: Double?
    public var cachedTokens: Double?
    public var reasoningTokens: Double?
    public var cost: Double?
    public var status = 0
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Uses the production request builder while measuring and bounding its transport.
public actor BenchTransport: HTTPTransport {
    private let session: URLSession
    private let maxTokens: Int
    private let deadline: Double
    private var usage = BenchUsage()
    public init(maxTokens: Int, timeout: Double, configuration: URLSessionConfiguration? = nil) {
        self.maxTokens = max(32, min(8192, maxTokens)); deadline = max(1, min(300, timeout))
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = deadline; config.timeoutIntervalForResource = deadline
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    public func metrics() -> BenchUsage { usage }
    public func data(for original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = original
        request.timeoutInterval = deadline
        if request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true,
           let bytes = request.httpBody, var body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            body["max_tokens"] = maxTokens
            body["temperature"] = 0
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        usage.requestBytes = request.httpBody?.count ?? 0
        let (stream, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        usage.status = response.statusCode
        guard response.expectedContentLength <= 2_000_000 else { throw BenchError.message("Response exceeds 2 MB.") }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < 2_000_000 else { throw BenchError.message("Response exceeds 2 MB.") }
            data.append(byte)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let values = object["usage"] as? [String: Any] {
            func number(_ value: Any?) -> Double? {
                guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite, value.doubleValue >= 0 else { return nil }
                return value.doubleValue
            }
            usage.inputTokens = number(values["prompt_tokens"])
            usage.outputTokens = number(values["completion_tokens"])
            usage.cachedTokens = number((values["prompt_tokens_details"] as? [String: Any])?["cached_tokens"])
            usage.reasoningTokens = number((values["completion_tokens_details"] as? [String: Any])?["reasoning_tokens"])
            usage.cost = number(values["cost"])
        }
        return (data, response)
    }
}

public enum BenchProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case local, managed, openRouter
    public var id: String { rawValue }
    public var title: String {
        switch self { case .local: return "Local endpoint"; case .managed: return "S2T installed models"; case .openRouter: return "OpenRouter" }
    }
    public var cloud: Bool { self == .openRouter }
}

public struct PromptRunConfiguration: Sendable {
    public var provider: BenchProvider
    public var address: String
    public var host: String
    public var models: [String]
    public var key: String
    public var baseline: String
    public var candidate: String
    public var repetitions: Int
    public var requestLimit: Int
    public var maxTokens: Int
    public var timeout: Double
    public var seed: UInt64
    public init(provider: BenchProvider, address: String, host: String, models: [String], key: String, baseline: String, candidate: String, repetitions: Int, requestLimit: Int, maxTokens: Int, timeout: Double, seed: UInt64) {
        self.provider = provider; self.address = address; self.host = host; self.models = models; self.key = key
        self.baseline = baseline; self.candidate = candidate; self.repetitions = repetitions; self.requestLimit = requestLimit
        self.maxTokens = maxTokens; self.timeout = timeout; self.seed = seed
    }
    public func validate() throws {
        guard (1...20).contains(repetitions), (1...2000).contains(requestLimit), (32...8192).contains(maxTokens), (1...300).contains(timeout),
              (1...8).contains(models.count), models.allSatisfy({ !$0.isEmpty && $0.utf8.count < 200 && !$0.contains(where: \.isWhitespace) }),
              !baseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              baseline.utf8.count <= 65536, candidate.utf8.count <= 65536 else { throw BenchError.message("Check model IDs, prompt lengths and benchmark limits.") }
        if provider.cloud && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw BenchError.message("Enter the selected provider's key for this session.") }
        if provider == .local || provider == .managed { _ = try BenchEndpoint.local(address) }
    }
}

public enum PromptBenchmark {
    public static func run(_ config: PromptRunConfiguration, cases: [PromptCase] = PromptCorpus.cases,
                           emit: @escaping @Sendable (BenchResult) async -> Void) async throws {
        try config.validate()
        var attempted = 0
        for model in config.models {
            for repetition in 0..<config.repetitions {
                let ordered = BenchRandom.shuffled(cases, seed: config.seed &+ UInt64(repetition))
                for (index, test) in ordered.enumerated() {
                    let variants = (index + repetition).isMultiple(of: 2) ? ["A", "B"] : ["B", "A"]
                    for variant in variants {
                        try Task.checkCancellation()
                        guard attempted < config.requestLimit else {
                            let remaining = config.models.count * config.repetitions * cases.count * 2 - attempted
                            await emit(BenchResult(suite: "prompts", name: "Request limit", status: .skipped,
                                detail: "Stopped at the configured limit. \(remaining) comparisons were not run.", metrics: ["unrun_requests": Double(remaining)]))
                            return
                        }
                        attempted += 1
                        let transport = BenchTransport(maxTokens: config.maxTokens, timeout: config.timeout)
                        let api = DictationAPI(transport: transport)
                        let started = ProcessInfo.processInfo.systemUptime
                        var result = BenchResult(suite: "prompts", name: "\(model) · \(variant) · \(test.name) · \(repetition + 1)", status: .passed, detail: "All explicit assertions passed. Semantic quality still needs review.")
                        result.input = test.input
                        result.model = model; result.variant = variant; result.caseID = test.id
                        do {
                            let response = try await api.process(text: test.input, mode: .clean, model: model, apiKey: config.provider.cloud ? config.key : "",
                                provider: config.provider == .openRouter ? .openRouter : .local,
                                endpoint: config.host.isEmpty ? nil : config.host,
                                instructions: variant == "A" ? config.baseline : config.candidate, localURL: config.address)
                            result.output = response.text
                            let failures = test.failures(output: response.text)
                            if !failures.isEmpty { result.status = .failed; result.detail = failures.joined(separator: "; ") }
                            result.detail += " Requested \(model); returned \(response.model), host \(response.host ?? "unreported")."
                        } catch {
                            if Task.isCancelled { throw CancellationError() }
                            result.status = .failed
                            result.detail = "Request failed: \(error.localizedDescription.replacingOccurrences(of: config.key.isEmpty ? "\u{0}" : config.key, with: "[redacted]"))"
                        }
                        let usage = await transport.metrics()
                        result.metrics = ["latency_ms": (ProcessInfo.processInfo.systemUptime - started) * 1000,
                            "request_bytes": Double(usage.requestBytes), "http_status": Double(usage.status), "repetition": Double(repetition + 1)]
                        for (key, value) in [("input_tokens", usage.inputTokens), ("output_tokens", usage.outputTokens), ("cached_tokens", usage.cachedTokens), ("reasoning_tokens", usage.reasoningTokens), ("cost_usd", usage.cost)] {
                            if let value { result.metrics[key] = value }
                        }
                        if usage.inputTokens == nil { result.detail += " Token usage unreported." }
                        if !config.key.isEmpty {
                            result.detail = result.detail.replacingOccurrences(of: config.key, with: "[redacted]")
                            result.output = result.output?.replacingOccurrences(of: config.key, with: "[redacted]")
                        }
                        await emit(result)
                    }
                }
            }
        }
    }
}
