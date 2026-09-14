import AppKit

@MainActor final class SettingsGlassScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .aqua)
        drawsBackground = true
        backgroundColor = .white
        contentView.drawsBackground = true
        contentView.backgroundColor = .white
        hasVerticalScroller = true
        automaticallyAdjustsContentInsets = false
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor final class SettingsGlassButton: NSButton {
    var primary = false { didSet { updateTitle() } }
    private var updating = false
    override var title: String { didSet { updateTitle() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        if #available(macOS 26, *) { bezelStyle = .glass; borderShape = .capsule }
        else { bezelStyle = .rounded }
        font = .systemFont(ofSize: 12, weight: .medium)
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }
    private func updateTitle() {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        if #available(macOS 26, *) { tintProminence = primary ? .primary : .none }
        bezelColor = primary ? .systemBlue : nil
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: primary ? NSColor.white : NSColor.labelColor
        ])
    }
}

@MainActor enum SettingsFormStyle {
    static func field(_ field: NSTextField) -> NSView {
        let well = NSView()
        well.wantsLayer = true
        well.layer?.cornerRadius = 11
        well.layer?.cornerCurve = .continuous
        well.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.045).cgColor
        well.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        well.layer?.borderWidth = 1
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 13)
        field.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(field)
        NSLayoutConstraint.activate([
            well.heightAnchor.constraint(equalToConstant: 34),
            field.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 22)
        ])
        return well
    }

    static func popup(_ popup: NSPopUpButton) {
        if #available(macOS 26, *) { popup.bezelStyle = .glass; popup.borderShape = .capsule }
        else { popup.bezelStyle = .rounded }
        popup.font = .systemFont(ofSize: 13, weight: .medium)
        popup.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }

    static func pageHeading(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
}
