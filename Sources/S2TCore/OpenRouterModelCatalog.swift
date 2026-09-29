import Foundation

public struct OpenRouterTextModel: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var acceptsImages: Bool { architecture.input_modalities.contains("image") }
    private let architecture: Architecture
    private struct Architecture: Decodable, Equatable, Sendable {
        let input_modalities: [String]
        let output_modalities: [String]
    }
    public static func load(transport: any HTTPTransport = SessionTransport()) async throws -> [Self] {
        try decode(await OpenRouterCatalogRequest.load("models?output_modalities=text", transport: transport))
    }
    public static func decode(_ data: Data) throws -> [Self] {
        struct Catalog: Decodable { let data: [OpenRouterTextModel] }
        var seen = Set<String>()
        return try JSONDecoder().decode(Catalog.self, from: data).data.filter {
            $0.architecture.input_modalities.contains("text") && $0.architecture.output_modalities.contains("text") &&
            ProcessingProvider.openRouter.validModelID($0.id) && seen.insert($0.id).inserted
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public struct OpenRouterHost: Decodable, Equatable, Sendable {
    public let tag: String
    public let provider_name: String
    public let quantization: String?
    public let status: Int?
    public let pricing: Pricing
    public let throughput_last_30m: Percentiles?
    public struct Pricing: Decodable, Equatable, Sendable {
        public let prompt: String?
        public let completion: String?
        public let request: String?
    }
    public struct Percentiles: Decodable, Equatable, Sendable { public let p50: Double? }
    public var combinedPrice: Double? {
        guard let input = price(pricing.prompt), let output = price(pricing.completion) else { return nil }
        return input + output
    }
    private func price(_ value: String?) -> Double? {
        guard let value, let number = Double(value), number.isFinite, number >= 0 else { return nil }
        return number
    }
    public func menuTitle(cheapest: Double?) -> String {
        var parts = [provider_name + (quantization.map { " · " + $0 } ?? "")]
        if let speed = throughput_last_30m?.p50, speed.isFinite, speed > 0 {
            parts.append(speed.formatted(.number.precision(.fractionLength(0))) + " tok/s")
        } else { parts.append("Speed unavailable") }
        if let input = price(pricing.prompt), let output = price(pricing.completion) {
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...3))
            parts.append("$" + (input * 1e6).formatted(format) + " in / $" + (output * 1e6).formatted(format) + " out per 1M")
            if let cheapest, cheapest > 0, let total = combinedPrice {
                parts.append("+" + max(0, (total / cheapest - 1) * 100).formatted(.number.precision(.fractionLength(0))) + "%")
            }
        } else { parts.append("Price unavailable") }
        if let request = price(pricing.request), request > 0 {
            parts.append("$" + request.formatted(.number.precision(.fractionLength(0...6))) + "/request")
        }
        return parts.joined(separator: " · ")
    }
    public static func load(model: String, transport: any HTTPTransport = SessionTransport()) async throws -> [Self] {
        guard ProcessingProvider.openRouter.validModelID(model) else { throw URLError(.badURL) }
        let path = model.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! }.joined(separator: "/")
        return try decode(await OpenRouterCatalogRequest.load("models/" + path + "/endpoints", transport: transport))
    }
    public static func decode(_ data: Data) throws -> [Self] {
        struct Response: Decodable { let data: Endpoints }
        struct Endpoints: Decodable { let endpoints: [OpenRouterHost] }
        var seen = Set<String>()
        return try JSONDecoder().decode(Response.self, from: data).data.endpoints.filter {
            ($0.status == nil || $0.status == 0) && !$0.tag.isEmpty && seen.insert($0.tag).inserted
        }.sorted { $0.provider_name == $1.provider_name ? $0.tag < $1.tag : $0.provider_name < $1.provider_name }
    }
}

private enum OpenRouterCatalogRequest {
    static func load(_ path: String, transport: any HTTPTransport) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/" + path)!)
        request.timeoutInterval = 15
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200, data.count <= 8_000_000 else { throw URLError(.badServerResponse) }
        return data
    }
}
