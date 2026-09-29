import AppKit

/// A system group box; AppKit supplies the background and separator appearance.
@MainActor final class SettingsGroup: NSBox {
    let stack = NSStackView()

    init(grouped: Bool = false, verticalInset: CGFloat = 14, horizontalInset: CGFloat = 14) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titlePosition = .noTitle
        boxType = grouped ? .primary : .custom
        if !grouped { isTransparent = true }
        contentViewMargins = NSSize(width: grouped ? 12 : 0, height: grouped ? 12 : 6)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        let margin: CGFloat = grouped ? horizontalInset : 0
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: grouped ? verticalInset : 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: grouped ? -verticalInset : -6)
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
