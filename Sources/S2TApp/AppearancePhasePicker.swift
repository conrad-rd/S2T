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

final class AppearancePhasePicker: SettingsChoiceControl {
    init(frame: NSRect) {
        let items = zip(["Stiff", "Speaking", "Processing"], ["pause", "waveform", "ellipsis.circle"]).map {
            SettingsChoiceItem(title: $0, image: NSImage(systemSymbolName: $1, accessibilityDescription: $0))
        }
        super.init(items: items, label: "Preview state")
        self.frame = frame
        translatesAutoresizingMaskIntoConstraints = false
        identifier = NSUserInterfaceItemIdentifier("appearance.previewPhase")
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 132), heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func select(_ phase: Int, bezel: Bool) {
        selectedSegment = phase
        let title = bezel ? "Done" : "Stiff"
        if items[0].title != title {
            items[0] = SettingsChoiceItem(title: title, image: NSImage(systemSymbolName: bezel ? "checkmark" : "pause", accessibilityDescription: title))
        }
    }
}
