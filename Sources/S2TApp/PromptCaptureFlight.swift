import AppKit

/// Flies a captured thumbnail into the deck. Core Animation runs the motion in the render
/// server inside a stationary, click-through panel, so a busy main thread cannot make it stutter
/// and no window moves or resizes during the flight.
@MainActor final class PromptCaptureFlight {
    private(set) var panel: NSPanel?
    private var card: CALayer?
    private var completion: (() -> Void)?
    private var generation = 0
    private(set) var active = false
    static let duration = 0.52

    /// Covers one screen. A window across displays is shown on only one of them.
    func prepare(for screen: NSScreen? = nil) {
        guard let screen = screen ?? NSScreen.main else { return }
        let window = panel ?? PromptCaptureFeedback.makePanel()
        panel = window
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
    }

    func show(_ card: CALayer, from: CGPoint, to: CGPoint, scale: CGFloat, present: Bool, completion: @escaping () -> Void) {
        finish()
        // The capture and its deck share a screen; fly on the deck's screen.
        prepare(for: NSScreen.screens.first(where: { $0.frame.contains(to) }))
        guard let panel, let host = panel.contentView?.layer else { completion(); return }
        generation += 1
        let id = generation
        self.card = card; self.completion = completion; active = true
        let start = CGPoint(x: from.x - panel.frame.minX, y: from.y - panel.frame.minY)
        let end = CGPoint(x: to.x - panel.frame.minX, y: to.y - panel.frame.minY)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        card.position = end
        host.addSublayer(card)
        CATransaction.commit()
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start); move.toValue = NSValue(point: end)
        move.duration = Self.duration
        // Cubic ease-out, matching the previous 1 − (1 − t)³ path.
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
        let shrink = CASpringAnimation(keyPath: "transform.scale")
        shrink.fromValue = scale; shrink.toValue = 1
        shrink.mass = 1; shrink.stiffness = 260; shrink.damping = 28; shrink.duration = Self.duration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in MainActor.assumeIsolated { self?.land(id) } }
        card.add(move, forKey: "flight")
        card.add(shrink, forKey: "shrink")
        CATransaction.commit()
        if present { panel.orderFrontRegardless() }
        // Land even if Core Animation never commits, for example while the display sleeps.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration + 0.15) { [weak self] in self?.land(id) }
    }

    private func land(_ id: Int) {
        guard active, generation == id else { return }
        finish()
    }

    func finish(reveal: Bool = true) {
        active = false
        card?.removeAllAnimations()
        card?.removeFromSuperlayer(); card = nil
        if panel?.isVisible == true { panel?.orderOut(nil) }
        let completed = completion; completion = nil
        if reveal { completed?() }
    }

    /// The running motion, for hidden verification.
    var motion: (from: CGPoint, to: CGPoint, duration: Double)? {
        guard let move = card?.animation(forKey: "flight") as? CABasicAnimation,
              let from = (move.fromValue as? NSValue)?.pointValue, let to = (move.toValue as? NSValue)?.pointValue else { return nil }
        return (from, to, move.duration)
    }
}

/// Drops the collected screenshots from the deck into the prompt field as they are pasted.
/// Each card arcs up out of the corner, lifts slightly, then shrinks into the field with a small
/// tilt, staggered one after another, and fades as it enters the field.
/// Core Animation runs everything in the render server inside a stationary click-through panel.
@MainActor final class PromptCaptureDrop {
    struct Card {
        let image: CGImage?
        let size: CGSize
        let position: CGPoint
        let scale: CGFloat
    }
    private(set) var panel: NSPanel?
    private var layers: [CALayer] = []
    private var generation = 0
    private(set) var active = false
    static let duration = 0.66
    static let stagger = 0.075

    private func prepare(for screen: NSScreen) -> NSPanel {
        let window = panel ?? PromptCaptureFeedback.makePanel()
        panel = window
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        return window
    }

    /// The point where cards land: near the leading edge, where attachments usually appear.
    static func landing(in field: CGRect, index: Int) -> CGPoint {
        CGPoint(x: field.minX + min(field.width * 0.22, 96) + CGFloat(index) * 14, y: field.midY)
    }

    func drop(_ cards: [Card], into field: CGRect, present: Bool, reducedMotion: Bool) {
        finish()
        // Run on the field's screen. Cards from a deck on another screen enter from the same
        // bottom-left spot there, since one window cannot span displays.
        guard !cards.isEmpty, let screen = NSScreen.screens.max(by: { Self.overlap($0.frame, field) < Self.overlap($1.frame, field) }) else { return }
        let panel = prepare(for: screen)
        guard let host = panel.contentView?.layer else { return }
        generation += 1
        let id = generation
        active = true
        let origin = panel.frame.origin
        let now = CACurrentMediaTime()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index, card) in cards.enumerated() {
            let layer = PromptCaptureFeedback.makeCard(size: card.size, image: card.image, scale: panel.backingScaleFactor)
            let source = NSScreen.screens.first(where: { $0.frame.contains(card.position) })
            let position = source.map { $0 == screen ? card.position
                : CGPoint(x: card.position.x - $0.visibleFrame.minX + screen.visibleFrame.minX,
                          y: card.position.y - $0.visibleFrame.minY + screen.visibleFrame.minY) } ?? card.position
            let start = CGPoint(x: position.x - origin.x, y: position.y - origin.y)
            let landing = Self.landing(in: field, index: index)
            let end = CGPoint(x: landing.x - origin.x, y: landing.y - origin.y)
            let finalScale = max(0.08, min(field.height * 0.7, 40) / max(1, card.size.height))
            layer.position = end
            layer.opacity = 0
            layer.transform = CATransform3DMakeScale(finalScale, finalScale, 1)
            host.addSublayer(layer)
            layers.append(layer)
            let begin = now + Double(index) * (reducedMotion ? 0 : Self.stagger)
            let group = CAAnimationGroup()
            if reducedMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1; fade.toValue = 0
                group.animations = [fade]
                group.duration = 0.2
            } else {
                // Arc up and over, then fall into the field.
                let path = CGMutablePath()
                path.move(to: start)
                let lift = max(90, min(260, abs(end.y - start.y) * 0.45 + 90))
                path.addCurve(to: end, control1: CGPoint(x: start.x + (end.x - start.x) * 0.15, y: max(start.y, end.y) + lift),
                              control2: CGPoint(x: end.x, y: end.y + lift * 0.6))
                let move = CAKeyframeAnimation(keyPath: "position")
                move.path = path
                move.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                scale.values = [card.scale, max(card.scale, 0.62), finalScale * 0.85]
                scale.keyTimes = [0, 0.38, 1]
                scale.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
                let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
                let lean = (index.isMultiple(of: 2) ? 1.0 : -1.0) * 0.14
                tilt.values = [0, lean, -lean * 0.3, 0]
                tilt.keyTimes = [0, 0.4, 0.8, 1]
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [1, 1, 0]
                fade.keyTimes = [0, 0.82, 1]
                group.animations = [move, scale, tilt, fade]
                group.duration = Self.duration
            }
            group.beginTime = begin
            group.fillMode = .backwards
            layer.add(group, forKey: "drop")
        }
        CATransaction.commit()
        if present { panel.orderFrontRegardless() }
        let total = (reducedMotion ? 0.2 : Self.duration) + Double(cards.count - 1) * (reducedMotion ? 0 : Self.stagger)
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.05) { [weak self] in
            guard let self, self.generation == id else { return }
            self.finish()
        }
    }

    func finish() {
        active = false
        for layer in layers { layer.removeAllAnimations(); layer.removeFromSuperlayer() }
        layers = []
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }

    var cardCount: Int { layers.filter { $0.animation(forKey: "drop") != nil }.count }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let area = lhs.intersection(rhs); return area.isNull ? 0 : area.width * area.height
    }

    /// Reads a field's on-screen frame, in Cocoa coordinates. Geometry only, never contents.
    nonisolated static func frame(of field: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(field, 0.1)
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(field, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 4, dimensions.height > 4 else { return nil }
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: point.x, y: primary - point.y - dimensions.height, width: dimensions.width, height: dimensions.height)
    }
}
