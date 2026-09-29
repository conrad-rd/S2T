import Foundation

public enum SpeechScore {
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    public static func wordErrorRate(expected: String, actual: String) -> Double {
        let reference = words(expected), hypothesis = words(actual)
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        var previous = Array(0...hypothesis.count)
        for (i, word) in reference.enumerated() {
            var row = [i + 1]
            for (j, other) in hypothesis.enumerated() { row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (word == other ? 0 : 1))) }
            previous = row
        }
        return Double(previous.last!) / Double(reference.count)
    }
}
