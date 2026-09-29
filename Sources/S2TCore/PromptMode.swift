import Foundation

public struct PromptReferenceDetector {
    public struct Match { public let phrase: String; public let wordIndex: Int; public let range: NSRange }
    private var firedTimes: [Double] = []
    private var priorRequestTimes: [Double] = []
    private var requestID = -1
    private var emittedCount = 0
    public init() {}
    private static let expression = try! NSRegularExpression(pattern: #"\b(?:take a look at (?:this|that)|look (?:at (?:this|that)|over here|here)|check (?:this|that) out|see (?:this|that)|schau (?:mal )?(?:hier|da)|schau dir (?:das|dies) an|sieh (?:dir )?(?:das|hier)(?: an)?|like there|over there|here|hier)\b"#, options: .caseInsensitive)

    public static func matches(_ text: String) -> [Match] {
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let prefix = source.substring(to: match.range.location).lowercased().replacingOccurrences(of: "’", with: "'")
            let words = prefix.split(whereSeparator: { $0.isWhitespace })
            let tail = words.suffix(3).joined(separator: " ")
            guard !["don't", "do not", "not", "never", "nicht"].contains(where: { tail.hasSuffix($0) }) else { return nil }
            return Match(phrase: source.substring(with: match.range).lowercased(), wordIndex: words.count, range: match.range)
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



public struct PromptReferenceText {
    public static let editingInstruction = "Keep every __S2T_SCREENSHOT_...__ marker exactly once, unchanged and unbroken, beside the same spoken reference in the edited text. Keep their order and position within the surrounding thought, including when formatting notes or an email. Never collect them into a list or move them to the end. They will become screenshot mentions before the text is pasted."

    public struct Reference {
        public let number: Int
        public let seconds: Double
        public let description: String
        public let imageName: String?
        public let cueIndex: Int?
        public init(number: Int, seconds: Double, description: String, imageName: String?, cueIndex: Int? = nil) {
            self.number = number; self.seconds = seconds; self.description = description; self.imageName = imageName
            self.cueIndex = cueIndex
        }
    }

    public let text: String
    private let markers: [String]
    private let screenshotOnly: Bool

    public init(transcript: String, session: String) {
        let matches = Array(PromptReferenceDetector.matches(transcript).prefix(64))
        markers = matches.indices.map { "__S2T_SCREENSHOT_\(session)_\($0)__" }
        screenshotOnly = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let annotated = NSMutableString(string: transcript)
        for (match, marker) in zip(matches, markers).reversed() {
            annotated.insert(" " + marker, at: NSMaxRange(match.range))
        }
        text = annotated as String
    }

    public func resolve(_ output: String, references: [Reference]) -> String {
        func label(_ reference: Reference) -> String { "[attached screenshot: [\(reference.number)]]" }
        if screenshotOnly { return references.map(label).joined(separator: "\n") }
        var result = output
        for (index, marker) in markers.enumerated() {
            if let reference = references.first(where: { $0.cueIndex == index }) {
                result = result.replacingOccurrences(of: marker, with: label(reference))
            } else {
                result = result.replacingOccurrences(of: " " + marker, with: "").replacingOccurrences(of: marker, with: "")
            }
        }
        return result
    }

    public static func removingMarkers(from text: String) -> String {
        text.replacingOccurrences(of: #" ?__S2T_SCREENSHOT_[a-z0-9]+_[0-9]+__"#, with: "", options: .regularExpression)
    }
}
