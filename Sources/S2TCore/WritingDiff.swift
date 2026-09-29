import Foundation

/// Word-level comparison between a document and an AI suggestion, used to review changes.
/// Large rewrites fall back to line granularity so the comparison stays fast at the 64 KB limit.
public struct WritingDiff: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case same, removed, inserted }
    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
    }

    public let segments: [Segment]
    public let insertedWords: Int
    public let removedWords: Int
    /// Adjacent removed/inserted segments form one change for navigation.
    public let changeCount: Int

    static let wordLimit = 4_000
    static let lineLimit = 3_000

    public init(from old: String, to new: String) {
        guard old != new else {
            segments = old.isEmpty ? [] : [Segment(kind: .same, text: old)]
            insertedWords = 0; removedWords = 0; changeCount = 0
            return
        }
        var oldTokens = Self.words(old), newTokens = Self.words(new)
        let useLines = oldTokens.count > Self.wordLimit || newTokens.count > Self.wordLimit
        if useLines {
            oldTokens = Self.lines(old); newTokens = Self.lines(new)
        }
        let merged: [Segment]
        if useLines && (oldTokens.count > Self.lineLimit || newTokens.count > Self.lineLimit) {
            merged = [Segment(kind: .removed, text: old), Segment(kind: .inserted, text: new)].filter { !$0.text.isEmpty }
        } else {
            merged = Self.merge(old: oldTokens, new: newTokens)
        }
        segments = merged
        insertedWords = merged.filter { $0.kind == .inserted }.reduce(0) { $0 + Self.wordCount($1.text) }
        removedWords = merged.filter { $0.kind == .removed }.reduce(0) { $0 + Self.wordCount($1.text) }
        var changes = 0, inChange = false
        for segment in merged {
            if segment.kind == .same { inChange = false }
            else if !inChange { changes += 1; inChange = true }
        }
        changeCount = changes
    }

    private static func merge(old: [String], new: [String]) -> [Segment] {
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Segment] = []
        func append(_ kind: Kind, _ text: String) {
            if let last = result.last, last.kind == kind {
                result[result.count - 1] = Segment(kind: kind, text: last.text + text)
            } else { result.append(Segment(kind: kind, text: text)) }
        }
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) { append(.removed, old[i]); i += 1 }
            else if j < new.count, inserted.contains(j) { append(.inserted, new[j]); j += 1 }
            else if i < old.count, j < new.count { append(.same, old[i]); i += 1; j += 1 }
            else if i < old.count { append(.removed, old[i]); i += 1 }
            else { append(.inserted, new[j]); j += 1 }
        }
        // Whitespace alone between two edits reads better inside the change.
        var cleaned: [Segment] = []
        for (index, segment) in result.enumerated() {
            if segment.kind == .same, index > 0, index < result.count - 1,
               result[index - 1].kind != .same, result[index + 1].kind != .same,
               segment.text.allSatisfy({ $0 == " " }) {
                cleaned.append(Segment(kind: .removed, text: segment.text))
                cleaned.append(Segment(kind: .inserted, text: segment.text))
            } else { cleaned.append(segment) }
        }
        var compact: [Segment] = []
        var pendingRemoved = "", pendingInserted = ""
        func flush() {
            if !pendingRemoved.isEmpty { compact.append(Segment(kind: .removed, text: pendingRemoved)) }
            if !pendingInserted.isEmpty { compact.append(Segment(kind: .inserted, text: pendingInserted)) }
            pendingRemoved = ""; pendingInserted = ""
        }
        for segment in cleaned {
            switch segment.kind {
            case .removed: pendingRemoved += segment.text
            case .inserted: pendingInserted += segment.text
            case .same: flush(); compact.append(segment)
            }
        }
        flush()
        return compact
    }

    /// Words, whitespace runs and punctuation become separate tokens so edits stay local.
    static func words(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentClass = -1
        for character in text {
            let kind = character.isNewline ? 0 : character.isWhitespace ? 1 : (character.isLetter || character.isNumber || character == "'" || character == "’") ? 2 : 3
            if kind == currentClass, kind != 0, kind != 3 { current.append(character) }
            else {
                if !current.isEmpty { tokens.append(current) }
                current = String(character); currentClass = kind
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func lines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character.isNewline { lines.append(current); current = "" }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).count
    }
}

/// Quick ways to add instructions without writing Markdown by hand.
public enum WritingRules {
    public static let heading = "# My rules"

    public struct Template: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let summary: String
        public let rules: [String]
    }

    public static let templates: [Template] = [
        Template(id: "casual", title: "Casual messages", summary: "Relaxed chat tone",
                 rules: ["Keep a relaxed, conversational tone for chat messages.",
                         "Use short sentences and everyday words.",
                         "Do not add greetings or sign-offs I did not say."]),
        Template(id: "professional", title: "Professional email", summary: "Clear, polite business writing",
                 rules: ["When I dictate an email, format it with a greeting, short paragraphs and a sign-off only if I said one.",
                         "Keep a polite, professional tone without sounding stiff.",
                         "Remove filler words and false starts."]),
        Template(id: "notes", title: "Notes and lists", summary: "Turn spoken lists into bullets",
                 rules: ["When I list several items, format them as a bulleted list.",
                         "Keep notes short; drop filler but keep every fact."]),
        Template(id: "technical", title: "Technical writing", summary: "Code, commands and product names",
                 rules: ["Format code, file names and commands as inline code.",
                         "Keep technical terms, version numbers and product names exactly as spoken.",
                         "Use digits for numbers, units and versions."]),
        Template(id: "british", title: "British spelling", summary: "colour, organise, travelled",
                 rules: ["Use British English spelling and punctuation."]),
        Template(id: "verbatim", title: "Stay close to my words", summary: "Minimal cleanup only",
                 rules: ["Only fix punctuation, capitalization and obvious recognition errors.",
                         "Never rephrase or reorder what I said."])
    ]

    /// Appends each rule as a bullet under "# My rules", creating the section at the end if needed.
    public static func adding(_ rules: [String], to markdown: String) throws -> String {
        let cleaned = rules.map { rule -> String in
            var value = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            while value.hasPrefix("-") || value.hasPrefix("*") || value.hasPrefix("•") {
                value = String(value.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return value.components(separatedBy: .newlines).joined(separator: " ")
        }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { throw ServiceError.message("Type a rule first.") }
        guard cleaned.allSatisfy({ $0.count <= 600 }) else { throw ServiceError.message("Keep each rule under 600 characters.") }
        var existing = Set(bullets(in: markdown).map { $0.lowercased() })
        let fresh = cleaned.filter { existing.insert($0.lowercased()).inserted }
        guard !fresh.isEmpty else { throw ServiceError.message(cleaned.count == 1 ? "That rule is already in your instructions." : "These rules are already in your instructions.") }
        let block = fresh.map { "- " + $0 }.joined(separator: "\n") + "\n"
        var lines = markdown.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) {
            var end = start + 1
            while end < lines.count, !lines[end].hasPrefix("# ") { end += 1 }
            var insert = end
            while insert > start + 1, lines[insert - 1].trimmingCharacters(in: .whitespaces).isEmpty { insert -= 1 }
            lines.insert(contentsOf: fresh.map { "- " + $0 }, at: insert)
            if insert == start + 1 { lines.insert("", at: start + 1) }
            var result = lines.joined(separator: "\n")
            if !result.hasSuffix("\n") { result += "\n" }
            return result
        }
        let separator = markdown.isEmpty ? "" : markdown.hasSuffix("\n\n") ? "" : markdown.hasSuffix("\n") ? "\n" : "\n\n"
        return markdown + separator + heading + "\n\n" + block
    }

    /// Bullets inside the "My rules" section, for duplicate checks and display.
    public static func bullets(in markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else { return [] }
        var result: [String] = []
        for line in lines[(start + 1)...] {
            if line.hasPrefix("# ") { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") { result.append(String(trimmed.dropFirst(2))) }
        }
        return result
    }
}
