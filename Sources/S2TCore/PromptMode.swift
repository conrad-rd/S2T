import Foundation

public struct PromptReferenceDetector {
    public struct Match { public let phrase: String; public let wordIndex: Int }
    private var firedTimes: [Double] = []
    private var priorRequestTimes: [Double] = []
    private var requestID = -1
    private var emittedCount = 0
    public init() {}
    private static let expression = try! NSRegularExpression(pattern: #"\b(?:take a look at (?:this|that)|look (?:at (?:this|that)|over here|here)|check (?:this|that) out|see (?:this|that)|schau (?:mal )?(?:hier|da)|schau dir (?:das|dies) an|sieh (?:dir )?(?:das|hier)(?: an)?|like there|over there|here|hier)\b"#)

    public static func matches(_ text: String) -> [Match] {
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'") as NSString
        return expression.matches(in: lower as String, range: NSRange(location: 0, length: lower.length)).compactMap { match in
            let prefix = lower.substring(to: match.range.location)
            let words = prefix.split(whereSeparator: { $0.isWhitespace })
            let tail = words.suffix(3).joined(separator: " ")
            guard !["don't", "do not", "not", "never", "nicht"].contains(where: { tail.hasSuffix($0) }) else { return nil }
            return Match(phrase: lower.substring(with: match.range), wordIndex: words.count)
        }
    }

    public mutating func consume(text: String, wordTimes: [Double], requestID: Int = 0) -> [(phrase: String, seconds: Double)] {
        if self.requestID != requestID {
            self.requestID = requestID
            emittedCount = 0
            priorRequestTimes = firedTimes
        }
        var events: [(String, Double)] = []
        for (index, match) in Self.matches(text).enumerated() {
            guard index >= emittedCount, wordTimes.indices.contains(match.wordIndex) else { continue }
            emittedCount = index + 1
            let time = wordTimes[match.wordIndex]
            guard !priorRequestTimes.contains(where: { abs($0 - time) < 0.8 }) else { continue }
            firedTimes.append(time)
            events.append((match.phrase, time))
        }
        return events
    }
}

public enum PromptCaptureGeometry {
    public static func region(pointer: CGPoint, display: CGRect) -> CGRect {
        let width = min(800, display.width), height = min(600, display.height)
        return CGRect(x: max(display.minX, min(display.maxX - width, pointer.x - width / 2)),
                      y: max(display.minY, min(display.maxY - height, pointer.y - height / 2)), width: width, height: height)
    }
}

public struct PromptImageDescription: Decodable, Sendable {
    public let description: String
}

public struct PromptImageInput: Sendable {
    public let number: Int
    public let png: Data
    public let pointer: CGPoint
    public let seconds: Double
    public let phrase: String
    public init(number: Int, png: Data, pointer: CGPoint, seconds: Double, phrase: String) {
        self.number = number; self.png = png; self.pointer = pointer; self.seconds = seconds; self.phrase = phrase
    }
}

public enum PromptReferenceText {
    public struct Reference {
        public let number: Int
        public let seconds: Double
        public let description: String
        public let imageName: String?
        public init(number: Int, seconds: Double, description: String, imageName: String?) {
            self.number = number; self.seconds = seconds; self.description = description; self.imageName = imageName
        }
    }
    public static func append(to text: String, session: String, references: [Reference]) -> String {
        guard !references.isEmpty else { return text }
        return text + "\n\n[Visual references · Prompt set \(session)]\n" + references.map {
            let image = $0.imageName.map { " Image: \($0)" } ?? ""
            return "Reference \($0.number), at \(String(format: "%.1f", $0.seconds))s: \($0.description)\(image)"
        }.joined(separator: "\n")
    }
}
