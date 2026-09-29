import AppKit

@MainActor final class AppearanceSectionSelection {
    private(set) var section = AppearanceSection.glow
    func select(_ section: AppearanceSection) { self.section = section }
}

@MainActor final class AppearanceSectionBar: NSView {
    let selection = AppearanceSectionSelection()
    let picker: AppearanceIconGroup
    var onSelection: ((AppearanceSection) -> Void)?

    override init(frame: NSRect) {
        let symbols = ["sun.max", "rectangle", "waveform", "paintpalette"]
        picker = AppearanceIconGroup(items: zip(AppearanceSection.allCases, symbols).map { ($0.title, $1) })
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.sections")
        picker.setAccessibilityLabel("Appearance controls")
        addSubview(picker)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 195),
            heightAnchor.constraint(equalToConstant: 42)
        ])
        picker.onSelection = { [weak self] index in
            guard let self, let section = AppearanceSection(rawValue: index) else { return }
            self.select(section)
            self.onSelection?(section)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        picker.frame = bounds
    }
    func select(_ section: AppearanceSection) {
        selection.select(section)
        picker.select(section.rawValue)
    }
}
