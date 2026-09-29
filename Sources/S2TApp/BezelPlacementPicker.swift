import AppKit

@MainActor final class BezelPlacementPicker: SettingsChoiceControl {
    init(frame: NSRect) {
        super.init(items: ["Left", "Right"].map { .init(title: $0) }, label: "Bezel placement")
        self.frame = frame
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.bezel.placement")
        selectedSegment = 1
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 140), heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    required init?(coder: NSCoder) { nil }
}
