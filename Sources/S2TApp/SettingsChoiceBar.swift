import AppKit
import SwiftUI

struct SettingsChoiceBar: NSViewRepresentable {
    let titles: [String]
    let selected: Int
    let label: String
    let select: (Int) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> SettingsChoiceControl {
        SettingsChoiceControl(items: titles.map { .init(title: $0) }, label: label)
    }
    func updateNSView(_ control: SettingsChoiceControl, context: Context) {
        if control.items.map(\.title) != titles { control.items = titles.map { .init(title: $0) } }
        control.select(selected)
        control.isEnabled = isEnabled
        control.onSelection = select
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsChoiceControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }
}

struct SettingsChoiceItem {
    var title: String
    var image: NSImage? = nil
}

@MainActor class SettingsChoiceControl: NSSegmentedControl {
    private let hoverLayer = CALayer()
    private var hoverArea: NSTrackingArea?
    private var hoveredSegment: Int?
    var onSelection: ((Int) -> Void)?
    var items: [SettingsChoiceItem] { didSet { updateItems() } }
    override var isEnabled: Bool { didSet { updateHover() } }

    init(items: [SettingsChoiceItem], label: String) {
        self.items = items
        super.init(frame: .zero)
        trackingMode = .selectOne
        segmentStyle = .automatic
        segmentDistribution = .fillEqually
        focusRingType = .none
        if #available(macOS 26, *) {
            controlSize = .extraLarge
            borderShape = .capsule
        } else {
            controlSize = .large
        }
        if #available(macOS 27, *) {
            // Public NSSegmentedControl.Role.tabs; KVC also supports builds using the macOS 26 SDK.
            setValue(1, forKey: "role")
        }
        updateItems()
        selectedSegment = 0
        setAccessibilityLabel(label)
        target = self
        action = #selector(changeSelection(_:))
        wantsLayer = true
        hoverLayer.opacity = 0
        hoverLayer.zPosition = 1
        layer?.addSublayer(hoverLayer)
    }
    required init?(coder: NSCoder) { nil }

    func select(_ index: Int) {
        if selectedSegment != index { selectedSegment = index }
        updateHover()
    }
    private func updateItems() {
        let selected = selectedSegment
        segmentCount = items.count
        for (index, item) in items.enumerated() {
            setImage(item.image, forSegment: index)
            setImageScaling(.scaleProportionallyDown, forSegment: index)
            setLabel(item.image == nil ? item.title : "", forSegment: index)
            setToolTip(item.title, forSegment: index)
        }
        if items.indices.contains(selected) { selectedSegment = selected }
        invalidateIntrinsicContentSize()
    }
    @objc private func changeSelection(_ sender: NSSegmentedControl) {
        guard isEnabled, items.indices.contains(selectedSegment) else { return }
        updateHover()
        onSelection?(selectedSegment)
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { trackHover(event) }
    override func mouseMoved(with event: NSEvent) { trackHover(event) }
    override func mouseExited(with event: NSEvent) { hoveredSegment = nil; updateHover() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hoveredSegment = nil; updateHover() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateHover() }
    override func layout() { super.layout(); updateHover() }

    private var segmentArea: NSRect {
        let height = min(bounds.height, intrinsicContentSize.height)
        return NSRect(x: bounds.minX, y: bounds.midY - height / 2, width: bounds.width, height: height)
            .insetBy(dx: 4, dy: 4)
    }
    private func trackHover(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let area = segmentArea
        if isEnabled, segmentCount > 0, area.contains(point) {
            hoveredSegment = min(segmentCount - 1, Int((point.x - area.minX) / (area.width / CGFloat(segmentCount))))
        } else { hoveredSegment = nil }
        updateHover()
    }
    private func updateHover() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard isEnabled, let index = hoveredSegment, index != selectedSegment, items.indices.contains(index) else {
            hoverLayer.opacity = 0
            return
        }
        let area = segmentArea
        let width = area.width / CGFloat(segmentCount)
        hoverLayer.frame = NSRect(x: area.minX + CGFloat(index) * width + 2, y: area.minY,
                                 width: max(0, width - 4), height: area.height)
        hoverLayer.cornerRadius = area.height / 2
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hoverLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        }
        hoverLayer.opacity = 1
    }
}
