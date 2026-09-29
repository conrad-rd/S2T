import Foundation

public struct OpenRouterReasoning: Codable, Equatable, Sendable {
    public var mandatory: Bool?
    public var supported_efforts: [String]?

    public var efforts: [OpenRouterOptions.Effort] {
        [.automatic] + OpenRouterOptions.Effort.allCases.filter {
            $0 != .automatic && supported_efforts?.contains($0.rawValue) == true && !($0 == .none && mandatory == true)
        }
    }
}

public final class OpenRouterReasoningCatalog: @unchecked Sendable {
    public static let updated = Notification.Name("S2TOpenRouterReasoningUpdated")
    public static let shared = OpenRouterReasoningCatalog(entries: bundled)
    private let lock = NSLock()
    private let initial: [String: OpenRouterReasoning]
    private var refreshed: [String: OpenRouterReasoning] = [:]
    private var checkedAt: [String: Date] = [:]
    private var loading = Set<String>()

    public init(entries: [String: OpenRouterReasoning]) { initial = entries }

    public func efforts(for model: String) -> [OpenRouterOptions.Effort] {
        lock.withLock { (refreshed[model] ?? initial[model])?.efforts ?? [.automatic] }
    }

    public func refresh(model: String, transport: any HTTPTransport = SessionTransport()) async {
        guard ProcessingProvider.openRouter.validModelID(model), begin(model) else { return }
        var value: OpenRouterReasoning?
        var successful = false
        do {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/:"))
            guard let escaped = model.addingPercentEncoding(withAllowedCharacters: allowed),
                  let url = URL(string: "https://openrouter.ai/api/v1/model/" + escaped) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await transport.data(for: request)
            guard data.count <= 1_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
            if response.statusCode == 404 {
                value = OpenRouterReasoning(); successful = true
            } else {
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                struct Response: Decodable { let data: Entry }
                let entry = try JSONDecoder().decode(Response.self, from: data).data
                guard entry.id == model || entry.canonical_slug == model else { throw URLError(.cannotParseResponse) }
                value = entry.reasoning ?? OpenRouterReasoning(); successful = true
            }
        } catch { }
        finish(model, value: value, successful: successful)
    }

    private func begin(_ model: String) -> Bool {
        lock.withLock {
            guard !loading.contains(model), checkedAt[model].map({ Date().timeIntervalSince($0) >= 3600 }) ?? true else { return false }
            loading.insert(model)
            return true
        }
    }

    private func finish(_ model: String, value: OpenRouterReasoning?, successful: Bool) {
        lock.withLock {
            loading.remove(model)
            if checkedAt.count >= 256, let oldest = checkedAt.min(by: { $0.value < $1.value })?.key {
                checkedAt.removeValue(forKey: oldest); refreshed.removeValue(forKey: oldest)
            }
            checkedAt[model] = Date().addingTimeInterval(successful ? 0 : -3540)
            if let value { refreshed[model] = value }
        }
        if successful { NotificationCenter.default.post(name: Self.updated, object: self) }
    }

    private struct Entry: Decodable {
        let id: String
        let canonical_slug: String?
        let reasoning: OpenRouterReasoning?
    }

    public static func decode(_ data: Data) throws -> [String: OpenRouterReasoning] {
        struct Response: Decodable { let data: [Entry] }
        let entries = try JSONDecoder().decode(Response.self, from: data).data
        var result: [String: OpenRouterReasoning] = [:]
        for entry in entries where ProcessingProvider.openRouter.validModelID(entry.id) {
            let value = entry.reasoning ?? OpenRouterReasoning()
            result[entry.id] = value
            if let canonical = entry.canonical_slug { result[canonical] = value }
        }
        return result
    }

    private static var bundled: [String: OpenRouterReasoning] {
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("S2T_S2TCore.bundle")) }
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? packaged : packaged ?? Bundle.module
        guard let url = bundle?.url(forResource: "OpenRouterReasoning", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? decode(data) else { return [:] }
        return entries
    }
}
