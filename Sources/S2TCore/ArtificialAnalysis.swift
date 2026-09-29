import Foundation

public struct ArtificialAnalysisSnapshot: Codable, Sendable {
    public let models: [BenchmarkModel]
    public let fetchedAt: Date
    public let tier: String
    public let indexVersion: Double?
    public let speechAvailable: Bool
    public let warning: String?
}

public enum ArtificialAnalysisError: Error, LocalizedError {
    case http(Int), invalidData
    public var errorDescription: String? {
        switch self {
        case .http(401): return "Artificial Analysis rejected the key. Update it in API keys."
        case .http(403): return "This Artificial Analysis subscription does not include the requested data."
        case .http(429): return "Artificial Analysis's daily request limit was reached. Try again tomorrow."
        case .http: return "Artificial Analysis is unavailable. Try again later."
        case .invalidData: return "Artificial Analysis returned incomplete or incompatible data."
        }
    }
}

public struct ArtificialAnalysisClient: Sendable {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = SessionTransport()) { self.transport = transport }

    public func fetch(key: String, now: Date = Date()) async throws -> ArtificialAnalysisSnapshot {
        do {
            let legacy: AALegacyModels = try await read("data/llms/models", key: key)
            guard legacy.status == 200, !legacy.data.isEmpty else { throw ArtificialAnalysisError.invalidData }
            let providers: [AAProvider]
            do {
                let response: AAPage<AAProvider> = try await pages("language/providers", key: key)
                providers = response.data
            } catch ArtificialAnalysisError.http(let status) where [403, 404, 410].contains(status) {
                providers = []
            }
            var models = Self.languageModels(legacy.data, providers: providers, version: legacy.intelligenceIndexVersion,
                workload: legacy.promptOptions?.promptLength ?? "medium")
            var speechAvailable = false
            var warning: String?
            do {
                let speech: AAPage<AASpeech> = try await page("media/speech-to-text/models" + (providers.isEmpty ? "/free" : ""), key: key)
                guard !speech.data.isEmpty else { throw ArtificialAnalysisError.invalidData }
                models += Self.speechModels(speech.data)
                speechAvailable = true
            } catch is CancellationError { throw CancellationError() }
            catch { warning = "Speech data could not refresh. Dictation uses dated reference data." }
            return .init(models: Self.unique(models), fetchedAt: now, tier: providers.isEmpty ? "free" : "commercial",
                indexVersion: legacy.intelligenceIndexVersion, speechAvailable: speechAvailable, warning: warning)
        } catch ArtificialAnalysisError.http(let status) where [404, 410].contains(status) {
            return try await fetchV2(key: key, now: now)
        }
    }

    public func validateKey(_ key: String) async throws {
        do { let _: AAKeyCheck = try await read("data/llms/models", key: key) }
        catch ArtificialAnalysisError.http(let status) where [404, 410].contains(status) {
            let _: AAKeyCheck = try await read("language/models/free", key: key)
        }
    }

    private func fetchV2(key: String, now: Date) async throws -> ArtificialAnalysisSnapshot {
        let first: AAPage<AAModel> = try await page("language/models/free", key: key)
        let paid = first.tier == "pro" || first.tier == "commercial"
        let language: AAPage<AAModel> = paid
            ? try await pages("language/models", key: key)
            : try await pages("language/models/free", key: key, first: first)
        guard !language.data.isEmpty else { throw ArtificialAnalysisError.invalidData }
        let providers: [AAProvider]
        if first.tier == "commercial" {
            let result: AAPage<AAProvider> = try await pages("language/providers", key: key)
            providers = result.data
        } else { providers = [] }
        var models = Self.languageModels(language.data, providers: providers, version: language.intelligenceIndexVersion, workload: paid ? "long" : "medium")
        var speechAvailable = false
        var warning: String?
        do {
            let speech: AAPage<AASpeech> = try await page("media/speech-to-text/models" + (paid ? "" : "/free"), key: key)
            guard !speech.data.isEmpty else { throw ArtificialAnalysisError.invalidData }
            models += Self.speechModels(speech.data)
            speechAvailable = true
        } catch is CancellationError { throw CancellationError() }
        catch { warning = "Speech data could not refresh. Dictation uses dated reference data." }
        return .init(models: Self.unique(models), fetchedAt: now, tier: first.tier, indexVersion: language.intelligenceIndexVersion,
                     speechAvailable: speechAvailable, warning: warning)
    }

    private static func unique(_ models: [BenchmarkModel]) -> [BenchmarkModel] {
        var seen = Set<String>()
        return models.filter { seen.insert($0.id).inserted }
    }

    private func page<T: Decodable>(_ path: String, key: String, number: Int = 1) async throws -> AAPage<T> {
        try await read(path, key: key, number: path.hasPrefix("language/") ? number : nil)
    }

    private func read<T: Decodable>(_ path: String, key: String, number: Int? = nil) async throws -> T {
        try Task.checkCancellation()
        var components = URLComponents(string: "https://artificialanalysis.ai/api/v2/" + path)!
        if let number { components.queryItems = [.init(name: "page", value: String(number))] }
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else { throw ArtificialAnalysisError.http(response.statusCode) }
        guard data.count <= 15_000_000 else { throw ArtificialAnalysisError.invalidData }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func pages<T: Decodable>(_ path: String, key: String, first: AAPage<T>? = nil) async throws -> AAPage<T> {
        var result: AAPage<T>
        if let first { result = first } else { result = try await page(path, key: key) }
        guard result.pagination?.page == 1 else { throw ArtificialAnalysisError.invalidData }
        var current = result
        var number = 1
        while current.pagination?.hasMore == true {
            guard number < 50, current.pagination?.page == number else { throw ArtificialAnalysisError.invalidData }
            number += 1
            current = try await page(path, key: key, number: number)
            guard current.tier == result.tier, current.intelligenceIndexVersion == result.intelligenceIndexVersion,
                  current.pagination?.page == number else { throw ArtificialAnalysisError.invalidData }
            result.data += current.data
        }
        return result
    }

    private static func languageModels(_ models: [AAModel], providers: [AAProvider], version: Double?, workload: String) -> [BenchmarkModel] {
        var result: [BenchmarkModel] = []
        for model in models {
            let source = "https://artificialanalysis.ai/models/" + model.slug
            let pairs = providers.flatMap { provider in
                provider.models.filter { $0.id == model.id }.map { (provider, $0) }
            }
            let basis: BenchmarkQuality = .intelligence
            let value = model.evaluations.artificialAnalysisIntelligenceIndex
            let note = "Artificial Analysis Intelligence Index. " + (version.map { "Version \($0)." } ?? "Version not reported by this endpoint.")
            let quality = measurement(value, source: source, note: note).map { [basis: $0] } ?? [:]
            if pairs.isEmpty {
                result.append(.init(id: "aa/\(model.id)/text", name: model.name, provider: "AA reference", task: "text",
                    quality: quality,
                    speed: providers.isEmpty ? measurement(model.medianOutputTokensPerSecond ?? model.performance?.medianOutputTokensPerSecond,
                        source: source, note: "AA model-level output TPS. Workload: " + workload + ". The API does not identify the measured host; this is not a Cerebras or OpenRouter host measurement.") : nil,
                    cost: price(model.pricing, source: source, host: "Model-level reference"), modelID: model.id))
            } else {
                for (provider, endpoint) in pairs {
                    result.append(.init(id: "aa/\(model.id)/\(provider.id)/text", name: model.name, provider: provider.name, task: "text",
                        quality: quality,
                        speed: measurement(endpoint.performance?.medianOutputTokensPerSecond, source: source + "/providers",
                            note: "Measured on \(provider.name) only. Median output tokens per second; not time to first token or an OpenRouter routing guarantee."),
                        cost: price(endpoint.pricing, source: source + "/providers", host: provider.name), modelID: model.id))
                }
            }
        }
        return result
    }

    private static func speechModels(_ models: [AASpeech]) -> [BenchmarkModel] {
        models.flatMap { model -> [BenchmarkModel] in
            let source = "https://artificialanalysis.ai/speech-to-text"
            let providers = model.providers ?? []
            if providers.isEmpty {
                let quality = measurement(model.aaWerIndex, source: source, note: "Artificial Analysis Word Error Rate index.").map { [BenchmarkQuality.speech: $0] } ?? [:]
                return [.init(id: "aa/\(model.id)/speech", name: model.name, provider: "Host unspecified", task: "speech", quality: quality, modelID: model.id)]
            }
            return providers.map { host in
                let quality = measurement(host.aaWerIndex ?? model.aaWerIndex, source: source, note: "Artificial Analysis Word Error Rate index. Host: \(host.name).").map { [BenchmarkQuality.speech: $0] } ?? [:]
                return .init(id: "aa/\(model.id)/\(host.id)/speech", name: model.name, provider: host.name, task: "speech", quality: quality,
                    speed: measurement(host.medianSpeedFactor, source: source, note: "Audio processing speed relative to real time, measured on \(host.name). This is not text generation TPS."),
                    cost: measurement(host.pricePer1KMinutes, source: source, note: "Price per 1,000 audio minutes on \(host.name)."), modelID: model.id)
            }
        }
    }
    private static func measurement(_ value: Double?, source: String, note: String) -> BenchmarkMeasurement? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return .init(value, source: source, note: note)
    }
    private static func price(_ value: AAPricing?, source: String, host: String) -> BenchmarkMeasurement? {
        if let blended = value?.price1MBlended3To1 {
            return measurement(blended, source: source, note: "\(host). AA 3:1 input/output blended USD per million tokens.")
        }
        guard let input = value?.price1MInputTokens, let output = value?.price1MOutputTokens,
              input >= 0, output >= 0 else { return nil }
        return measurement((3 * input + output) / 4, source: source, note: "\(host). USD per million tokens, 3:1 input/output blend.")
    }
}

private struct AAPage<T: Decodable>: Decodable {
    let tier: String
    let intelligenceIndexVersion: Double?
    let pagination: AAPagination?
    var data: [T]
}
private struct AAPagination: Decodable { let page: Int; let hasMore: Bool }
private struct AAPricing: Decodable { let price1MInputTokens: Double?; let price1MOutputTokens: Double?; let price1MBlended3To1: Double? }
private struct AAPerformance: Decodable { let medianOutputTokensPerSecond: Double? }
private struct AAEvaluations: Decodable { let artificialAnalysisIntelligenceIndex: Double?; let mmmuPro: Double? }
private struct AAModalities: Decodable {
    struct Input: Decodable { let image: Bool }
    let input: Input
}
private struct AAModel: Decodable {
    let id: String; let name: String; let slug: String
    let evaluations: AAEvaluations; let pricing: AAPricing?; let modalities: AAModalities?
    let medianOutputTokensPerSecond: Double?; let performance: AAPerformance?
}
private struct AAProvider: Decodable {
    let id: String; let name: String
    let models: [AAEndpoint]
}
private struct AAEndpoint: Decodable {
    let id: String; let pricing: AAPricing?; let performance: AAPerformance?
}
private struct AASpeech: Decodable {
    let id: String; let name: String; let aaWerIndex: Double?
    let providers: [AASpeechHost]?
}
private struct AASpeechHost: Decodable {
    let id: String; let name: String; let aaWerIndex: Double?
    let pricePer1KMinutes: Double?; let medianSpeedFactor: Double?
}

private struct AAKeyCheck: Decodable {}
private struct AALegacyModels: Decodable {
    struct PromptOptions: Decodable { let promptLength: String? }
    let status: Int
    let intelligenceIndexVersion: Double?
    let promptOptions: PromptOptions?
    let data: [AAModel]
}
