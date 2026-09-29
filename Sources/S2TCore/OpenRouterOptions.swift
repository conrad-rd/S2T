import Foundation

public struct OpenRouterOptions: Codable, Equatable, Sendable {
    public enum Effort: String, Codable, CaseIterable, Sendable {
        case automatic = "", none, minimal, low, medium, high, xhigh, max
        public var title: String {
            switch self {
            case .automatic: return "Model default"
            case .xhigh: return "Extra high"
            case .max: return "Maximum"
            default: return rawValue.capitalized
            }
        }
    }
    public var reasoning: Effort
    public var fast: Bool
    public var allowDataCollection: Bool
    public static let contributorModel = "meta/muse-spark-1.3-contributor"
    public static func supportedEfforts(for model: String) -> [Effort] {
        Effort.allCases
    }
    public func normalized(for model: String) -> Self {
        self
    }
    private enum CodingKeys: String, CodingKey { case reasoning, fast, allowDataCollection }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reasoning = try values.decodeIfPresent(Effort.self, forKey: .reasoning) ?? .automatic
        fast = try values.decodeIfPresent(Bool.self, forKey: .fast) ?? false
        allowDataCollection = try values.decodeIfPresent(Bool.self, forKey: .allowDataCollection) ?? false
    }
    func validateConsent(model: String) throws {
        if model == Self.contributorModel && !allowDataCollection {
            throw ServiceError.message("Muse Spark Contributor requires your opt-in under Models. Meta may use prompts and responses to improve its products. Your original words are preserved.")
        }
    }

    public init(reasoning: Effort = .automatic, fast: Bool = false, allowDataCollection: Bool = false) {
        self.reasoning = reasoning
        self.fast = fast
        self.allowDataCollection = allowDataCollection
    }

    func apply(to body: inout [String: Any], endpoint: String? = nil) {
        let effort = reasoning
        body["reasoning"] = effort != .automatic ? ["effort": effort.rawValue] : nil
        var routing: [String: Any] = ["data_collection": allowDataCollection && body["model"] as? String == Self.contributorModel ? "allow" : "deny"]
        if let endpoint = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines), !endpoint.isEmpty {
            routing["only"] = [endpoint]
            routing["allow_fallbacks"] = false
        } else if fast {
            routing["sort"] = "throughput"
        }
        body["provider"] = routing
    }
}
