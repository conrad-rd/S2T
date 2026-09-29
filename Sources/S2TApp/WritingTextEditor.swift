import AppKit
import SwiftUI

enum MarkdownFormat: Equatable {
    case heading, bold, italic, bulletList, numberedList, inlineCode, link
}

@MainActor final class WritingTextDocument: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView = WritingTextView(frame: .zero)
    var onChange: ((String) -> Void)?
    private var replacing = false

    override init() {
        super.init()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .windowBackgroundColor
        textView.drawsBackground = false
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: 16)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.defaultTabInterval = 31.2
        paragraph.tabStops = []
        textView.defaultParagraphStyle = paragraph
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        textView.onAppearanceChange = { [weak self] in self?.applyMarkdownStyles() }
        scrollView.documentView = textView
    }

    func update(text: String, editable: Bool, label: String, identifier: String) {
        textView.isEditable = editable
        textView.setAccessibilityLabel(label)
        textView.setAccessibilityIdentifier(identifier)
        guard textView.string != text else { return }
        replacing = true
        let selected = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
        textView.undoManager?.removeAllActions()
        replacing = false
        applyMarkdownStyles()
    }

    func find() {
        scrollView.window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }

    func format(_ format: MarkdownFormat) {
        guard textView.isEditable else { return }
        scrollView.window?.makeFirstResponder(textView)
        textView.applyMarkdown(format)
    }

    func textDidChange(_ notification: Notification) {
        guard !replacing else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyMarkdownStyles), object: nil)
        perform(#selector(applyMarkdownStyles), with: nil, afterDelay: 0.015)
        onChange?(textView.string)
    }

    @objc func applyMarkdownStyles() {
        MarkdownTextStyler.apply(to: textView)
    }
}

@MainActor final class WritingTextView: NSTextView {
    private let documentUndo = UndoManager()
    var onAppearanceChange: (() -> Void)?
    override var undoManager: UndoManager? { documentUndo }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    @objc func undo(_ sender: Any?) {
        guard isEditable, documentUndo.canUndo else { return }
        breakUndoCoalescing()
        documentUndo.undo()
        didChangeText()
    }

    @objc func redo(_ sender: Any?) {
        guard isEditable, documentUndo.canRedo else { return }
        documentUndo.redo()
        didChangeText()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return isEditable && documentUndo.canUndo }
        if item.action == #selector(redo(_:)) { return isEditable && documentUndo.canRedo }
        return super.validateUserInterfaceItem(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command, let key = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "f" {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performTextFinderAction(item)
            return true
        }
        if key == "b" { applyMarkdown(.bold); return true }
        if key == "i" { applyMarkdown(.italic); return true }
        if key == "k" { applyMarkdown(.link); return true }
        return super.performKeyEquivalent(with: event)
    }

    func applyMarkdown(_ format: MarkdownFormat) {
        let source = string as NSString
        let selection = selectedRange()
        switch format {
        case .heading:
            let line = source.lineRange(for: selection)
            let content = source.substring(with: line)
            let marker = try! NSRegularExpression(pattern: #"^#{1,6}[\t ]+"#)
            let body = marker.stringByReplacingMatches(in: content, range: NSRange(location: 0, length: (content as NSString).length), withTemplate: "")
            insertText("# " + body, replacementRange: line)
        case .bulletList, .numberedList:
            let lines = source.lineRange(for: selection)
            let content = source.substring(with: lines)
            let lineStart = try! NSRegularExpression(pattern: #"(?m)^(?=\S)"#)
            let prefix = format == .bulletList ? "- " : "1. "
            let replacement = lineStart.stringByReplacingMatches(in: content, range: NSRange(location: 0, length: (content as NSString).length), withTemplate: prefix)
            insertText(replacement, replacementRange: lines)
            setSelectedRange(NSRange(location: lines.location, length: (replacement as NSString).length))
        case .bold:
            wrap(selection, prefix: "**", suffix: "**", placeholder: "bold text")
        case .italic:
            wrap(selection, prefix: "*", suffix: "*", placeholder: "italic text")
        case .inlineCode:
            wrap(selection, prefix: "`", suffix: "`", placeholder: "code")
        case .link:
            let label = selection.length > 0 ? source.substring(with: selection) : "link"
            let replacement = "[\(label)](url)"
            insertText(replacement, replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + (label as NSString).length + 3, length: 3))
        }
    }

    private func wrap(_ selection: NSRange, prefix: String, suffix: String, placeholder: String) {
        let source = string as NSString
        let body = selection.length > 0 ? source.substring(with: selection) : placeholder
        insertText(prefix + body + suffix, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + (prefix as NSString).length, length: (body as NSString).length))
    }
}

@MainActor enum MarkdownTextStyler {
    private static let heading = try! NSRegularExpression(pattern: #"(?m)^(#{1,6})[\t ]+(.+)$"#)
    private static let listMarker = try! NSRegularExpression(pattern: #"(?m)^[\t ]*(?:[-+*]|\d+[.)])(?=[\t ])"#)
    private static let quoteMarker = try! NSRegularExpression(pattern: #"(?m)^[\t ]*>+[\t ]?"#)
    private static let boldAsterisk = try! NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*"#)
    private static let boldUnderscore = try! NSRegularExpression(pattern: #"__([^_\n]+)__"#)
    private static let italicAsterisk = try! NSRegularExpression(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#)
    private static let italicUnderscore = try! NSRegularExpression(pattern: #"(?<!_)_([^_\n]+)_(?!_)"#)
    private static let strike = try! NSRegularExpression(pattern: #"~~([^~\n]+)~~"#)
    private static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#)
    private static let inlineCode = try! NSRegularExpression(pattern: #"(?<!`)`([^`\n]+)`(?!`)"#)
    private static let fencedCode = try! NSRegularExpression(pattern: #"(?ms)^```[^\n]*(?:\n|$).*?(?:^```[\t ]*$|\z)"#)
    private static let styledKeys: [NSAttributedString.Key] = [.font, .foregroundColor, .backgroundColor, .strikethroughStyle, .underlineStyle]

    static func apply(to textView: NSTextView) {
        guard let layout = textView.layoutManager else { return }
        let source = textView.string as NSString
        let whole = NSRange(location: 0, length: source.length)
        for key in styledKeys { layout.removeTemporaryAttribute(key, forCharacterRange: whole) }
        guard whole.length > 0, whole.length <= 65_536 else { return }
        let base = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .semibold)
        let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)

        heading.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let match else { return }
            let level = min(6, match.range(at: 1).length)
            let sizes: [CGFloat] = [20, 18, 16, 15, 14, 13]
            layout.addTemporaryAttributes([.font: NSFont.systemFont(ofSize: sizes[level - 1], weight: .semibold)], forCharacterRange: match.range(at: 2))
            layout.addTemporaryAttributes([.foregroundColor: NSColor.tertiaryLabelColor], forCharacterRange: match.range(at: 1))
        }
        for regex in [italicAsterisk, italicUnderscore] {
            regex.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
                guard let range = match?.range(at: 1), range.location != NSNotFound else { return }
                layout.addTemporaryAttributes([.font: italic], forCharacterRange: range)
            }
        }
        for regex in [boldAsterisk, boldUnderscore] {
            regex.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
                guard let range = match?.range(at: 1), range.location != NSNotFound else { return }
                layout.addTemporaryAttributes([.font: bold], forCharacterRange: range)
            }
        }
        strike.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let range = match?.range(at: 1), range.location != NSNotFound else { return }
            layout.addTemporaryAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue], forCharacterRange: range)
        }
        listMarker.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let range = match?.range else { return }
            layout.addTemporaryAttributes([.foregroundColor: NSColor.controlAccentColor], forCharacterRange: range)
        }
        quoteMarker.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let range = match?.range else { return }
            layout.addTemporaryAttributes([.foregroundColor: NSColor.secondaryLabelColor], forCharacterRange: range)
        }
        link.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let match else { return }
            layout.addTemporaryAttributes([.foregroundColor: NSColor.linkColor], forCharacterRange: match.range(at: 1))
            layout.addTemporaryAttributes([.foregroundColor: NSColor.secondaryLabelColor], forCharacterRange: match.range(at: 2))
        }
        inlineCode.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let range = match?.range(at: 1), range.location != NSNotFound else { return }
            layout.addTemporaryAttributes([
                .foregroundColor: NSColor.controlAccentColor,
                .backgroundColor: NSColor.separatorColor.withAlphaComponent(0.16)
            ], forCharacterRange: range)
        }
        fencedCode.enumerateMatches(in: textView.string, range: whole) { match, _, _ in
            guard let range = match?.range else { return }
            layout.addTemporaryAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
                .backgroundColor: NSColor.separatorColor.withAlphaComponent(0.12)
            ], forCharacterRange: range)
        }
    }
}

struct WritingTextEditor: NSViewRepresentable {
    let document: WritingTextDocument
    @Binding var text: String
    var editable = true
    var label: String
    var identifier = "writing.editor"

    final class Coordinator {
        weak var document: WritingTextDocument?
        init(document: WritingTextDocument) { self.document = document }
    }
    func makeCoordinator() -> Coordinator { Coordinator(document: document) }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 400)
    }
    func makeNSView(context: Context) -> NSScrollView { document.scrollView }
    func updateNSView(_ view: NSScrollView, context: Context) {
        document.onChange = { text = $0 }
        document.update(text: text, editable: editable, label: label, identifier: identifier)
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.document?.onChange = nil
    }
}

@MainActor final class MarkdownPreviewDocument {
    let scrollView = NSScrollView()
    let textView = MarkdownPreviewTextView(frame: .zero)
    private var renderedSource: String?
    private(set) var renderCount = 0

    init() {
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .windowBackgroundColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        scrollView.documentView = textView
    }

    func update(markdown: String, label: String, identifier: String) {
        textView.setAccessibilityLabel(label)
        textView.setAccessibilityIdentifier(identifier)
        guard renderedSource != markdown else { return }
        renderedSource = markdown
        renderCount += 1
        let rendered = MarkdownPreviewRenderer.render(markdown)
        guard textView.textStorage?.isEqual(to: rendered) != true else { return }
        textView.textStorage?.setAttributedString(rendered)
    }
}

@MainActor final class MarkdownPreviewTextView: NSTextView { }

@MainActor enum MarkdownPreviewRenderer {
    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})[\t ]+(.+)$"#)
    private static let unordered = try! NSRegularExpression(pattern: #"^([\t ]*)[-+*][\t ]+(.+)$"#)
    private static let ordered = try! NSRegularExpression(pattern: #"^([\t ]*)(\d+)[.)][\t ]+(.+)$"#)
    private static let quote = try! NSRegularExpression(pattern: #"^[\t ]*>[\t ]?(.*)$"#)

    static func render(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var fencedCode = false
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fencedCode.toggle()
                continue
            }
            if fencedCode {
                append(line.isEmpty ? " " : line, to: output, style: .codeBlock)
            } else {
                appendLine(line, to: output)
            }
            if index < lines.count - 1 { output.append(NSAttributedString(string: "\n")) }
        }
        return output
    }

    private enum LineStyle {
        case body, heading(Int), bullet(Int), numbered(Int, String), quote, codeBlock
        var isCode: Bool {
            if case .codeBlock = self { return true }
            return false
        }
    }

    private static func appendLine(_ line: String, to output: NSMutableAttributedString) {
        let value = line as NSString
        let range = NSRange(location: 0, length: value.length)
        if let match = heading.firstMatch(in: line, range: range) {
            append(value.substring(with: match.range(at: 2)), to: output, style: .heading(match.range(at: 1).length))
        } else if let match = unordered.firstMatch(in: line, range: range) {
            append(value.substring(with: match.range(at: 2)), to: output,
                style: .bullet(indentation(value.substring(with: match.range(at: 1)))))
        } else if let match = ordered.firstMatch(in: line, range: range) {
            append(value.substring(with: match.range(at: 3)), to: output,
                style: .numbered(indentation(value.substring(with: match.range(at: 1))), value.substring(with: match.range(at: 2))))
        } else if let match = quote.firstMatch(in: line, range: range) {
            append(value.substring(with: match.range(at: 1)), to: output, style: .quote)
        } else {
            append(line, to: output, style: .body)
        }
    }

    private static func indentation(_ whitespace: String) -> Int {
        var spaces = 0
        for character in whitespace { spaces += character == "\t" ? 4 : 1 }
        return min(4, spaces / 4)
    }

    private static func append(_ source: String, to output: NSMutableAttributedString, style: LineStyle) {
        let baseSize: CGFloat
        let weight: NSFont.Weight
        var prefix = ""
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 7
        var foreground = NSColor.textColor
        var background: NSColor?

        switch style {
        case .body:
            baseSize = 14; weight = .regular
        case .heading(let level):
            baseSize = [24, 20, 17, 15, 14, 14][min(5, max(0, level - 1))]
            weight = level <= 2 ? .bold : .semibold
            paragraph.paragraphSpacingBefore = level == 1 ? 10 : 7
            paragraph.paragraphSpacing = 9
        case .bullet(let level):
            baseSize = 14; weight = .regular; prefix = "•\t"
            paragraph.headIndent = CGFloat(level) * 18 + 22
            paragraph.firstLineHeadIndent = CGFloat(level) * 18
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
        case .numbered(let level, let number):
            baseSize = 14; weight = .regular; prefix = number + ".\t"
            paragraph.headIndent = CGFloat(level) * 18 + 28
            paragraph.firstLineHeadIndent = CGFloat(level) * 18
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
        case .quote:
            baseSize = 14; weight = .regular; prefix = "│\t"; foreground = .secondaryLabelColor
            paragraph.headIndent = 22; paragraph.firstLineHeadIndent = 0
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 22)]
        case .codeBlock:
            baseSize = 13; weight = .regular; background = NSColor.separatorColor.withAlphaComponent(0.12)
            paragraph.headIndent = 12; paragraph.firstLineHeadIndent = 12; paragraph.paragraphSpacing = 0
        }

        let baseFont = style.isCode ? NSFont.monospacedSystemFont(ofSize: baseSize, weight: weight) : NSFont.systemFont(ofSize: baseSize, weight: weight)
        let rendered = NSMutableAttributedString(string: prefix, attributes: [.font: baseFont, .foregroundColor: foreground, .paragraphStyle: paragraph])
        let inline = inlineMarkdown(source, baseFont: baseFont, foreground: foreground, paragraph: paragraph)
        rendered.append(inline)
        if let background { rendered.addAttribute(.backgroundColor, value: background, range: NSRange(location: 0, length: rendered.length)) }
        output.append(rendered)
    }

    private static func inlineMarkdown(_ source: String, baseFont: NSFont, foreground: NSColor,
                                       paragraph: NSParagraphStyle) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: source, attributes: [.font: baseFont, .foregroundColor: foreground, .paragraphStyle: paragraph])
        }
        let result = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            let fragment = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent
            var font = baseFont
            if intent?.contains(.code) == true { font = .monospacedSystemFont(ofSize: max(12, baseFont.pointSize - 0.5), weight: .regular) }
            else {
                var traits: NSFontTraitMask = []
                if intent?.contains(.stronglyEmphasized) == true { traits.insert(.boldFontMask) }
                if intent?.contains(.emphasized) == true { traits.insert(.italicFontMask) }
                if !traits.isEmpty { font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits) }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
            if intent?.contains(.code) == true { attributes[.backgroundColor] = NSColor.separatorColor.withAlphaComponent(0.16) }
            if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: fragment, attributes: attributes))
        }
        return result
    }
}

struct WritingMarkdownPreview: NSViewRepresentable {
    let document: MarkdownPreviewDocument
    let markdown: String
    let label: String
    var identifier = "writing.preview"

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 600, height: proposal.height ?? 400)
    }
    func makeNSView(context: Context) -> NSScrollView { document.scrollView }
    func updateNSView(_ view: NSScrollView, context: Context) {
        document.update(markdown: markdown, label: label, identifier: identifier)
    }
}
