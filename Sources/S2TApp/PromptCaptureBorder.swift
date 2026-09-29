import AppKit

/// The ⌘-drag selection: a light dim around it, a light ring and a faint halo, all outside the
/// captured area and kept sharp so the surroundings stay readable. The overlay window covers only
/// the screen where the gesture happens; one window across displays shows on only one of them. Every part is a plain layer whose frame changes, so the render
/// server never re-rasterizes a path while dragging. Drag positions arrive on the event-tap
/// thread through `move(toQuartz:)` and update the layers there, without the main thread.
final class PromptCaptureBorder: @unchecked Sendable {
    static let dimOpacity: Float = 0.14
    static let fadeDuration = 0.42
    private let lock = NSLock()
    private var panelsStorage: [NSPanel] = []
    private let container = CALayer()
    private let dims = (0..<4).map { _ in CALayer() }
    private let halo = CALayer()
    private let ring = CALayer()
    private let shutterFill = CALayer()
    private var bounds = CGRect.zero
    private var primaryHeight: CGFloat = 0
    private var origin = CGPoint.zero
    private var anchor: CGPoint?
    private var fadeGeneration = 0
    private var current: CGRect?

    init() {
        container.anchorPoint = .zero
        container.masksToBounds = true
        for dim in dims { dim.backgroundColor = NSColor.black.cgColor; container.addSublayer(dim) }
        halo.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        halo.borderWidth = 3
        halo.cornerRadius = 7; halo.cornerCurve = .continuous
        ring.borderColor = NSColor.white.withAlphaComponent(0.62).cgColor
        ring.borderWidth = 1.5
        ring.cornerRadius = 4; ring.cornerCurve = .continuous
        shutterFill.backgroundColor = NSColor.white.cgColor
        shutterFill.opacity = 0
        container.addSublayer(halo)
        container.addSublayer(ring)
        container.addSublayer(shutterFill)
        layout(nil)
    }

    @MainActor var panels: [NSPanel] { panelsStorage }
    var rect: CGRect? { lock.lock(); defer { lock.unlock() }; return current }

    /// Places the overlay on one screen. Defaults to the screen under the pointer.
    @MainActor func prepare(for screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.frame
        let panel: NSPanel
        if let existing = panelsStorage.first { panel = existing }
        else {
            panel = PromptCaptureFeedback.makePanel()
            panel.contentView?.layer?.addSublayer(container)
            panelsStorage = [panel]
        }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        lock.lock()
        bounds = CGRect(origin: .zero, size: frame.size)
        origin = frame.origin
        primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        CATransaction.begin(); CATransaction.setDisableActions(true)
        container.frame = bounds
        container.contentsScale = screen.backingScaleFactor
        CATransaction.commit()
        lock.unlock()
    }

    @MainActor private static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { overlap($0.frame, rect) < overlap($1.frame, rect) }
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let area = lhs.intersection(rhs); return area.isNull ? 0 : area.width * area.height
    }

    /// Starts a drag at a Cocoa screen point. Later event-tap positions extend it from here.
    @MainActor func begin(at point: CGPoint, present: Bool) {
        prepare(for: NSScreen.screens.first(where: { $0.frame.contains(point) }))
        guard let panel = panelsStorage.first else { return }
        lock.lock()
        anchor = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        fadeGeneration += 1
        current = nil
        layout(nil)
        lock.unlock()
        if present, !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Event-tap thread. Quartz coordinates, top-left origin on the primary display.
    func move(toQuartz point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        guard let anchor, !panelsStorage.isEmpty else { return }
        let local = CGPoint(x: point.x - origin.x, y: primaryHeight - point.y - origin.y)
        // The selection stays on the screen where it started, like its capture.
        let selection = CGRect(x: min(anchor.x, local.x), y: min(anchor.y, local.y),
                               width: abs(local.x - anchor.x), height: abs(local.y - anchor.y)).intersection(bounds)
        let visible = max(selection.width, selection.height) >= 6
        current = visible ? selection.offsetBy(dx: origin.x, dy: origin.y) : nil
        layout(visible ? selection : nil)
    }

    /// Draws a selection in Cocoa screen coordinates and ends any drag tracking.
    @MainActor func show(_ rect: CGRect, present: Bool) {
        prepare(for: Self.screen(for: rect))
        guard let panel = panelsStorage.first else { return }
        lock.lock()
        anchor = nil
        fadeGeneration += 1
        current = rect
        layout(rect.offsetBy(dx: -origin.x, dy: -origin.y))
        lock.unlock()
        if present, !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Plays once the selection's pixels are captured: a soft white shutter inside the selection
    /// while the ring and dim fade in place. Nothing expands. The final model opacity is zero,
    /// so nothing reappears when the animation ends.
    @MainActor func shutter(reducedMotion: Bool = false) {
        lock.lock()
        anchor = nil
        fadeGeneration += 1
        let id = fadeGeneration
        let duration = reducedMotion ? 0.2 : Self.fadeDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.finishFade(id) } }
        if !reducedMotion, current != nil {
            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values = [0, 0.38, 0]; flash.keyTimes = [0, 0.18, 1]
            flash.duration = duration * 0.8
            flash.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
            shutterFill.add(flash, forKey: "shutter")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        container.opacity = 0
        container.add(fade, forKey: "fade")
        CATransaction.commit()
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in self?.finishFade(id) }
    }

    @MainActor func flash() { shutter() }

    @MainActor private func finishFade(_ id: Int) {
        lock.lock()
        let stale = fadeGeneration != id
        lock.unlock()
        if !stale { hide() }
    }

    @MainActor func hide() {
        lock.lock()
        anchor = nil
        fadeGeneration += 1
        current = nil
        layout(nil)
        lock.unlock()
        for panel in panelsStorage where panel.isVisible { panel.orderOut(nil) }
    }

    /// Lays out the layers for a panel-local selection. Callers hold `lock`.
    private func layout(_ selection: CGRect?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let selection, !selection.isNull, !selection.isEmpty {
            container.removeAnimation(forKey: "fade")
            shutterFill.removeAnimation(forKey: "shutter")
            container.opacity = 1
            // The ring's inner edge sits 2.5 points out and its inner corner radius (4 − 1.5) is
            // centred on the selection corner, so no drawn pixel reaches the captured area.
            let hole = selection.insetBy(dx: -2, dy: -2)
            let b = bounds
            let outside = [
                CGRect(x: b.minX, y: b.minY, width: b.width, height: max(0, hole.minY - b.minY)),
                CGRect(x: b.minX, y: hole.maxY, width: b.width, height: max(0, b.maxY - hole.maxY)),
                CGRect(x: b.minX, y: hole.minY, width: max(0, hole.minX - b.minX), height: hole.height),
                CGRect(x: hole.maxX, y: hole.minY, width: max(0, b.maxX - hole.maxX), height: hole.height)
            ]
            for (index, frame) in outside.enumerated() {
                dims[index].frame = frame
                dims[index].opacity = Self.dimOpacity
                dims[index].isHidden = false
            }
            ring.frame = selection.insetBy(dx: -4, dy: -4)
            halo.frame = selection.insetBy(dx: -7, dy: -7)
            shutterFill.frame = selection
            ring.isHidden = false; halo.isHidden = false; shutterFill.isHidden = false
        } else {
            for layer in dims + [ring, halo, shutterFill] { layer.isHidden = true }
        }
        CATransaction.commit()
    }

    /// The part of a selection that is guaranteed free of any drawing.
    static func clearArea(for rect: CGRect) -> CGRect { rect.insetBy(dx: -2, dy: -2) }
}
