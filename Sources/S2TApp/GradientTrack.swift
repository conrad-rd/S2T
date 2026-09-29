import AppKit
import S2TCore

@MainActor final class GradientTrack: NSView {
    private(set) var gradient = GlowGradient()
    private(set) var handles: [GradientStopHandle] = []
    var onSelect: ((UUID) -> Void)?
    var onMove: ((UUID, Double) -> Void)?
    var onEditColor: ((UUID) -> Void)?
    var onAdd: ((Double) -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onRestore: ((GlowGradient) -> Void)?
    var lineRect: CGRect { CGRect(x: 20, y: (bounds.height * 0.58).rounded() - 2, width: max(1, bounds.width - 40), height: 4) }
    var tickPositions: [CGFloat] { (0...20).map { lineRect.minX + CGFloat($0) / 20 * lineRect.width } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("appearance.gradient.track")
        toolTip = "Click a color to edit it. Drag to move it. Click the line to add a color."
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refresh(_ gradient: GlowGradient, selected: UUID?) {
        self.gradient = gradient
        let existing = Dictionary(uniqueKeysWithValues: handles.map { ($0.stopID, $0) })
        let ids = Set(gradient.stops.map(\.id))
        for handle in handles where !ids.contains(handle.stopID) {
            handle.dragStart = nil
            handle.removeFromSuperview()
        }
        handles = gradient.stops.map { stop in
            if let handle = existing[stop.id] { return handle }
            let handle = GradientStopHandle(id: stop.id)
            handle.track = self
            addSubview(handle)
            return handle
        }
        for i in handles.indices {
            let stop = gradient.stops[i]
            handles[i].tag = i
            handles[i].color = NSColor(srgbRed: stop.color.x, green: stop.color.y, blue: stop.color.z, alpha: 1)
            handles[i].state = selected == stop.id ? .on : .off
            handles[i].setAccessibilityLabel("Gradient color \(i + 1)")
            handles[i].setAccessibilityValue("\(Int((stop.position * 100).rounded())) percent")
            handles[i].needsDisplay = true
        }
        needsLayout = true
        needsDisplay = true
    }

    func cancelDrag() { handles.forEach { $0.dragStart = nil } }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { cancelDrag() }; super.viewWillMove(toWindow: newWindow) }

    override func layout() {
        super.layout()
        for i in handles.indices {
            let center = point(at: gradient.stops[i].position)
            handles[i].frame = CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)
        }
    }

    func point(at position: Double) -> CGPoint { CGPoint(x: lineRect.minX + position * lineRect.width, y: lineRect.midY) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let parent = superview else { return nil }
        let local = convert(point, from: parent)
        guard bounds.contains(local) else { return nil }
        if let nearest = handles.min(by: {
            abs($0.frame.midX - local.x) < abs($1.frame.midX - local.x)
        }), nearest.frame.insetBy(dx: -2, dy: 0).contains(local) { return nearest }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.y - lineRect.midY) <= 16, lineRect.minX...lineRect.maxX ~= point.x else { return }
        onAdd?((point.x - lineRect.minX) / lineRect.width)
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.35).setFill()
        background.fill()
        let ticks = NSBezierPath()
        for (i, x) in tickPositions.enumerated() {
            ticks.move(to: CGPoint(x: x, y: 23))
            ticks.line(to: CGPoint(x: x, y: i % 5 == 0 ? 31 : 27))
        }
        NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
        ticks.lineWidth = 1
        ticks.stroke()
        for stop in gradient.stops {
            let x = point(at: stop.position).x
            let guide = NSBezierPath()
            guide.move(to: CGPoint(x: x, y: 35))
            guide.line(to: CGPoint(x: x, y: bounds.height - 9))
            guide.setLineDash([2, 3], count: 2, phase: 0)
            guide.lineWidth = 0.5
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            guide.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        let line = NSBezierPath()
        let clearance: CGFloat = 13.25
        var start = lineRect.minX
        for stop in gradient.stops {
            let center = point(at: stop.position).x
            let end = min(lineRect.maxX, center - clearance)
            if end > start {
                line.appendRoundedRect(CGRect(x: start, y: lineRect.minY, width: end - start, height: lineRect.height), xRadius: 2, yRadius: 2)
            }
            start = max(start, center + clearance)
        }
        if start < lineRect.maxX {
            line.appendRoundedRect(CGRect(x: start, y: lineRect.minY, width: lineRect.maxX - start, height: lineRect.height), xRadius: 2, yRadius: 2)
        }
        line.addClip()
        let sampler = gradient.sampler
        let count = max(1, Int(ceil(lineRect.width * (window?.backingScaleFactor ?? 2))))
        for i in 0..<count {
            let rgb = sampler.color(at: Double(i) / Double(count))
            NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1).setFill()
            CGRect(x: lineRect.minX + Double(i) * lineRect.width / Double(count), y: lineRect.minY,
                   width: lineRect.width / Double(count) + 0.5, height: lineRect.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for percent in [0, 50, 100] {
            let title = "\(percent)%" as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: point(at: Double(percent) / 100).x - size.width / 2, y: 5), withAttributes: attributes)
        }
    }
}

@MainActor final class GradientStopHandle: NSButton, NSMenuItemValidation {
    let stopID: UUID
    weak var track: GradientTrack?
    var color = NSColor.controlAccentColor { didSet { updateGlow() } }
    override var state: NSControl.StateValue { didSet { updateGlow() } }
    let selectionGlow = GradientStopGlow()
    var dragStart: (gradient: GlowGradient, position: Double, x: CGFloat)?
    private var hasDragged = false

    init(id: UUID) {
        stopID = id
        super.init(frame: .zero)
        title = ""
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        clipsToBounds = false
        layer?.masksToBounds = false
        layer?.addSublayer(selectionGlow.layer)
        setButtonType(.momentaryChange)
        target = self
        action = #selector(editColor)
        setAccessibilityRole(.slider)
        setAccessibilityHelp("Click to change color. Drag or use arrow keys to move. Delete removes the color.")
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Remove color", action: #selector(removeColor), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        self.menu = menu
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateGlow),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateGlow),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        selectionGlow.layout(in: bounds, scale: window?.backingScaleFactor ?? 2)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateGlow() }
    @objc private func updateGlow() {
        selectionGlow.update(color: color, selected: state == .on,
            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            visible: window?.isVisible == true && window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor)
    }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 7, dy: 7))
        (state == .on ? color : NSColor.controlBackgroundColor).setFill()
        circle.fill()
        color.setStroke()
        circle.lineWidth = 2.5
        circle.stroke()
    }
    @objc private func editColor() { track?.onEditColor?(stopID) }
    @objc private func removeColor() { track?.onRemove?(stopID) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { (track?.gradient.stops.count ?? 0) > 1 }
    override func mouseDown(with event: NSEvent) {
        guard let track, let index = track.gradient.index(of: stopID) else { return }
        window?.makeFirstResponder(self)
        track.onSelect?(stopID)
        hasDragged = false
        dragStart = (track.gradient, track.gradient.stops[index].position, track.convert(event.locationInWindow, from: nil).x)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let track, let start = dragStart else { return }
        let x = track.convert(event.locationInWindow, from: nil).x
        if abs(x - start.x) > 3 { hasDragged = true }
        if hasDragged { track.onMove?(stopID, start.position + (x - start.x) / track.lineRect.width) }
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        dragStart = nil
        if !hasDragged { editColor() }
    }
    override func keyDown(with event: NSEvent) {
        guard let track else { return }
        if event.keyCode == 53, let start = dragStart {
            dragStart = nil
            track.onRestore?(start.gradient)
        } else if event.keyCode == 51 || event.keyCode == 117 {
            dragStart = nil
            removeColor()
        } else if [123, 124, 125, 126].contains(event.keyCode) {
            let direction = event.keyCode == 123 || event.keyCode == 125 ? -1.0 : 1.0
            move(by: direction * (event.modifierFlags.contains(.shift) ? 0.05 : 0.01))
        } else { super.keyDown(with: event) }
    }
    private func move(by amount: Double) {
        guard let track, let index = track.gradient.index(of: stopID) else { return }
        track.onSelect?(stopID)
        track.onMove?(stopID, track.gradient.stops[index].position + amount)
    }
    override func accessibilityPerformIncrement() -> Bool { move(by: 0.01); return true }
    override func accessibilityPerformDecrement() -> Bool { move(by: -0.01); return true }
}
