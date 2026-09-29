import Foundation

public struct BenchmarkOffering: Sendable {
    public let id: String
    public let name: String
    public let task: String
    public init(id: String, name: String, task: String) {
        self.id = id; self.name = name; self.task = task
    }
}

public enum BenchmarkAvailability {
    public static func filter(_ models: [BenchmarkModel], offered: [BenchmarkOffering]) -> [BenchmarkModel] {
        let versions = offered.map { (offer: $0, family: family($0.id)) }
        let latest = versions.filter { candidate in
            !versions.contains { other in
                other.offer.task == candidate.offer.task && other.family.name == candidate.family.name &&
                    candidate.family.version.compare(other.family.version, options: .numeric) == .orderedAscending
            }
        }.map(\.offer)
        func matches(_ model: BenchmarkModel, _ offer: BenchmarkOffering) -> Bool {
            guard offer.task == model.task, offer.id.hasPrefix("local/") == (model.provider == "Local") else { return false }
            func canonical(_ id: String) -> String {
                id.hasPrefix("openrouter/") ? String(id.dropFirst("openrouter/".count)) : id
            }
            if canonical(model.id) == canonical(offer.id) || model.modelID.map(canonical) == canonical(offer.id) || model.id == "reference/" + offer.id { return true }
            return normalized(model.name) == normalized(offer.name)
        }
        var result = models.compactMap { model -> BenchmarkModel? in
            guard let offer = latest.first(where: { matches(model, $0) }) else { return nil }
            guard model.task == "speech", offer.id.hasPrefix("openrouter/") else { return model }
            return .init(id: model.id, name: model.name, provider: "OpenRouter", task: model.task,
                         quality: model.quality, speed: model.speed, cost: model.cost, modelID: offer.id)
        }
        var seen = Set(result.map(\.id))
        for offer in latest where offer.task == "speech" && !result.contains(where: { matches($0, offer) }) {
            guard seen.insert(offer.id).inserted else { continue }
            let provider = offer.id.hasPrefix("local/") ? "Local" : offer.id.hasPrefix("assemblyai/") ? "AssemblyAI" : offer.id.hasPrefix("xai/") ? "xAI" : "OpenRouter"
            result.append(.init(id: offer.id, name: offer.name, provider: provider, task: offer.task))
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func family(_ id: String) -> (name: String, version: String) {
        if id.hasSuffix("openai/whisper-1") {
            return (id.replacingOccurrences(of: "whisper-1", with: "whisper-large-v{version}"), "1")
        }
        let patterns = [
            #"^(.*mai-transcribe-)([0-9.]+)$"#,
            #"^(.*grok-voice-transcribe-)([0-9.]+)$"#,
            #"^(.*universal-)([0-9-]+)(-pro)$"#,
            #"^(.*whisper-large-v)([0-9]+)(.*)$"#,
            #"^(.*gemini-)([0-9.]+)(-.*)$"#,
            #"^(.*claude-(?:opus|sonnet|haiku)-)([0-9.]+)(.*)$"#,
            #"^(.*gpt-)([0-9.]+)(.*)$"#
        ]
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(id.startIndex..., in: id)
            guard let match = regex.firstMatch(in: id, range: range), let versionRange = Range(match.range(at: 2), in: id) else { continue }
            let version = String(id[versionRange]).replacingOccurrences(of: "-", with: ".")
            return (id.replacingCharacters(in: versionRange, with: "{version}"), version)
        }
        return (id, "")
    }
}
