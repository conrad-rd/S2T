import AppKit

@MainActor final class SettingsGroup: NSView {
    let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.025).cgColor
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func add(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }


}

@MainActor enum SettingsHeading {
    static func make(_ title: String, symbol: String, color: NSColor, large: Bool = false) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: large ? 22 : 13, weight: .semibold)
        let row = NSStackView(views: [AppearanceIconView(symbol: symbol, color: color, size: large ? 32 : 24), label, NSView()])
        row.alignment = .centerY
        row.spacing = 10
        return row
    }
}

final class SettingsDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}
