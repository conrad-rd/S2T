import AppKit

@MainActor final class AppearanceSectionBar: SettingsCapsuleGroup {
    private(set) var buttons: [NSButton] = []
    var onSelection: ((AppearanceSection) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.sections")
        setAccessibilityLabel("Appearance controls")

        let content = NSView()
        let stack = NSStackView()
        stack.spacing = 2
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for section in AppearanceSection.allCases {
            let button = SettingsHoverButton(title: section.title, target: self, action: #selector(choose(_:)))
            button.cell = AppearanceTabCell(textCell: section.title)
            button.target = self
            button.action = #selector(choose(_:))
            let symbol = ["sun.max", "rectangle", "waveform"][section.rawValue]
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: section.title)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            if #available(macOS 26, *) { button.borderShape = .capsule }
            button.tag = section.rawValue
            button.identifier = NSUserInterfaceItemIdentifier("appearance.section." + section.title.lowercased())
            button.setAccessibilityLabel(section.title + " settings")
            button.toolTip = section.title + " settings"
            stack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            buttons.append(button)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 286),
            heightAnchor.constraint(equalToConstant: 48),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6)
        ])
        select(.glow)
    }
    required init?(coder: NSCoder) { nil }

    func select(_ section: AppearanceSection) {
        for button in buttons {
            let selected = button.tag == section.rawValue
            button.state = selected ? .on : .off
            button.isBordered = selected
            button.contentTintColor = selected ? .controlAccentColor : nil
            button.setAccessibilityValue(selected ? "Selected" : "Not selected")
        }
    }

    @objc private func choose(_ sender: NSButton) {
        guard let section = AppearanceSection(rawValue: sender.tag) else { return }
        select(section)
        onSelection?(section)
    }
}

private final class AppearanceTabCell: NSButtonCell {
    private func contentStart(_ bounds: NSRect) -> CGFloat {
        bounds.midX - (super.imageRect(forBounds: bounds).width + 6 + attributedTitle.size().width) / 2
    }
    override func imageRect(forBounds rect: NSRect) -> NSRect {
        var image = super.imageRect(forBounds: rect)
        image.origin.x = contentStart(rect)
        return image
    }
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var title = super.titleRect(forBounds: rect)
        title.origin.x = contentStart(rect) + super.imageRect(forBounds: rect).width + 6
        title.size = attributedTitle.size()
        title.origin.y = rect.midY - title.height / 2
        return title
    }
}
