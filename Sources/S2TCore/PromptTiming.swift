import Foundation

public struct TimedWord: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    public init(text: String, start: Double, end: Double) {
        self.text = text; self.start = start; self.end = end
    }
}

public struct TimedTranscription: Sendable {
    public let text: String
    public let words: [TimedWord]
    public init(text: String, words: [TimedWord] = []) { self.text = text; self.words = words }
}

public enum PromptTiming {
    public struct Reference: Sendable {
        public let phrase: String
        public let seconds: Double?
        public let approximate: Bool
    }

    public static func references(transcript: String, words: [TimedWord]) -> [Reference] {
        let finalWords = transcript.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }
        let spoken = words.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start }
        guard finalWords.count <= 6000, spoken.count <= 6000 else {
            return PromptReferenceDetector.matches(transcript).map { Reference(phrase: $0.phrase, seconds: nil, approximate: true) }
        }
        let source = spoken.map { normalize($0.text) }
        let difference = finalWords.difference(from: source)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var aligned: [Int: Int] = [:]
        var old = 0, new = 0
        while old < source.count && new < finalWords.count {
            if removed.contains(old) { old += 1; continue }
            if inserted.contains(new) { new += 1; continue }
            aligned[new] = old
            old += 1; new += 1
        }
        return PromptReferenceDetector.matches(transcript).map { match in
            let index = match.wordIndex + match.phrase.split(whereSeparator: \.isWhitespace).count - 1
            if let sourceIndex = aligned[index] {
                return Reference(phrase: match.phrase, seconds: spoken[sourceIndex].start, approximate: false)
            }
            let left = aligned.keys.filter { $0 < index }.max()
            let right = aligned.keys.filter { $0 > index }.min()
            if let left, let right, right - left <= 6,
               let a = aligned[left], let b = aligned[right] {
                let start = spoken[a].end, end = spoken[b].start
                if end >= start, end - start <= 3 {
                    let fraction = Double(index - left) / Double(right - left)
                    return Reference(phrase: match.phrase, seconds: start + (end - start) * fraction, approximate: true)
                }
            }
            return Reference(phrase: match.phrase, seconds: nil, approximate: true)
        }
    }

    public static func nearestFrame(to time: Double, times: [Double], tolerance: Double = 0.6) -> Int? {
        guard time.isFinite, !times.isEmpty else { return nil }
        var lower = 0, upper = times.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if times[middle] < time { lower = middle + 1 } else { upper = middle }
        }
        let candidates = [lower - 1, lower].filter { times.indices.contains($0) }
        guard let index = candidates.min(by: { abs(times[$0] - time) < abs(times[$1] - time) }),
              abs(times[index] - time) <= tolerance else { return nil }
        return index
    }

    private static func normalize(_ word: String) -> String {
        String(word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
