import AppKit

@MainActor final class EditableAPIKeyField: NSTextField {
    private(set) var isRevealed = false
    private var windowObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell = NSSecureTextFieldCell(textCell: "")
    }
    required init?(coder: NSCoder) { nil }

    private func reveal() {
        guard isEnabled, isEditable, !isRevealed else { return }
        replaceCell(NSTextFieldCell(textCell: stringValue))
        isRevealed = true
    }

    func mask() {
        guard isRevealed else { return }
        isRevealed = false
        if currentEditor() != nil { window?.makeFirstResponder(nil) }
        replaceCell(NSSecureTextFieldCell(textCell: stringValue))
    }

    private func replaceCell(_ replacement: NSTextFieldCell) {
        guard let previous = cell as? NSTextFieldCell else { return }
        replacement.font = previous.font
        replacement.textColor = previous.textColor
        replacement.backgroundColor = previous.backgroundColor
        replacement.drawsBackground = previous.drawsBackground
        replacement.isBezeled = previous.isBezeled
        replacement.isBordered = previous.isBordered
        replacement.isEditable = previous.isEditable
        replacement.isSelectable = previous.isSelectable
        replacement.isEnabled = previous.isEnabled
        replacement.placeholderString = previous.placeholderString
        replacement.focusRingType = previous.focusRingType
        replacement.lineBreakMode = previous.lineBreakMode
        replacement.isScrollable = previous.isScrollable
        cell = replacement
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        reveal()
        let accepted = super.becomeFirstResponder()
        if !accepted { mask() }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        reveal()
        super.mouseDown(with: event)
        if currentEditor() == nil { mask() }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        mask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        mask()
        if let window {
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mask() }
            }
        }
    }
}
