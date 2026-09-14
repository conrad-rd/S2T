import AppKit
import S2TCore

@MainActor final class ClipboardHistoryView: NSView {
    let textView = NSTextView()
    private var displayedEntries: [ClipboardHistory.Entry]?
    private var wasEnabled: Bool?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
        identifier = NSUserInterfaceItemIdentifier("clipboard.history.contents")
        let scroll = NSScrollView(frame: bounds.insetBy(dx: 8, dy: 6))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        textView.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.setAccessibilityLabel("Remembered clipboard items")
        scroll.documentView = textView
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [ClipboardHistory.Entry], enabled: Bool) {
        guard displayedEntries != entries || wasEnabled != enabled else { return }
        displayedEntries = entries
        wasEnabled = enabled
        if !enabled {
            textView.string = "Clipboard history is off. New copies are not saved or used in dictation. Enable it above to resume, or clear remembered items below."
        } else if entries.isEmpty {
            textView.string = "No remembered items yet. Copy text or a link in another app to add it here. S2T's own copies are excluded."
        } else {
            textView.string = entries.map {
                $0.copiedAt.formatted(date: .abbreviated, time: .shortened) + "\n" + $0.displayText
            }.joined(separator: "\n\n────────────\n\n")
        }
        textView.scrollToBeginningOfDocument(nil)
    }
}
