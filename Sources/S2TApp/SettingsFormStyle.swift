import AppKit
import SwiftUI

struct SettingsPageBackground: View {
    var body: some View { Rectangle().fill(.background).ignoresSafeArea() }
}

@MainActor final class SettingsScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        contentView.drawsBackground = false
        hasVerticalScroller = true
        automaticallyAdjustsContentInsets = false
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor class SettingsActionButton: NSButton {
    private var updatingTitle = false
    var prominentTitle = false { didSet { updateTitles() } }

    override var title: String { didSet { updateTitles() } }
    override var font: NSFont? { didSet { updateTitles() } }
    override var lineBreakMode: NSLineBreakMode { didSet { updateTitles() } }
    override var isEnabled: Bool { didSet { updateTitles() } }
    override var state: NSControl.StateValue { didSet { updateTitles() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateTitles()
    }
    required init?(coder: NSCoder) { nil }

    private func updateTitles() {
        guard !updatingTitle else { return }
        updatingTitle = true
        defer { updatingTitle = false }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = lineBreakMode
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .paragraphStyle: paragraph
        ]
        if prominentTitle {
            attributes[.foregroundColor] = NSColor.white.withAlphaComponent(isEnabled ? 1 : 0.45)
        }
        let text = NSAttributedString(string: title, attributes: attributes)
        attributedTitle = text
        attributedAlternateTitle = text
    }
}

@MainActor final class SettingsFormButton: SettingsActionButton {
    var primary = true { didSet { updateTint() } }
    private func updateTint() {
        SettingsFormStyle.action(self, primary: primary)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        updateTint()
        font = .systemFont(ofSize: 13, weight: .medium)
        controlSize = .regular
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor enum SettingsFormStyle {
    static func nativeAction(_ button: NSButton) {
        action(button, primary: false)
        button.isBordered = true
        button.font = .systemFont(ofSize: 13)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    static func action(_ button: NSButton, primary: Bool) {
        button.appearance = nil
        button.contentTintColor = nil
        button.bezelColor = nil
        (button as? SettingsActionButton)?.prominentTitle = false
        button.bezelStyle = .rounded
        if #available(macOS 26, *) {
            button.borderShape = .automatic
            button.tintProminence = primary ? .primary : .none
        }
    }

    static func submit(_ field: NSTextField, with button: NSButton) {
        field.target = button
        field.action = #selector(NSButton.performClick(_:))
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
    }

    static func field(_ field: NSTextField) -> NSView {
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.focusRingType = .default
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func popup(_ popup: NSPopUpButton) {
        action(popup, primary: false)
        popup.isBordered = true
        popup.font = .systemFont(ofSize: 13, weight: .medium)
        popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }

    static func menuPicker(_ popup: NSPopUpButton) {
        action(popup, primary: false)
        popup.isBordered = true
        popup.font = .systemFont(ofSize: 13)
        popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }

    static func pageHeading(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}

extension NSPopUpButton {
    /// Appends an item without `addItem(withTitle:)`, which silently removes an earlier item with the same title
    /// and shifts every later index. Hosts such as two "Amazon Bedrock" regions share a title.
    @discardableResult func appendItem(_ title: String, value: Any?, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = value
        item.tag = tag
        menu?.addItem(item)
        return item
    }

    /// Selects by stored value rather than by position in a source array.
    func selectItem(value: String) {
        if let index = itemArray.firstIndex(where: { $0.representedObject as? String == value }) { selectItem(at: index) }
    }
}
