import Foundation

/// Bounded, local numeric diagnostics. No audio, text, credentials or field identities.
public enum DictationTiming {
    public static let historyKey = "dictationTimingHistory"
    public static func record(_ durations: [String: Double], outcome: String, defaults: UserDefaults, at: Date = Date()) {
        let safe = durations.filter { $0.key.count <= 64 && $0.value.isFinite && $0.value >= 0 }
        let entry: [String: Any] = ["at": at.timeIntervalSince1970, "outcome": outcome, "durations": safe]
        var history = defaults.array(forKey: historyKey) as? [[String: Any]] ?? []
        history.append(entry)
        defaults.set(Array(history.suffix(20)), forKey: historyKey)
    }
}
