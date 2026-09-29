import Foundation
import CoreGraphics

public enum InputTargetPreset: String, CaseIterable, Sendable {
    case claude, chatGPT, x, discord, whatsApp, telegram, messages, t3Code, gemini, google, safari, codex, terminal

    public var title: String {
        switch self {
        case .claude: return "Claude AI"
        case .chatGPT: return "ChatGPT"
        case .x: return "X"
        case .discord: return "Discord"
        case .whatsApp: return "WhatsApp"
        case .telegram: return "Telegram"
        case .messages: return "Messages"
        case .t3Code: return "T3 Code"
        case .gemini: return "Gemini"
        case .google: return "Google"
        case .safari: return "Safari"
        case .codex: return "Codex"
        case .terminal: return "Terminal & Claude Code"
        }
    }

    public static func identifiesT3Composer(classes: [String]) -> Bool {
        classes.count <= 256 && classes.contains("@container/composer-surface") && classes.contains("group/composer-surface")
    }

    public static func match(bundleID: String, webURL: URL?, inWebContent: Bool) -> Self? {
        if inWebContent {
            if let url = webURL, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
               let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
                func at(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
                if at("claude.ai") { return .claude }
                if at("chatgpt.com") || at("chat.openai.com") { return .chatGPT }
                if at("x.com") || at("twitter.com") { return .x }
                if at("discord.com") || at("discordapp.com") { return .discord }
                if at("web.whatsapp.com") { return .whatsApp }
                if at("web.telegram.org") { return .telegram }
                if at("gemini.google.com") { return .gemini }
                let googleDomains = ["google.com", "google.de", "google.co.uk", "google.fr", "google.es", "google.it", "google.ca", "google.com.au", "google.co.in", "google.co.jp", "google.nl", "google.ch", "google.at", "google.be"]
                if googleDomains.contains(where: { host == $0 || host == "www." + $0 }) { return .google }
            }
            // Desktop Electron apps may expose local web content without a public URL.
            // A browser's own preset must never take over an unrelated website.
            return native(bundleID: bundleID, allowBrowser: false)
        }
        return native(bundleID: bundleID, allowBrowser: true)
    }

    private static func native(bundleID: String, allowBrowser: Bool) -> Self? {
        switch bundleID.lowercased() {
        case "com.anthropic.claudefordesktop": return .claude
        case "com.openai.chat": return .chatGPT
        case "com.twitter.twitter-mac": return .x
        case "com.hnc.discord", "com.hnc.discordcanary", "com.hnc.discordptb", "app.swiftcord": return .discord
        case "net.whatsapp.whatsapp": return .whatsApp
        case "ru.keepcoder.telegram", "org.telegram.desktop": return .telegram
        case "com.apple.mobilesms", "com.apple.ichat": return .messages
        case "com.t3tools.t3code": return .t3Code
        case "com.openai.codex": return .codex
        case "com.apple.safari", "com.apple.safaritechnologypreview": return allowBrowser ? .safari : nil
        case "com.apple.terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty": return .terminal
        default: return nil
        }
    }

    public var usesComposerBoundary: Bool { self != .safari && self != .terminal && self != .x }

    private var limits: (horizontal: CGFloat, vertical: CGFloat, radius: CGFloat) {
        switch self {
        case .claude: return (8, 5, 20)
        case .chatGPT: return (8, 4, 28)
        case .discord: return (7, 2.5, 8)
        case .whatsApp: return (8, 2.5, 24)
        case .telegram: return (6, 2.5, 18)
        case .messages: return (4, 2, 18)
        case .t3Code: return (6, 5, 22)
        case .codex: return (6, 5, 16)
        case .gemini: return (10, 4, 28)
        case .google: return (8, 2, 28)
        case .safari: return (0, 0, 10)
        case .x: return (0, 0, 12)
        case .terminal: return (0, 0, 4)
        }
    }

    /// Prescribed local container limits, independent of the general composer's ranking and expansion rules.
    public func resolve(editor: Int, nodes: [Int: ComposerNode]) -> InputOutlineTarget? {
        guard let leaf = nodes[editor], leaf.subrole != "AXSecureTextField",
              InputOutlineGeometry.isInput(role: leaf.role, subrole: leaf.subrole, editable: leaf.editable),
              let input = leaf.frame, valid(input) else { return nil }
        if self == .terminal { return nil }
        if self == .safari {
            return ComposerTargeting.resolveTarget(editor: editor, nodes: nodes)
        }
        if self == .x {
            return ComposerAttachments.attachingBars(to: target(input), boundary: editor, nodes: nodes, unit: min(input.height, 28))
        }
        var path: Set<Int> = [editor]
        var ancestors = [ComposerNode]()
        var parent = leaf.parent
        while let id = parent, path.insert(id).inserted, ancestors.count < 24, let node = nodes[id] {
            guard ComposerTargeting.containerRoles.contains(node.role),
                  !node.subrole.contains("Navigation"),
                  !["AXLandmarkMain", "AXDocument", "AXDocumentArticle"].contains(node.subrole) else { break }
            ancestors.append(node)
            parent = node.parent
        }
        let unit = boundaryUnit(input)
        for node in ancestors {
            guard let bounds = node.frame, acceptsBoundary(bounds, editor: input) else { continue }
            guard let controls = controls(in: node.id, editor: editor, path: path, nodes: nodes, bounds: bounds) else { return nil }
            let paddedNativeField = self == .messages && bounds.height <= input.height + unit
            let searchBoundary = node.subrole == "AXLandmarkSearch"
            guard !controls.isEmpty || paddedNativeField || searchBoundary else { continue }
            let capsule = [.chatGPT, .gemini, .google].contains(self)
                && InputOutlineGeometry.isCapsule(field: bounds, editor: input, role: leaf.role, controls: controls)
            let referenceControl: CGFloat = self == .chatGPT ? 30 : self == .gemini ? 29 : self == .t3Code ? 32 : 28
            // Preset radii are in layout units. Buttons retain their size when editor text wraps.
            let icons = controls.filter { $0.width >= $0.height * 0.75 && $0.width <= $0.height * 1.5 }
            let dimensions = (icons.isEmpty ? controls : icons).map { min($0.width, $0.height) }.filter { $0 > 0 }.sorted()
            let controlSize = self == .t3Code ? dimensions.last : dimensions.isEmpty ? nil : dimensions[(dimensions.count - 1) / 2]
            let scale = controlSize.map { $0 / referenceControl } ?? 1
            let body = target(bounds, capsule: capsule, scale: scale)
            return ComposerAttachments.attachingBars(to: body, boundary: node.id, nodes: nodes, unit: referenceControl * scale)
        }
        return nil
    }

    public func acceptsBoundary(_ bounds: CGRect, editor input: CGRect) -> Bool {
        let unit = boundaryUnit(input)
        return valid(bounds) && valid(input) && bounds.insetBy(dx: -1, dy: -1).contains(input)
            && bounds != input && bounds.width - input.width <= unit * limits.horizontal
            && bounds.height - input.height <= unit * limits.vertical
    }

    private func boundaryUnit(_ input: CGRect) -> CGFloat { min(input.height, input.width * 0.12) }

    private func controls(in root: Int, editor: Int, path: Set<Int>, nodes: [Int: ComposerNode], bounds: CGRect) -> [CGRect]? {
        var queue = [root], seen = Set<Int>(), controls = [CGRect]()
        while !queue.isEmpty, seen.count < 192 {
            let id = queue.removeFirst()
            if id == editor { continue }
            guard seen.insert(id).inserted, let node = nodes[id], node.childrenComplete else { return nil }
            if let rect = node.frame, !valid(rect) { continue }
            if !path.contains(id) {
                if InputOutlineGeometry.isInput(role: node.role, subrole: node.subrole, editable: node.editable) {
                    if let rect = node.frame, let input = nodes[editor]?.frame,
                       rect.width <= input.height * 0.1, rect.height <= input.height * 0.1 { continue }
                    return nil
                }
                if ["AXWebArea", "AXWindow", "AXApplication", "AXTable", "AXOutline", "AXList"].contains(node.role) {
                    if let frame = node.frame, !bounds.intersects(frame) { continue }
                    return nil
                }
                if ComposerTargeting.controlRoles.contains(node.role), let rect = node.frame {
                    guard bounds.insetBy(dx: -1, dy: -1).contains(rect) else { return nil }
                    controls.append(rect)
                    continue
                }
                if node.role == "AXStaticText", let rect = node.frame,
                   let input = nodes[editor]?.frame, !input.insetBy(dx: -1, dy: -1).contains(rect) { return nil }
            }
            queue += node.children
        }
        return queue.isEmpty ? controls : nil
    }

    private func target(_ bounds: CGRect, capsule: Bool = false, scale: CGFloat = 1) -> InputOutlineTarget {
        InputOutlineTarget(frame: bounds, cornerRadius: capsule ? bounds.height / 2 : min(min(bounds.width, bounds.height) / 2, limits.radius * scale),
                           cornerStyle: self == .safari || self == .messages ? .continuous : .circular)
    }

    public static func terminalTarget(viewport: CGRect, caret: CGRect) -> InputOutlineTarget? {
        guard valid(viewport), [caret.minX, caret.minY, caret.width, caret.height].allSatisfy(\.isFinite),
              caret.width >= 0, caret.height >= 8, caret.height <= 80,
              caret.minX >= viewport.minX, caret.maxX <= viewport.maxX,
              caret.minY >= viewport.minY, caret.maxY <= viewport.maxY else { return nil }
        let row = CGRect(x: viewport.minX, y: caret.minY - caret.height * 0.25,
                         width: viewport.width, height: caret.height * 1.5).intersection(viewport)
        return InputOutlineTarget(frame: row, cornerRadius: 4, cornerStyle: .circular)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 1 && rect.height > 1
    }
    private func valid(_ rect: CGRect) -> Bool { Self.valid(rect) }
}
