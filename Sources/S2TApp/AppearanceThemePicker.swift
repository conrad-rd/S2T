import AppKit

final class AppearanceThemePicker: SettingsChoiceControl {
    static let themes = ["light", "dark", "system"]
    var onThemeSelection: ((String) -> Void)?

    init(frame: NSRect) {
        super.init(items: ["Light", "Dark", "Auto"].map { .init(title: $0) }, label: "Interface theme")
        self.frame = frame
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.theme")
        selectedSegment = 2
        onSelection = { [weak self] index in self?.onThemeSelection?(Self.themes[index]) }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 180), heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func select(_ value: String) {
        if let index = Self.themes.firstIndex(of: value) { selectedSegment = index }
    }
}
