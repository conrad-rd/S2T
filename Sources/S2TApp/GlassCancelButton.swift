import AppKit

@MainActor final class GlassCancelButton: NSButton {
    var onCancel: (() -> Void)?
    var drawsArtwork = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        target = self
        action = #selector(cancelDictation)
        setAccessibilityLabel("Cancel dictation")
        toolTip = "Cancel dictation"
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func cancelDictation() { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsArtwork, let context = NSGraphicsContext.current?.cgContext else { return }
        GlassCapsuleArtwork.drawCancel(in: bounds, pressed: isHighlighted, context: context)
    }
}

/// Receives only capsule interactions; the larger material window stays click-through.
@MainActor final class GlassInteractionPanel: NSPanel {
    let interaction = GlassCapsuleInteractionView(frame: CGRect(x: 0, y: 0, width: 112, height: 36))
    var button: GlassCancelButton { interaction.button }
    init() {
        super.init(contentRect: interaction.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = interaction
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateHitTesting(pointer: CGPoint) {
        let local = CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
        ignoresMouseEvents = !interaction.tracking && !interaction.hitPath.contains(local)
    }
}

@MainActor final class GlassCapsuleInteractionView: NSView {
    let button = GlassCancelButton(frame: CGRect(x: 6, y: 6, width: 24, height: 24))
    var onBegin: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: ((CGPoint?) -> Void)?
    var shape: CGPath?
    var hitPath: CGPath { shape ?? GlassCapsuleArtwork.path(in: bounds) }
    private var start: CGPoint?
    private var moved = false
    var tracking: Bool { start != nil }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.drawsArtwork = false
        addSubview(button)
        toolTip = "Drag to either screen edge for Bezel, or away for Liquid Glass."
        setAccessibilityLabel("Dictation capsule. Drag to position.")
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        button.frame = CGRect(x: bounds.width * 6 / 112, y: bounds.height / 6,
            width: bounds.width * 24 / 112, height: bounds.height * 2 / 3)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
        if !button.isHidden { addCursorRect(button.frame, cursor: .arrow) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitPath.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(event)
        start = point
        moved = false
        onBegin?(point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = screenPoint(event)
        if !moved && hypot(point.x - start.x, point.y - start.y) < 3 { return }
        moved = true
        onDrag?(point)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        let point = screenPoint(event)
        if let start, hypot(point.x - start.x, point.y - start.y) >= 3 { moved = true }
        if moved { onDrag?(point) }
        let destination = moved ? point : nil
        start = nil
        moved = false
        onEnd?(destination)
    }
    func cancelDrag() { start = nil; moved = false }
}
