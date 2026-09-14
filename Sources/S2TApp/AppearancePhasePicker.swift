import AppKit

final class SettingsHoverButton: NSButton {
    private var hoverArea: NSTrackingArea?
    private(set) var hovered = false
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); setHovered(false) }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = false
    }

    func setHovered(_ value: Bool) {
        hovered = value
        wantsLayer = true
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = false
        layer?.cornerCurve = .circular
        let color = NSColor.labelColor.withAlphaComponent(value ? 0.09 : 0).cgColor
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            animation.toValue = color
            animation.duration = 0.16
            layer.add(animation, forKey: "hover")
        }
        layer?.backgroundColor = color
    }
}

final class AppearancePhasePicker: SettingsCapsuleGroup {
    private(set) var buttons: [SettingsHoverButton] = []
    var onSelection: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        let stack = NSStackView()
        stack.spacing = 6
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        identifier = NSUserInterfaceItemIdentifier("appearance.previewPhase")
        setAccessibilityLabel("Preview state")
        for (index, symbol) in ["pause", "waveform", "ellipsis.circle"].enumerated() {
            let title = ["Stiff", "Speaking", "Processing"][index]
            let button = SettingsHoverButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: #selector(choose(_:)))
            button.title = ""
            button.imagePosition = .imageOnly
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            if #available(macOS 26, *) { button.borderShape = .capsule }
            button.setButtonType(.pushOnPushOff)
            button.imageScaling = .scaleProportionallyDown
            button.symbolConfiguration = .init(pointSize: 15, weight: .medium)
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.identifier = NSUserInterfaceItemIdentifier("appearance.phase.\(index)")
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            buttons.append(button)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 132), heightAnchor.constraint(equalToConstant: 48),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6)
        ])
    }
    required init?(coder: NSCoder) { nil }
    func select(_ phase: Int, bezel: Bool) {
        for button in buttons {
            button.state = button.tag == phase ? .on : .off
            button.isBordered = button.tag == phase
            button.contentTintColor = button.tag == phase ? .controlAccentColor : .secondaryLabelColor
        }
        let title = bezel ? "Done" : "Stiff"
        buttons[0].image = NSImage(systemSymbolName: bezel ? "checkmark" : "pause", accessibilityDescription: title)
        buttons[0].toolTip = title
        buttons[0].setAccessibilityLabel(title)
    }
    @objc private func choose(_ sender: NSButton) { onSelection?(sender.tag) }
}
