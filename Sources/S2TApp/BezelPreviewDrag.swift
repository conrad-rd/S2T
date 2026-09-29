import AppKit
import S2TCore

@MainActor final class BezelPreviewContainer: NSView {
    let indicator = BezelIndicatorView(frame: CGRect(origin: .zero, size: BezelGeometry.size))
    var side = BezelSide.right
    var position = 0.5
    var onMove: ((BezelSide, Double) -> Void)?
    private(set) var floatingIndicator: BezelIndicatorView?
    private(set) var isDragging = false
    private var overlay: BezelDragOverlay?
    private var start: (point: NSPoint, side: BezelSide, position: Double, centerY: CGFloat)?
    private var center = NSPoint.zero
    private var velocity = CGVector.zero
    private var lastPoint = NSPoint.zero
    private var lastEventTime = 0.0
    private var reducedMotion = false
    private var settling = false
    private var animationTimer: Timer?
    private var release: (time: Double, center: CGPoint)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        identifier = NSUserInterfaceItemIdentifier("appearance.bezel.drag")
        indicator.wantsLayer = true
        addSubview(indicator)
        toolTip = "Drag to either edge. Arrow keys change the side or height. Escape cancels a drag."
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Bezel placement")
    }
    required init?(coder: NSCoder) { nil }

    func synchronize(side: BezelSide, position: Double, phase: Int, time: Double, reducedMotion: Bool) {
        if start == nil && !settling {
            self.side = side
            self.position = position
            placeAttached()
            self.reducedMotion = reducedMotion
        }
        let symbol: BezelSymbol = phase == 0 ? .checkmark : phase == 2 ? .spinner : .waveform
        let bands = (0..<7).map { 0.5 + 0.4 * sin(time * 2 + Double($0)) }
        for view in [indicator, floatingIndicator].compactMap({ $0 }) {
            view.update(form: .shown, symbol: symbol, level: 0.65, spectrum: bands, time: time, reducedMotion: reducedMotion)
        }

    }

    override func layout() {
        super.layout()
        if start == nil && !settling { placeAttached() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)), name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowClosing(_:)), name: NSWindow.didResignKeyNotification, object: window)
        } else { cancelDrag() }
    }
    @objc private func windowClosing(_ notification: Notification) { cancelDrag() }
    override func viewDidHide() { super.viewDidHide(); cancelDrag() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let body = indicator.convert(indicator.bounds, to: self)
        let hit = NSRect(x: side == .left ? 0 : bounds.width - 70, y: body.midY - 56, width: 70, height: 112)
        return hit.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        finishFloating()
        let point = convert(event.locationInWindow, from: nil)
        start = (point, side, position, indicator.frame.midY)
        lastPoint = point
        lastEventTime = CACurrentMediaTime()
        window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !isDragging {
            guard hypot(point.x - start.point.x, point.y - start.point.y) > 2 else { return }
            beginFloating()
        }
        let now = CACurrentMediaTime()
        let elapsed = max(1.0 / 120, now - lastEventTime)
        if hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 0.1 {
            velocity = CGVector(dx: max(-1000, min(1000, (point.x - lastPoint.x) / elapsed)),
                            dy: max(-1000, min(1000, (point.y - lastPoint.y) / elapsed)))
            lastEventTime = now
        }
        let centerY = start.centerY + point.y - start.point.y
        position = min(1, max(0, (bounds.maxY - 60 - centerY) / max(1, bounds.height - 120)))
        center = NSPoint(x: min(bounds.width - 32, max(32, point.x)), y: bounds.height - 60 - position * max(1, bounds.height - 120))
        lastPoint = point
        updateBlob()
        positionFloating(at: center)
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        if isDragging {
            mouseDragged(with: event)
            side = center.x < bounds.midX ? .left : .right
            start = nil
            isDragging = false
            settling = true
            placeAttached()
            settleAtEdge()
            onMove?(side, position)
        } else { start = nil }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelDrag() }
        else if event.keyCode == 123 { change(side: .left, position: position) }
        else if event.keyCode == 124 { change(side: .right, position: position) }
        else if event.keyCode == 126 { change(side: side, position: position - 0.05) }
        else if event.keyCode == 125 { change(side: side, position: position + 0.05) }
        else { super.keyDown(with: event) }
    }
    override func accessibilityValue() -> Any? { "\(side.title), \(Int((position * 100).rounded())) percent from top" }
    override func accessibilityPerformIncrement() -> Bool { change(side: side, position: position + 0.05); return true }
    override func accessibilityPerformDecrement() -> Bool { change(side: side, position: position - 0.05); return true }

    private func change(side: BezelSide, position: Double) {
        cancelDrag()
        self.side = side
        self.position = min(1, max(0, position))
        placeAttached()
        onMove?(side, self.position)
    }
    private func placeAttached() {
        indicator.side = side
        indicator.setFrameOrigin(BezelGeometry.frame(screen: bounds, side: side,
            verticalPosition: position).origin)
    }
    private func beginFloating() {
        guard let root = window?.contentView else { return }
        let overlay = BezelDragOverlay(frame: root.bounds)
        overlay.autoresizingMask = [.width, .height]
        root.addSubview(overlay, positioned: .above, relativeTo: nil)
        let size = convert(NSRect(origin: .zero, size: BezelGeometry.size), to: overlay).size
        let floating = BezelIndicatorView(frame: NSRect(origin: .zero, size: size))
        floating.setBoundsSize(BezelGeometry.size)
        floating.wantsLayer = true
        overlay.addSubview(floating)
        self.overlay = overlay
        floatingIndicator = floating
        floating.update(form: .shown, symbol: indicator.symbol, level: 0.65, spectrum: indicator.bands,
                        time: CACurrentMediaTime(), reducedMotion: reducedMotion)
        indicator.isHidden = true
        isDragging = true
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }
    private func positionFloating(at point: NSPoint) {
        guard let floatingIndicator, let overlay else { return }
        let point = convert(point, to: overlay)
        floatingIndicator.setFrameOrigin(NSPoint(x: point.x - floatingIndicator.frame.width / 2,
                                                y: point.y - floatingIndicator.frame.height / 2))
    }
    private func updateBlob() {
        guard let floatingIndicator else { return }
        let age = max(0, CACurrentMediaTime() - lastEventTime)
        let decay = exp(-age * (settling ? 14 : 4.5))
        let motion = reducedMotion ? CGVector.zero : CGVector(dx: velocity.dx * decay, dy: velocity.dy * decay)
        let wobble = reducedMotion || settling ? 0 : sin(age * 19) * decay * min(1, hypot(velocity.dx, velocity.dy) / 500)
        let nearest: BezelSide = center.x < bounds.midX ? .left : .right
        let distance = nearest == .left ? center.x : bounds.width - center.x
        floatingIndicator.dragVelocity = CGVector(dx: motion.dx, dy: -motion.dy)
        floatingIndicator.previewShape = BezelDragShape.make(velocity: motion, wobble: wobble, side: nearest, distance: distance)
    }
    static func blob(velocity: CGVector) -> BezelShape { BezelDragShape.make(velocity: velocity) }

    private func settleAtEdge() {
        guard floatingIndicator != nil else { finishFloating(); return }
        if reducedMotion { finishFloating(); return }
        settling = true
        release = (CACurrentMediaTime(), center)
    }
    private func animate() {
        guard let floatingIndicator else { return }
        if isDragging { updateBlob(); return }
        guard let release else { return }
        let progress = min(1, (CACurrentMediaTime() - release.time) / 0.36)
        let target = indicator.convert(indicator.displayedShape.symbolCenter, to: self)
        let travel = 1 - pow(1 - progress, 3)
        center = CGPoint(x: release.center.x + (target.x - release.center.x) * travel,
                         y: release.center.y + (target.y - release.center.y) * travel)
        positionFloating(at: center)
        updateBlob()
        if let source = floatingIndicator.previewShape {
            let targetShape = indicator.displayedShape
            let origin = indicator.convert(NSPoint.zero, to: floatingIndicator)
            var transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            let shape = BezelShape(path: targetShape.path.copy(using: &transform)!, symbolCenter: targetShape.symbolCenter.applying(transform))
            let distance = side == .left ? center.x : bounds.width - center.x
            let targetDistance = side == .left ? target.x : bounds.width - target.x
            let t = min(1, max(0, (94 - distance) / max(1, 94 - targetDistance)))
            floatingIndicator.previewShape = BezelDragShape.morph(source, into: shape, amount: travel * t * t * (3 - 2 * t))
        }
        if progress >= 1 { finishFloating() }
    }
    private func cancelDrag() {
        if let start { side = start.side; position = start.position }
        start = nil
        finishFloating()
        placeAttached()
    }
    private func finishFloating() {
        animationTimer?.invalidate()
        animationTimer = nil
        release = nil
        isDragging = false
        settling = false
        overlay?.removeFromSuperview()
        overlay = nil
        floatingIndicator = nil
        indicator.isHidden = false
    }
}

private final class BezelDragOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
