import Foundation
import CryptoKit

public struct BenchStatistics: Sendable {
    public let samples: [Double]
    public init(_ samples: [Double]) { self.samples = samples.filter { $0.isFinite && $0 >= 0 }.sorted() }
    public var median: Double? { percentile(0.5) }
    public var p95: Double? { percentile(0.95) }
    public var p99: Double? { percentile(0.99) }
    public var maximum: Double? { samples.last }
    public var mean: Double? { samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count) }
    public func over(_ threshold: Double) -> Int { samples.filter { $0 > threshold }.count }
    public func percentile(_ fraction: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples[min(samples.count - 1, max(0, Int(ceil(Double(samples.count) * fraction)) - 1))]
    }
}

public enum BenchStatus: String, Codable, Sendable { case passed, failed, skipped, cancelled }

public struct BenchResult: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var suite: String
    public var name: String
    public var status: BenchStatus
    public var detail: String
    public var metrics: [String: Double]
    public var samples: [Double] = []
    public var input: String?
    public var output: String?
    public var model: String?
    public var variant: String?
    public var caseID: String?
    public init(suite: String, name: String, status: BenchStatus, detail: String, metrics: [String: Double] = [:]) {
        self.suite = suite; self.name = name; self.status = status; self.detail = detail; self.metrics = metrics
    }
}

public struct BenchReport: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var created = Date()
    public var schema = 1
    public var machine = ProcessInfo.processInfo.operatingSystemVersionString
    public var processors = ProcessInfo.processInfo.activeProcessorCount
    public var memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
    public var settings: [String: String]
    public var results: [BenchResult]
    public init(results: [BenchResult], settings: [String: String]) { self.results = results; self.settings = settings }
    public func encoded(includeText: Bool) throws -> Data {
        var copy = self
        if !includeText { for i in copy.results.indices { copy.results[i].input = nil; copy.results[i].output = nil } }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(copy)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 32_000_000 else { throw BenchError.message("Report exceeds 32 MB.") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(Self.self, from: data)
        guard report.schema == 1, report.results.count <= 20_000 else { throw BenchError.message("Unsupported report.") }
        return report
    }
}

public enum BenchReportHistory {
    public static func load(from directory: URL, limit: Int = 100) -> [BenchReport] {
        guard limit > 0 else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? BenchReport.decode(data)
        }.sorted {
            $0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created > $1.created
        }.prefix(limit).map { $0 }
    }
}

public enum BenchError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct BenchRandom: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    public static func shuffled<T>(_ values: [T], seed: UInt64) -> [T] { var rng = Self(seed: seed); return values.shuffled(using: &rng) }
}

public enum BenchEndpoint {
    public static func local(_ address: String) throws -> URL {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme),
              ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw BenchError.message("Use a loopback HTTP endpoint without credentials, query parameters or fragments.")
        }
        return url
    }
    public static func fingerprint(_ text: String) -> String { fingerprint(Data(text.utf8)) }
    public static func fingerprint(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
