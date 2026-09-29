import AppKit
import S2TCore

@MainActor final class PromptCaptureFeedback {
    private var cards: [CALayer] = []
    private var panel: NSPanel?
    let border = PromptCaptureBorder()
    private let flight = PromptCaptureFlight()
    let drop = PromptCaptureDrop()
    private var visibleFrame = CGRect.zero
    private var frameInterval = 1.0 / 60
    private var pendingSelection: CGRect?
    private var selectionScheduled = false
    private var nextSelectionTime = 0.0
    private var selectionDrawCount = 0
    private var selectionObserver: ((CGRect) -> Void)?
    private var reduceMotionOverride: Bool?
    private var reduceMotion: Bool { reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var selectionGeneration = UUID()
    private var acknowledged: CGRect?
    private var hideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var generation = UUID()
    private let present: Bool
    var suppressPresentation = false
    private(set) var visible = false
    private(set) var collapsed = false
    private(set) var count = 0
    static let cardSize = CGSize(width: 196, height: 140)
    static let margin: CGFloat = 20
    static let cornerRadius: CGFloat = 16

    init(present: Bool = true) { self.present = present }

    func prepare() {
        guard present, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if panel == nil {
            let window = Self.makePanel(); window.setFrame(Self.deckFrame(screen.visibleFrame), display: false); panel = window
        }
        frameInterval = 1 / Double(max(60, min(120, screen.maximumFramesPerSecond)))
        border.prepare()
        flight.prepare()
    }

    /// Starts a ⌘-drag. The event-tap thread then draws the selection through `border`.
    func beginSelection(at point: CGPoint) {
        guard present else { return }
        flashTask?.cancel()
        resetSelection()
        border.begin(at: point, present: !suppressPresentation)
    }

    /// Holds the selection, with its blurred surround, while its pixels are captured. The shutter
    /// plays when the capture arrives in `show`; everything drawn sits outside the captured area.
    func acknowledge(_ rect: CGRect) {
        guard present, rect.width >= 2, rect.height >= 2 else { return }
        acknowledged = rect
        resetSelection()
        drawSelection(rect)
        let id = selectionGeneration
        // If the capture never arrives, still clear the selection.
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self, self.selectionGeneration == id else { return }
            self.acknowledged = nil
            self.release()
        }
    }

    func show(_ screenshot: PromptScreenshot, count: Int) {
        guard present, let screen = NSScreen.screens.max(by: {
            Self.overlap($0.frame, screenshot.region) < Self.overlap($1.frame, screenshot.region)
        }) else { return }
        hideTask?.cancel(); collapseTask?.cancel()
        flight.finish()
        // The capture for a held selection has arrived: play its shutter as the thumbnail leaves.
        if acknowledged.map({ Self.overlap($0, screenshot.region) > 0 }) == true { release() }
        acknowledged = nil
        self.count = count
        visible = true; collapsed = false
        let window = panel ?? Self.makePanel()
        let host = window.contentView ?? Self.host()
        panel = window
        if window.contentView == nil { window.contentView = host }
        visibleFrame = screen.visibleFrame
        frameInterval = 1 / Double(max(60, min(120, screen.maximumFramesPerSecond)))
        let deckFrame = Self.deckFrame(visibleFrame)
        let oldOrigin = window.frame.origin
        if window.frame != deckFrame {
            window.setFrame(deckFrame, display: false)
            for card in cards { card.position.x += oldOrigin.x - deckFrame.minX; card.position.y += oldOrigin.y - deckFrame.minY }
        }
        let size = Self.imageSize(region: screenshot.region)
        let card = Self.makeCard(size: size, image: screenshot.thumbnail, scale: screen.backingScaleFactor)
        host.layer?.addSublayer(card)
        cards.insert(card, at: 0)
        if cards.count > 3 { cards.removeLast().removeFromSuperlayer() }
        if screenshot.thumbnail == nil {
            let id = generation
            Task { [weak self, weak card] in
                let image = await Task.detached(priority: .userInitiated) { PromptScreenshot.thumbnail(from: screenshot.png) }.value
                guard let self, self.generation == id, let card, self.cards.contains(where: { $0 === card }) else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                card.sublayers?.first?.contents = image
                CATransaction.commit()
            }
        }
        for (index, layer) in cards.enumerated() {
            let destination = Self.stackFrame(index: index, visibleFrame: screen.visibleFrame, size: layer.bounds.size)
            let target = CGPoint(x: destination.midX - window.frame.minX, y: destination.midY - window.frame.minY)
            let start = layer.presentation()?.position ?? layer.position
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.position = target
            layer.opacity = index == 0 ? (reduceMotion ? 1 : 0) : (index == 1 ? 0.86 : 0.68)
            layer.zPosition = CGFloat(3 - index)
            layer.transform = CATransform3DMakeScale(1 - CGFloat(index) * 0.045, 1 - CGFloat(index) * 0.045, 1)
            CATransaction.commit()
            if !reduceMotion, index > 0 {
                let movement = CABasicAnimation(keyPath: "position")
                movement.fromValue = NSValue(point: start); movement.toValue = NSValue(point: target)
                movement.duration = 0.28
                movement.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(movement, forKey: "stack")
            }
        }
        if !suppressPresentation, !window.isVisible { window.orderFrontRegardless() }
        if !reduceMotion {
            let destination = Self.stackFrame(index: 0, visibleFrame: visibleFrame, size: size)
            let flyingCard = Self.makeCard(size: size, image: screenshot.thumbnail, scale: screen.backingScaleFactor)
            flight.show(flyingCard, from: CGPoint(x: screenshot.region.midX, y: screenshot.region.midY),
                to: CGPoint(x: destination.midX, y: destination.midY),
                scale: min(1.8, max(1, screenshot.region.width / size.width)),
                present: !suppressPresentation) { [weak card] in
                    CATransaction.begin(); CATransaction.setDisableActions(true)
                    card?.opacity = 1
                    CATransaction.commit()
                }
            if screenshot.thumbnail == nil {
                Task { [weak flyingCard] in
                    let image = await Task.detached(priority: .userInitiated) { PromptScreenshot.thumbnail(from: screenshot.png) }.value
                    flyingCard?.sublayers?.first?.contents = image
                }
            }
        }
        scheduleCollapse()
    }

    /// Sends the deck's screenshots into the prompt field as they are pasted. The deck empties;
    /// the drop finishes on its own, independent of later hide or collapse calls.
    func deliver(into field: CGRect) {
        guard present, visible, let panel, !cards.isEmpty else { return }
        collapseTask?.cancel(); hideTask?.cancel()
        flight.finish()
        let items = cards.map { card -> PromptCaptureDrop.Card in
            let shown = card.presentation() ?? card
            let contents = card.sublayers?.first?.contents
            let image = contents.flatMap { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID ? ($0 as! CGImage) : nil }
            return PromptCaptureDrop.Card(image: image, size: card.bounds.size,
                position: CGPoint(x: shown.position.x + panel.frame.minX, y: shown.position.y + panel.frame.minY),
                scale: max(0.05, sqrt(shown.transform.m11 * shown.transform.m11 + shown.transform.m12 * shown.transform.m12)))
        }
        // The deepest card leaves first so the newest lands last, on top.
        drop.drop(Array(items.reversed()), into: field, present: !suppressPresentation, reducedMotion: reduceMotion)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cards.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
        cards = []
        visible = false; collapsed = false
        panel.orderOut(nil)
    }

    func collapse() {
        collapseTask?.cancel()
        guard visible, let panel else { return }
        flight.finish()
        collapsed = true
        let reduced = reduceMotion
        CATransaction.begin(); CATransaction.setAnimationDuration(reduced ? 0 : 0.28)
        for (index, card) in cards.enumerated() {
            card.removeAllAnimations()
            card.position = CGPoint(x: visibleFrame.minX - panel.frame.minX + 24 + CGFloat(index) * 3,
                y: visibleFrame.minY - panel.frame.minY + 20 + CGFloat(index) * 4)
            card.transform = CATransform3DMakeScale(0.22, 0.22, 1)
            card.opacity = index == 0 ? 0.6 : 0.35
        }
        CATransaction.commit()
    }

    private func scheduleCollapse() {
        let id = generation
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.collapse()
        }
    }

    func selection(_ rect: CGRect?) {
        flashTask?.cancel()
        guard present else { return }
        guard let rect, rect.width >= 2, rect.height >= 2 else { clearSelection(); return }
        pendingSelection = rect
        guard !selectionScheduled else { return }
        let delay = max(0, nextSelectionTime - CACurrentMediaTime())
        if delay == 0 {
            drawSelection(rect)
            return
        }
        selectionScheduled = true
        let id = selectionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.selectionGeneration == id else { return }
            self.selectionScheduled = false
            if let rect = self.pendingSelection { self.drawSelection(rect) }
        }
    }

    private func drawSelection(_ rect: CGRect) {
        let now = CACurrentMediaTime()
        if nextSelectionTime == 0 {
            nextSelectionTime = now + frameInterval
        } else {
            let intervals = max(1, floor((now - nextSelectionTime) / frameInterval) + 1)
            nextSelectionTime += intervals * frameInterval
        }
        selectionDrawCount += 1
        border.show(rect, present: !suppressPresentation)
        selectionObserver?(rect)
    }

    private func release() {
        border.shutter(reducedMotion: reduceMotion)
        let id = selectionGeneration
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((PromptCaptureBorder.fadeDuration + 0.06) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.selectionGeneration == id else { return }
            self.clearSelection()
        }
    }

    func hide() {
        generation = UUID()
        hideTask?.cancel(); collapseTask?.cancel(); flashTask?.cancel()
        flight.finish(reveal: false)
        acknowledged = nil
        visible = false; collapsed = false; count = 0
        cards.forEach { $0.removeFromSuperlayer() }; cards = []
        panel?.orderOut(nil)
        clearSelection()
    }
    func reset() { hide() }
    func hideSoon() {
        hideTask?.cancel()
        collapse()
        let id = generation
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.hide()
        }
    }

    private func resetSelection() {
        flashTask?.cancel()
        selectionGeneration = UUID(); selectionScheduled = false; pendingSelection = nil
        nextSelectionTime = 0
    }
    private func clearSelection() {
        resetSelection()
        border.hide()
    }
    private static func host() -> NSView {
        let host = PromptCaptureHostView(frame: .zero)
        host.layer = CALayer(); host.wantsLayer = true
        host.layer?.masksToBounds = true
        host.layerContentsRedrawPolicy = .never
        host.autoresizingMask = [.width, .height]
        return host
    }
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        BackdropWindowHosting.configure(panel)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false
        panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false; panel.sharingType = .none
        panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host()
        BackdropWindowHosting.configure(panel)
        // These panels draw images and strokes, with no backdrop sampler to keep alive.
        panel.backgroundColor = .clear
        return panel
    }
    static func makeCard(size: CGSize, image: CGImage?, scale: CGFloat) -> CALayer {
        let card = CALayer(); card.bounds = CGRect(origin: .zero, size: size)
        card.shadowColor = NSColor.black.cgColor; card.shadowOpacity = 0.28; card.shadowRadius = 12; card.shadowOffset = CGSize(width: 0, height: -4)
        card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        let photo = CALayer(); photo.frame = card.bounds; photo.contents = image; photo.contentsGravity = .resizeAspect
        photo.cornerRadius = cornerRadius; photo.cornerCurve = .continuous; photo.masksToBounds = true
        card.addSublayer(photo)
        let highlight = CAGradientLayer(); highlight.frame = card.bounds
        highlight.colors = [NSColor.white.withAlphaComponent(0.7).cgColor, NSColor.white.withAlphaComponent(0.12).cgColor, NSColor.white.withAlphaComponent(0.3).cgColor]
        highlight.startPoint = CGPoint(x: 0, y: 1); highlight.endPoint = CGPoint(x: 1, y: 0)
        let rim = CAShapeLayer(); rim.frame = card.bounds; rim.fillColor = nil; rim.strokeColor = NSColor.white.cgColor; rim.lineWidth = 1
        rim.path = CGPath(roundedRect: card.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        highlight.mask = rim; card.addSublayer(highlight)
        card.shouldRasterize = true; card.rasterizationScale = scale
        return card
    }
    private static func deckFrame(_ visible: CGRect) -> CGRect {
        CGRect(x: visible.minX + margin - 24, y: visible.minY + margin - 24,
            width: cardSize.width + 18 + 48, height: cardSize.height + 26 + 48)
    }
    static func imageSize(region: CGRect) -> CGSize {
        let scale = min(cardSize.width / max(1, region.width), cardSize.height / max(1, region.height))
        return CGSize(width: max(1, region.width * scale), height: max(1, region.height * scale))
    }
    static func stackFrame(index: Int, visibleFrame: CGRect, size: CGSize = CGSize(width: 196, height: 140)) -> CGRect {
        CGRect(x: visibleFrame.minX + margin + CGFloat(index) * 9, y: visibleFrame.minY + margin + CGFloat(index) * 13, width: size.width, height: size.height)
    }
    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let rect = lhs.intersection(rhs); return rect.isNull ? 0 : rect.width * rect.height
    }

    static func benchmark(_ screenshot: PromptScreenshot) {
        let feedback = PromptCaptureFeedback(); feedback.suppressPresentation = true
        let setup = ProcessInfo.processInfo.systemUptime
        feedback.prepare()
        let setupTime = (ProcessInfo.processInfo.systemUptime - setup) * 1000
        var times: [Double] = []
        for index in 1...12 {
            let start = ProcessInfo.processInfo.systemUptime
            feedback.show(screenshot, count: index)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        feedback.hide()
        print(String(format: "Hidden deck setup %.2f ms; capture UI work median %.2f ms, max %.2f ms. Compact windows keep backing buffers bounded; this is not displayed FPS.", setupTime, times.sorted()[6], times.max()!))
    }

    static func benchmarkSelectionLatency() async throws {
        for frequency in [60, 120] {
            let feedback = PromptCaptureFeedback()
            feedback.suppressPresentation = true
            feedback.prepare()
            feedback.frameInterval = 1 / Double(frequency)
            defer { feedback.hide() }
            var submitted: [Int: Double] = [:]
            var delays: [Double] = []
            feedback.selectionObserver = { rect in
                if let time = submitted[Int(rect.minX)] { delays.append((CACurrentMediaTime() - time) * 1000) }
            }
            let start = CACurrentMediaTime()
            for index in 0..<90 {
                let due = start + Double(index) / Double(frequency)
                let remaining = due - CACurrentMediaTime()
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                submitted[index] = CACurrentMediaTime()
                feedback.selection(CGRect(x: index, y: 50, width: 200 + index, height: 140))
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            guard feedback.border.rect?.minX == 89, !delays.isEmpty else { throw ServiceError.message("Selector lost the latest pointer position") }
            delays.sort()
            print(String(format: "%d Hz selection requests: %d layer updates; event-to-layer median %.3f ms, p95 %.3f ms, max %.3f ms",
                frequency, delays.count, delays[delays.count / 2], delays[min(delays.count - 1, Int(Double(delays.count) * 0.95))], delays.last!))
        }
        print("Hidden selector, synthetic pointer positions and native layer updates only. No screen capture or posted events; not displayed FPS.")
    }

    static func verify() async throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 160, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 120, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let screenshot = PromptScreenshot(png: bitmap.representation(using: .png, properties: [:])!, pointer: .zero,
            region: CGRect(x: 10, y: 20, width: 200, height: 150), thumbnail: bitmap.cgImage)
        let feedback = PromptCaptureFeedback(); feedback.suppressPresentation = true
        feedback.reduceMotionOverride = false
        defer { feedback.hide() }
        for index in 1...12 { feedback.show(screenshot, count: index) }
        guard feedback.cards.count == 3, feedback.visible, feedback.count == 12,
              let panel = feedback.panel, !panel.isVisible, panel.ignoresMouseEvents, panel.styleMask.contains(.nonactivatingPanel),
              panel.contentView?.subviews.isEmpty == true else { throw ServiceError.message("Image-only hidden deck metadata failed.") }
        for card in feedback.cards {
            guard card.superlayer === panel.contentView?.layer, card.shadowPath != nil, card.shouldRasterize, let image = card.sublayers?.first,
                  image.masksToBounds, image.cornerRadius == 16, image.contents != nil else { throw ServiceError.message("Rounded image, prepared thumbnail or cached shadow missing.") }
        }
        let deckLanding = stackFrame(index: 0, visibleFrame: feedback.visibleFrame, size: imageSize(region: screenshot.region))
        // One window cannot span displays; the flight covers exactly the deck's screen.
        let screens = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: deckLanding.midX, y: deckLanding.midY)) })?.frame ?? .null
        guard panel.frame.width <= 300, panel.frame.height <= 250,
              let flying = feedback.flight.panel, feedback.flight.active, !flying.isVisible,
              flying.frame == screens, flying.ignoresMouseEvents, flying.styleMask.contains(.nonactivatingPanel),
              let motion = feedback.flight.motion, motion.duration == PromptCaptureFlight.duration else {
            throw ServiceError.message("Screenshot deck must stay compact; the flight needs a stationary click-through panel with a render-server animation")
        }
        let landing = stackFrame(index: 0, visibleFrame: feedback.visibleFrame, size: imageSize(region: screenshot.region))
        let origin = CGPoint(x: screenshot.region.midX - flying.frame.minX, y: screenshot.region.midY - flying.frame.minY)
        guard abs(motion.from.x - origin.x) < 0.5, abs(motion.from.y - origin.y) < 0.5,
              abs(motion.to.x - (landing.midX - flying.frame.minX)) < 0.5, abs(motion.to.y - (landing.midY - flying.frame.minY)) < 0.5 else {
            throw ServiceError.message("Flight does not travel from the capture to the deck")
        }
        let showStart = CACurrentMediaTime()
        feedback.show(screenshot, count: 12)
        let showTime = (CACurrentMediaTime() - showStart) * 1000
        guard flying.frame == screens, feedback.flight.active else { throw ServiceError.message("A new flight moved or resized its window") }
        print(String(format: "Flight: one Core Animation path in a stationary %.0f × %.0f point panel; starting a capture's UI takes %.3f ms on the main thread, with no per-frame window moves.",
            screens.width, screens.height, showTime))
        feedback.flight.finish()
        guard !feedback.flight.active, feedback.cards[0].opacity == 1, flying.contentView?.layer?.sublayers?.isEmpty != false else {
            throw ServiceError.message("Flight did not land in the deck")
        }
        let frame = panel.frame
        feedback.selection(nil)
        feedback.selectionDrawCount = 0
        for x in 0..<120 { feedback.selection(CGRect(x: x, y: 50, width: 100 + x, height: 90)) }
        guard feedback.border.rect?.minX == 0, feedback.selectionDrawCount == 1 else {
            throw ServiceError.message("The first selection movement must appear immediately without drawing the entire burst")
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        guard feedback.selectionDrawCount == 2, feedback.border.rect?.minX == 119,
              feedback.border.panels.allSatisfy({ !$0.isVisible }), panel.frame == frame else {
            throw ServiceError.message("Selector did not present the latest coalesced pointer position.")
        }
        feedback.selection(CGRect(x: 400, y: 50, width: 300, height: 90))
        feedback.selection(CGRect(x: 401, y: 50, width: 300, height: 90))
        feedback.selection(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard feedback.border.rect == nil else { throw ServiceError.message("A queued movement restored a dismissed selection") }
        feedback.selection(CGRect(x: 500, y: 50, width: 300, height: 90))
        guard feedback.border.rect?.minX == 500 else { throw ServiceError.message("A new gesture inherited the previous gesture's delay") }
        feedback.selection(nil)
        let dragging = CGRect(x: 200, y: 200, width: 250, height: 180)
        feedback.selection(dragging)
        feedback.show(screenshot, count: 13)
        guard feedback.border.rect == dragging else { throw ServiceError.message("A finishing screenshot displaced the active selection") }
        feedback.selection(nil)
        feedback.collapse()
        guard feedback.collapsed, feedback.cards.allSatisfy({ abs($0.transform.m11 - 0.22) < 0.001 }) else { throw ServiceError.message("Deck did not minimize.") }
        feedback.hideSoon(); feedback.reset(); feedback.show(screenshot, count: 1)
        guard !feedback.collapsed, feedback.cards.count == 1 else { throw ServiceError.message("Deck restart kept old state.") }
        try await Task.sleep(nanoseconds: 2_100_000_000)
        guard feedback.visible, feedback.collapsed, feedback.cards.count == 1 else { throw ServiceError.message("A stale hide removed a restarted deck.") }
        // A held capture keeps its blurred selection until the pixels arrive, then plays its shutter.
        let held = CGRect(x: 10, y: 20, width: 200, height: 150)
        feedback.acknowledge(held)
        let overlay = feedback.border.panels.first?.contentView?.layer?.sublayers?.first
        guard feedback.border.rect == held, overlay?.opacity == 1 else { throw ServiceError.message("A requested capture did not hold its selection") }
        feedback.show(screenshot, count: 2)
        // Hidden windows finish animations at once; the model opacity proves the fade ends hidden.
        guard overlay?.opacity == 0 else { throw ServiceError.message("The shutter did not start when the captured pixels arrived") }
        // Delivery drops every deck card into the field and empties the deck.
        let cardCount = feedback.cards.count
        let field = CGRect(x: 400, y: 300, width: 520, height: 56)
        feedback.deliver(into: field)
        guard feedback.cards.isEmpty, !feedback.visible, feedback.drop.active, feedback.drop.cardCount == cardCount,
              let dropScreen = NSScreen.screens.first(where: { $0.frame.intersects(field) }), feedback.drop.panel?.frame == dropScreen.frame,
              feedback.drop.panel?.ignoresMouseEvents == true, feedback.drop.panel?.isVisible == false else {
            throw ServiceError.message("Screenshots did not drop into the prompt field")
        }
        feedback.hide()
        guard feedback.drop.active else { throw ServiceError.message("Hiding the deck cut the drop short") }
        feedback.drop.finish()
        feedback.show(screenshot, count: 1)
        feedback.reduceMotionOverride = true
        feedback.show(screenshot, count: 2)
        guard !feedback.flight.active, feedback.cards[0].animationKeys()?.isEmpty != false else { throw ServiceError.message("Reduce Motion animated a screenshot.") }
        for bounds in [CGRect(x: 0, y: 30, width: 1440, height: 850), CGRect(x: -1920, y: 900, width: 1920, height: 1040)] {
            guard bounds.contains(stackFrame(index: 2, visibleFrame: bounds)) else { throw ServiceError.message("Deck escaped display bounds.") }
        }
        print("Capture deck: rounded image-only cards, highlight, cached shadow, fixed-size flight, compact hidden windows, 120 selection updates, collapse and restart PASS. No screen capture.")
    }
}

private final class PromptCaptureHostView: NSView {
    @objc private func _shouldAutoFlattenLayerTree() -> Bool { false }
}
