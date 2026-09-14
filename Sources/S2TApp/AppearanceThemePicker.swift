import AppKit

final class AppearanceThemePicker: NSStackView {
    private(set) var buttons: [NSButton] = []
    var onSelection: ((String) -> Void)?
    private var selectedTheme: String?
    static let themes = ["light", "dark", "system"]

    override init(frame: NSRect) {
        super.init(frame: frame)
        spacing = 4
        distribution = .fillEqually
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.theme")
        setAccessibilityLabel("Interface theme")
        for (index, title) in ["Light", "Dark", "Auto"].enumerated() {
            let button = SettingsHoverButton(title: title, target: self, action: #selector(changeTheme(_:)))
            button.tag = index
            button.identifier = NSUserInterfaceItemIdentifier("appearance.theme." + Self.themes[index])
            button.isBordered = false
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyDown
            button.font = .systemFont(ofSize: 10)
            button.setAccessibilityLabel(title == "Auto" ? "Use system appearance" : "Use \(title.lowercased()) appearance")
            addArrangedSubview(button)
            buttons.append(button)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 146),
            heightAnchor.constraint(equalToConstant: 53)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func select(_ value: String) {
        guard selectedTheme != value else { return }
        selectedTheme = value
        for (index, button) in buttons.enumerated() {
            let selected = Self.themes[index] == value
            button.image = AppearanceThemeArtwork.image(theme: Self.themes[index], selected: selected)
            button.font = .systemFont(ofSize: 10, weight: selected ? .semibold : .regular)
            button.setAccessibilityValue(selected ? "Selected" : "Not selected")
        }
    }
    @objc private func changeTheme(_ sender: NSButton) { onSelection?(Self.themes[sender.tag]) }
}

private enum AppearanceThemeArtwork {
    static func image(theme: String, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 44, height: 34), flipped: false) { rect in
            let frame = rect.insetBy(dx: 3, dy: 3)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5).addClip()
            NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.77, alpha: 1).setFill()
            frame.fill()
            if let wallpaper = AppearancePreviewScene.wallpaper { wallpaper.draw(in: frame) }
            let window = NSRect(x: 10, y: -4, width: 42, height: 27)
            (theme == "dark" ? NSColor(calibratedWhite: 0.16, alpha: 1) : .white).setFill()
            NSBezierPath(roundedRect: window, xRadius: 5, yRadius: 5).fill()
            if theme == "system" {
                NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
                NSRect(x: 25, y: 0, width: 20, height: 23).fill()
            }
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: Double(14 + i * 6), y: 15, width: 3.5, height: 3.5)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if selected {
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
                border.lineWidth = 2
                border.stroke()
            }
            return true
        }
    }
}
