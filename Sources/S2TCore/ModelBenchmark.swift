import Foundation

public enum BenchmarkCategory: String, CaseIterable, Codable, Sendable {
    case quality, speed, cost
    public var title: String { rawValue.capitalized }
}

public enum BenchmarkQuality: String, CaseIterable, Codable, Sendable {
    case speech, fleurs, intelligence
    public var title: String {
        switch self {
        case .speech: return "AA-WER v2"
        case .fleurs: return "FLEURS English"
        case .intelligence: return "AA Intelligence Index"
        }
    }
    public var lowerIsBetter: Bool { self == .speech || self == .fleurs }
}

public struct BenchmarkMeasurement: Equatable, Codable, Sendable {
    public let value: Double
    public let source: String
    public let note: String
    public let estimated: Bool
    public init(_ value: Double, source: String, note: String, estimated: Bool = false) {
        self.value = value
        self.source = source
        self.note = note
        self.estimated = estimated
    }
}

public struct BenchmarkModel: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let task: String
    public let modelID: String?
    public var quality: [BenchmarkQuality: BenchmarkMeasurement]
    public var speed: BenchmarkMeasurement?
    public var cost: BenchmarkMeasurement?

    public init(id: String, name: String, provider: String, task: String,
                quality: [BenchmarkQuality: BenchmarkMeasurement] = [:],
                speed: BenchmarkMeasurement? = nil, cost: BenchmarkMeasurement? = nil, modelID: String? = nil) {
        self.id = id; self.name = name; self.provider = provider; self.task = task
        self.quality = quality; self.speed = speed; self.cost = cost; self.modelID = modelID
    }

    public func measurement(_ category: BenchmarkCategory, quality basis: BenchmarkQuality) -> BenchmarkMeasurement? {
        let result: BenchmarkMeasurement?
        switch category {
        case .quality: result = quality[basis]
        case .speed: result = speed
        case .cost: result = cost
        }
        guard let result, result.value.isFinite, result.value >= 0 else { return nil }
        return result
    }

    public func formatted(_ category: BenchmarkCategory, quality basis: BenchmarkQuality) -> String {
        guard let measurement = measurement(category, quality: basis) else { return "Not measured" }
        let number = (measurement.estimated ? "~" : "") + measurement.value.formatted(.number.precision(.fractionLength(0...2)))
        switch category {
        case .quality: return number + (basis == .intelligence ? " points" : "%")
        case .speed: return number + (task == "speech" ? "× realtime" : " tokens/s")
        case .cost: return "$" + number + (task == "speech" ? " / 1,000 min" : " / 1M tokens")
        }
    }
}

public struct BenchmarkStanding: Identifiable, Sendable {
    public let model: BenchmarkModel
    public let contributions: [BenchmarkCategory: Double]
    public let rank: Int
    public var id: String { model.id }
    public var total: Double { contributions.values.reduce(0, +) }
}

public enum BenchmarkRanking {
    public static func top(_ ranked: [BenchmarkStanding], limit: Int = 5) -> [BenchmarkStanding] {
        var seen = Set<String>()
        let distinct = ranked.filter { seen.insert($0.model.modelID ?? $0.id).inserted }
        var previous: Double?
        var place = 0
        return Array(distinct.prefix(max(0, limit))).enumerated().map { index, row in
            if previous.map({ abs($0 - row.total) > 0.000001 }) ?? true { place = index + 1 }
            previous = row.total
            return .init(model: row.model, contributions: row.contributions, rank: place)
        }
    }

    public static func rank(_ models: [BenchmarkModel], enabled: Set<BenchmarkCategory>, quality: BenchmarkQuality) -> [BenchmarkStanding] {
        guard !enabled.isEmpty else { return [] }
        let categories = BenchmarkCategory.allCases.filter { enabled.contains($0) }
        // Keep each category's scale fixed when another category is toggled.
        let ranges = Dictionary(uniqueKeysWithValues: categories.compactMap { category -> (BenchmarkCategory, ClosedRange<Double>)? in
            let values = models.compactMap { $0.measurement(category, quality: quality)?.value }
            guard let low = values.min(), let high = values.max() else { return nil }
            return (category, low...high)
        })
        let scores: [(BenchmarkModel, [BenchmarkCategory: Double])] = models.compactMap { model in
            var contributions: [BenchmarkCategory: Double] = [:]
            for category in categories {
                guard let measurement = model.measurement(category, quality: quality), let range = ranges[category] else { return nil }
                let lowerIsBetter = category == .cost || (category == .quality && quality.lowerIsBetter)
                let span = range.upperBound - range.lowerBound
                let relative = span == 0 ? 1 : (measurement.value - range.lowerBound) / span
                let score = span == 0 ? 1 : lowerIsBetter ? 1 - relative : relative
                contributions[category] = score * 100 / Double(categories.count)
            }
            return (model, contributions)
        }
        let sorted = scores.sorted {
            let left = $0.1.values.reduce(0, +), right = $1.1.values.reduce(0, +)
            return abs(left - right) < 0.000001 ? $0.0.id < $1.0.id : left > right
        }
        var previous: Double?
        var rank = 0
        return sorted.enumerated().map { index, item in
            let total = item.1.values.reduce(0, +)
            if previous.map({ abs($0 - total) > 0.000001 }) ?? true { rank = index + 1 }
            previous = total
            return BenchmarkStanding(model: item.0, contributions: item.1, rank: rank)
        }
    }
}
