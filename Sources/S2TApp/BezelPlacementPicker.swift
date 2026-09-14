import AppKit

@MainActor final class BezelPlacementPicker: NSControl {
    private(set) var buttons: [NSButton] = []
    var selectedSegment = 1 { didSet { refresh() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.bezel.placement")
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        layer?.borderWidth = 1
        let stack = NSStackView()
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (index, title) in ["Left", "Right"].enumerated() {
            let button = SettingsHoverButton(title: title, target: self, action: #selector(choose(_:)))
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            button.setAccessibilityLabel(title + " screen edge")
            if #available(macOS 26, *) {
                button.bezelStyle = .glass
                button.borderShape = .capsule
            } else { button.bezelStyle = .accessoryBarAction }
            button.widthAnchor.constraint(equalToConstant: 64).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 140), heightAnchor.constraint(equalToConstant: 40),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    private func refresh() {
        for button in buttons {
            let selected = button.tag == selectedSegment
            button.state = selected ? .on : .off
            button.bezelColor = selected ? .systemBlue : nil
            if #available(macOS 26, *) { button.tintProminence = selected ? .primary : .none }
            button.attributedTitle = NSAttributedString(string: button.tag == 0 ? "Left" : "Right", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: selected ? NSColor.white : NSColor.labelColor
            ])
            button.setAccessibilityValue(selected ? "Selected" : "Not selected")
        }
    }
    @objc private func choose(_ sender: NSButton) {
        selectedSegment = sender.tag
        sendAction(action, to: target)
    }
}
