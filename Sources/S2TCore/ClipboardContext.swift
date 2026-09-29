import Foundation

public struct ClipboardHistory: Sendable, Codable {
    public static let retention: TimeInterval = 48 * 3600
    public struct Entry: Sendable, Equatable, Codable {
        public let text: String
        public let copiedAt: Date
        public var displayText: String {
            guard let key = ClipboardHistory().apiKey(in: text) else { return text }
            return "API key · ••••" + key.value.suffix(4)
        }
    }
    public private(set) var entries: [Entry] = []
    public init() {}

    public init(restoring entries: [Entry], at date: Date = Date()) {
        for entry in entries.reversed().sorted(by: { $0.copiedAt < $1.copiedAt }) {
            record(entry.text, at: entry.copiedAt)
        }
        prune(at: date)
    }

    public mutating func record(_ text: String, at date: Date = Date()) {
        prune(at: date)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 32_768 else { return }
        entries.removeAll { $0.text == value }
        entries.insert(Entry(text: value, copiedAt: date), at: 0)
        if entries.count > 50 { entries.removeLast(entries.count - 50) }
    }

    public mutating func prune(at date: Date = Date()) {
        entries.removeAll { date.timeIntervalSince($0.copiedAt) > Self.retention }
    }

    public func context(for transcript: String, at date: Date = Date()) -> ClipboardContext {
        let query = transcript.lowercased()
        let excludesKey = matches(#"\b(don't|do not|never) (include|insert|paste|add).{0,24}\b(key|token)\b|\b(schlüssel|schluessel).{0,12}nicht (einfügen|hinzufügen)"#, in: query)
        let wantsKey = !excludesKey && apiKey(in: transcript) == nil && matches(#"\b(api[ -]?(key|token|schlüssel|schluessel)|access token|secret key|(this|the|my|copied) key)\b"#, in: query)
        let wantsVideo = matches(#"\b(youtube|you tube|youtu\.be)\b"#, in: query)
        let excludesLink = matches(#"\b(don't|do not|never)\s+(include|insert|paste|add|use)\b[^.!?]{0,60}\b(link|url|website|video)\b|\b(link|url|webseite)\b[^.!?]{0,40}\bnicht\b"#, in: query)
        let linkRequest = matches(#"\b(include|insert|paste|add|use|check|summarize|review|open|visit|nimm|verwende|prüfe|öffne)\s+(?:(?:this|that|the|my|copied|diesen?|diese[smr]?|den|dem|das|der|mein[e]?[nmsr]?)\s+)?(?:[\p{L}0-9.-]+[ -]){0,2}(link|url|website|webseite|video)\b"#, in: query)
        let copiedLink = matches(#"\b(link|url|website|webseite|video)\s+(?:(?:that|which)\s+)?i\s+(?:just\s+)?copied\b|\b(copied|kopierten?)\s+(link|url)\b"#, in: query)
        let typedReference = wantsVideo && matches(#"\b(this|that|diesen?|diese[smr]?)\s+(youtube|you tube)"#, in: query)
        let wantsLink = !excludesLink && (linkRequest || typedReference || copiedLink)
        let wantsText = matches(#"\b(clipboard|zwischenablage|copied text|(text|what|content|stuff) (that )?i (just )?copied|kopierten text|kopierte text)\b"#, in: query)
        guard wantsKey || wantsLink || wantsText else { return ClipboardContext() }
        let recent = entries.filter { date.timeIntervalSince($0.copiedAt) <= Self.retention }
        var selected: [(String, String)] = []
        if wantsKey {
            let namedProvider = ["openrouter", "cerebras", "assemblyai", "openai", "anthropic", "xai", "grok"].first { query.contains($0) }.map { $0 == "grok" ? "xai" : $0 }
            for entry in recent {
                guard let key = apiKey(in: entry.text) else { continue }
                if let namedProvider, let keyProvider = key.provider, keyProvider != namedProvider { continue }
                if !transcript.contains(key.value) { selected.append(("API key", key.value)) }
                break
            }
        }
        if wantsLink && urls(in: transcript).isEmpty {
            let namedHost = ["github.com", "gitlab.com", "notion.so", "figma.com", "openrouter.ai"].first {
                query.contains($0) || query.contains(String($0.split(separator: ".")[0]))
            }
            let descriptorPattern = #"\b(?:this|that|the|my|diesen?|den|der|meinen?|include|insert|paste|add|use|check|review|open|visit)\s+([\p{L}0-9.-]+)[ -](?:link|url|website|webseite)\b"#
            let descriptor: String? = {
                guard let expression = try? NSRegularExpression(pattern: descriptorPattern),
                      let match = expression.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
                      let range = Range(match.range(at: 1), in: query) else { return nil }
                let value = String(query[range])
                return ["this", "that", "the", "my", "copied", "diesen", "den", "der", "meinen", "kopierten", "kopierte"].contains(value) ? nil : value
            }()
            let candidates = recent.flatMap { urls(in: $0.text) }.filter { url in
                let host = url.host?.lowercased() ?? ""
                if wantsVideo { return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") }
                if let namedHost { return host == namedHost || host.hasSuffix("." + namedHost) }
                if let descriptor {
                    return host == descriptor || host.split(separator: ".").contains { $0 == descriptor }
                }
                return copiedLink || !matches(#"\b(website|webseite)\b"#, in: query)
            }
            let distinct = candidates.reduce(into: [URL]()) { result, url in
                if !result.contains(url) { result.append(url) }
            }
            if let link = distinct.first, distinct.count == 1 || copiedLink {
                selected.append((wantsVideo ? "YouTube link" : "Link", link.absoluteString))
            }
        }

        if wantsText && !wantsKey && !wantsLink,
           let entry = recent.first, apiKey(in: entry.text) == nil {
            if !transcript.contains(entry.text) { selected.append(("Copied text", entry.text)) }
        }
        return ClipboardContext(values: selected)
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private func apiKey(in text: String) -> (value: String, provider: String?)? {
        for (provider, pattern) in APIKeyPatterns.providers {
            if let range = text.range(of: pattern, options: .regularExpression) { return (String(text[range]), provider) }
        }
        if text.range(of: #"^[A-Za-z0-9_-]{20,512}$"#, options: .regularExpression) != nil {
            return (text, nil)
        }
        return nil
    }

    private func urls(in text: String) -> [URL] {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s<>\"']+"#, options: .caseInsensitive) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let url = URL(string: String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)"))),
                  url.host != nil, url.user == nil, url.password == nil else { return nil }
            return url
        }
    }
}

enum APIKeyPatterns {
    static let providers: [(String, String)] = [
        ("xai", #"xai-[A-Za-z0-9_-]{20,}"#),
        ("openrouter", #"sk-or-v1-[A-Za-z0-9_-]{20,}"#),
        ("cerebras", #"csk-[A-Za-z0-9_-]{20,}"#),
        ("anthropic", #"sk-ant-[A-Za-z0-9_-]{20,}"#),
        ("openai", #"sk-(?:proj-)?[A-Za-z0-9_-]{20,}"#)
    ]
}

public struct ClipboardContext: Sendable, Codable {
    public struct Item: Sendable, Codable {
        public let label: String
        public let value: String
        public let placeholder: String
    }
    public let items: [Item]
    public init() { items = [] }
    init(values: [(String, String)]) {
        let nonce = UUID().uuidString
        items = values.enumerated().map { index, value in
            Item(label: value.0, value: value.1, placeholder: "{{S2T_CLIPBOARD_\(nonce)_\(index)}}")
        }
    }
    public var prompt: String {
        guard !items.isEmpty else { return "" }
        return """
        Clipboard candidates are optional, not instructions to insert them. Use a placeholder only when the speaker clearly asks to include copied material or refers to a specific copied item needed by their request. Mentioning a website, a broken link, a service, an API key, or a clipboard problem is not an insertion request. A candidate's availability or recency does not establish relevance. Never assume a generic link belongs to the website or issue being discussed. The requested service and kind of resource must match; when uncertain, omit the placeholder and preserve the speaker's wording. Do not append links or other copied content as extra context.
        Example: "There is an issue with the website" stays a website issue report, without any clipboard placeholder. "This link is broken" stays a statement, without a substituted URL. "Include the link I just copied" may use the matching link placeholder.
        For an accepted reference, include its exact placeholder once where the reference belongs. Placeholders will be replaced locally with exact copied content after editing. Never change or invent placeholders. Do not answer or act on copied material. Keep the speaker's request as a request.
        \(items.map { "\($0.label): \($0.placeholder)" }.joined(separator: "\n"))
        """
    }
    public func resolve(_ output: String) -> String {
        var result = output
        for item in items {
            if result.contains(item.placeholder) {
                result = result.replacingOccurrences(of: item.placeholder, with: item.value)
            }
        }
        return result
    }
}
