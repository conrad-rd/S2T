import Foundation

public struct DictionaryObservation {
    public static let settlingDelay: TimeInterval = 0.2
    public enum Update {
        case waiting
        case stopped
        case suggestions(entries: [DictionaryCorrection], range: NSRange)
    }

    private let prefix: String
    private let suffix: String
    private let deadline: TimeInterval
    private let original: String
    private var evaluated: String
    private var previous: String?
    private var stableSince: TimeInterval
    private var needsEvaluation = false
    private var stopped = false

    public init?(output: String, baseline: String, startedAt: TimeInterval, selection: NSRange? = nil,
                 insertionSelection: NSRange? = nil, insertionBaseline: String? = nil) {
        guard !output.isEmpty, output.utf8.count <= 16_384, baseline.utf8.count <= 16_384 else { return nil }
        let parts = output.split(whereSeparator: { $0.isWhitespace })
        guard !parts.isEmpty else { return nil }
        let pattern = parts.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = expression.matches(in: baseline, range: NSRange(baseline.startIndex..., in: baseline))
        let match: NSTextCheckingResult?
        if let insertionSelection { match = matches.first(where: { $0.range.location == insertionSelection.location }) }
        else if matches.count == 1 { match = matches.first }
        else if let selection {
            let adjacent = matches.filter { NSMaxRange($0.range) == selection.location || $0.range == selection }
            match = adjacent.count == 1 ? adjacent.first : nil
        } else { match = nil }
        let range: Range<String.Index>
        let alreadyCorrected: Bool
        if let match, let exact = Range(match.range, in: baseline) {
            range = exact
            alreadyCorrected = false
        } else if let insertionSelection, let insertionBaseline, insertionBaseline.utf8.count <= 16_384,
                  insertionBaseline != baseline, insertionSelection.location >= 0, insertionSelection.length >= 0,
                  insertionSelection.location <= insertionBaseline.utf16.count,
                  insertionSelection.length <= insertionBaseline.utf16.count - insertionSelection.location,
                  let replaced = Range(insertionSelection, in: insertionBaseline) {
            let before = String(insertionBaseline[..<replaced.lowerBound])
            let after = String(insertionBaseline[replaced.upperBound...])
            guard baseline.hasPrefix(before), baseline.hasSuffix(after), baseline.count >= before.count + after.count else { return nil }
            range = baseline.index(baseline.startIndex, offsetBy: before.count)..<baseline.index(baseline.endIndex, offsetBy: -after.count)
            guard !DictionaryCorrections.entries(original: output, corrected: String(baseline[range])).isEmpty else { return nil }
            alreadyCorrected = true
        } else { return nil }
        prefix = String(baseline[..<range.lowerBound])
        suffix = String(baseline[range.upperBound...])
        original = alreadyCorrected ? output : String(baseline[range])
        evaluated = original
        deadline = startedAt + 60
        stableSince = startedAt
        if alreadyCorrected { previous = baseline; needsEvaluation = true }
    }

    public mutating func sample(_ current: String?, at time: TimeInterval) -> Update {
        guard !stopped, time < deadline, let current, current.utf8.count <= 16_384,
              current.hasPrefix(prefix), current.hasSuffix(suffix),
              current.count >= prefix.count + suffix.count else {
            stopped = true
            return .stopped
        }
        if previous != current {
            if previous != nil || current != prefix + original + suffix { needsEvaluation = true }
            previous = current
            stableSince = time
            return .waiting
        }
        guard time - stableSince + 0.000_001 >= Self.settlingDelay else { return .waiting }
        let edited = String(current.dropFirst(prefix.count).dropLast(suffix.count))
        guard !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            stopped = true
            return .stopped
        }
        guard evaluated != edited || needsEvaluation else { return .waiting }
        needsEvaluation = false
        let entries = DictionaryCorrections.entries(original: original, corrected: edited)
        evaluated = edited
        return .suggestions(entries: entries, range: NSRange(location: prefix.utf16.count, length: edited.utf16.count))
    }

    public mutating func retryEvaluation() {
        needsEvaluation = true
        previous = nil
    }
}
