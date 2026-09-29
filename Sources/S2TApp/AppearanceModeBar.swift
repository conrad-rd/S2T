import AppKit
import S2TCore

@MainActor final class AppearanceModeBar: NSView {
    static let modes: [GlowAppearance] = GlowAppearance.selectableCases
    let picker: AppearanceIconGroup
    var onSelection: ((GlowAppearance) -> Void)?

    init() {
        let symbols = ["rectangle.bottomhalf.filled", "macbook", "rectangle.inset.filled", "text.below.photo.fill", "waveform"]
        picker = AppearanceIconGroup(items: zip(Self.modes, symbols).map { ($0.title, $1) })
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.previewModes")
        toolTip = "Preview an appearance. Choose the active dictation style from the menu bar's Appearance menu."
        picker.setAccessibilityLabel("Appearance preview")
        addSubview(picker)
        picker.onSelection = { [weak self] index in
            guard let self else { return }
            self.select(Self.modes[index])
            self.onSelection?(Self.modes[index])
        }
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        picker.frame = bounds
    }

    func select(_ mode: GlowAppearance) {
        picker.select(Self.modes.firstIndex(of: mode.selection)!)
    }
}
