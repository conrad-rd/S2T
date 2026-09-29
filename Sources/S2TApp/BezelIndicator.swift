import AppKit
import S2TCore

enum BezelSymbol: Equatable {
    case waveform, spinner, checkmark, failure

    static func resolve(phase: DictationPhase, waiting: Bool, deliveryHint: String?) -> Self {
        if waiting || phase.processingAudio { return .spinner }
        if phase == .failed || (phase == .complete && deliveryHint != nil) { return .failure }
        return phase == .complete ? .checkmark : .waveform
    }
}

private final class BezelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class BezelWindowController {
    private let state: AppState
    private let presentsWindows: Bool
    private(set) var panel: NSPanel?
    private(set) var indicator: BezelIndicatorView?
    private(set) var backdrop: ProgressiveBackdropView?
    private var timer: Timer?
    private var motion = BezelMotion()
    private var previewStarted: Double?

    init(state: AppState, presentsWindows: Bool = true) {
        self.state = state
        self.presentsWindows = presentsWindows
    }

    @discardableResult
    func prepareWindow(screens: [NSScreen], pointer: CGPoint) -> NSPanel? {
        guard let index = GlowDisplay.preferredIndex(in: screens.map { GlowDisplay(screen: $0) }, pointer: pointer) else { return nil }
        let frame = BezelGeometry.frame(screen: screens[index].frame, side: state.bezelSide, verticalPosition: state.bezelVerticalPosition)
        if panel == nil {
            let panel = BezelPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            BackdropWindowHosting.configure(panel)
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let indicator = BezelIndicatorView(frame: CGRect(origin: .zero, size: frame.size))
            indicator.wantsLayer = true
            indicator.autoresizingMask = [.width, .height]
            let backdrop = ProgressiveBackdropView(frame: indicator.frame)
            backdrop.addSubview(indicator)
            panel.contentView = backdrop
            self.backdrop = backdrop
            self.indicator = indicator
            self.panel = panel
        }
        indicator?.side = state.bezelSide
        if panel?.frame != frame { panel?.setFrame(frame, display: false) }
        return panel
    }

    func show(screens: [NSScreen], pointer: CGPoint) {
        guard let panel = prepareWindow(screens: screens, pointer: pointer) else { hide(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if !motion.isVisible { previewStarted = state.phase == .preview ? now : nil }
        motion.setVisible(true, at: now, reducedMotion: reducedMotion)
        tick(at: now)
        if presentsWindows && !panel.isVisible { panel.orderFrontRegardless() }
        startTimer()
    }

    func hide() {
        guard motion.isVisible else { return }
        motion.setVisible(false, at: ProcessInfo.processInfo.systemUptime, reducedMotion: reducedMotion)
        startTimer()
    }

    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(at: ProcessInfo.processInfo.systemUptime) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func tick(at time: Double) {
        guard let indicator else { return }
        let form = motion.form(at: time, reducedMotion: reducedMotion)
        var symbol = BezelSymbol.resolve(phase: state.phase, waiting: state.isWaitingToPaste, deliveryHint: state.pasteHint)
        if state.phase == .preview {
            if previewStarted == nil { previewStarted = time }
            let elapsed = time - (previewStarted ?? time)
            symbol = elapsed < 3.6 ? .waveform : elapsed < 5.1 ? .spinner : .checkmark
        } else {
            previewStarted = nil
        }
        indicator.update(form: form, symbol: symbol, level: state.glowLevel, spectrum: state.speechSpectrum, time: time, reducedMotion: reducedMotion)
        updateBackdrop(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        if !motion.isVisible && form == .hidden {
            panel?.orderOut(nil)
            timer?.invalidate()
            timer = nil
        }
    }

    func updateBackdrop(reduceTransparency: Bool) {
        guard let indicator, let backdrop else { return }
        guard !reduceTransparency, indicator.form.depth > 0 else {
            if backdrop.profile != nil { backdrop.profile = nil }
            return
        }
        let strength = min(1, max(0, min(indicator.form.depth, indicator.form.body)))
        backdrop.apply(profile: GlowProfile(energy: strength, heights: [],
            bezel: BezelBackdrop(path: indicator.displayedShape.path)), radiusMap: nil)
    }

    deinit { timer?.invalidate() }
}

@MainActor final class BezelIndicatorView: NSView {
    var dragVelocity = CGVector.zero { didSet { needsDisplay = true } }
    var previewShape: BezelShape? { didSet { needsDisplay = true } }
    var side = BezelSide.right { didSet { needsDisplay = true } }
    private(set) var form = BezelForm.hidden
    private(set) var symbol = BezelSymbol.waveform
    private var level = 0.0
    private(set) var bands = Array(repeating: 0.0, count: AudioSpectrum.bandCount)
    private var tilt = 0.0
    private var tiltVelocity = 0.0
    private var time = 0.0
    private var reducedMotion = false
    private var lastTime: Double?
    override var isFlipped: Bool { true }

    func update(form: BezelForm, symbol: BezelSymbol, level: Double, spectrum: [Double], time: Double, reducedMotion: Bool) {
        let delta = min(0.1, max(0, time - (lastTime ?? time)))
        let incoming = min(1, max(0, level))
        self.level += (incoming - self.level) * (1 - exp(-delta / (incoming > self.level ? 0.045 : 0.12)))
        for index in bands.indices {
            let energy = min(1, max(0, spectrum[index]))
            let response = energy > bands[index] ? 0.025 : 0.085
            bands[index] += (energy - bands[index]) * (1 - exp(-delta / response))
        }
        let targetTilt = reducedMotion || symbol != .waveform ? 0 :
            (bands[0] + bands[1]) / 2 - (bands[4] + bands[5] + bands[6]) / 3
        let steps = max(1, Int(ceil(delta * 120)))
        let dt = delta / Double(steps)
        for _ in 0..<steps {
            tiltVelocity += (targetTilt - tilt) * 140 * dt
            tiltVelocity *= exp(-10 * dt)
            tilt += tiltVelocity * dt
        }
        lastTime = time
        self.form = form
        self.symbol = symbol
        self.time = time
        self.reducedMotion = reducedMotion
        needsDisplay = true
    }

    var displayedShape: BezelShape {
        previewShape ?? BezelGeometry.shape(form: form, side: side,
            level: reducedMotion || symbol != .waveform ? 0 : level, tilt: reducedMotion ? 0 : tilt)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        guard form.depth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        let shape = displayedShape
        let contour = shape.path
        context.saveGState()
        context.setShadow(offset: CGSize(width: side == .left ? 0.5 : -0.5, height: -1), blur: 10,
            color: NSColor.black.withAlphaComponent(0.09 * min(1, form.depth)).cgColor)
        context.addPath(contour)
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()
        context.addPath(contour)
        context.clip()
        let center = shape.symbolCenter
        context.translateBy(x: center.x, y: center.y)
        context.setAlpha(min(1, max(0, (min(form.depth, form.body) - 0.55) / 0.45)))
        let speed = reducedMotion ? 0 : min(1, hypot(dragVelocity.dx, dragVelocity.dy) / 1000)
        if previewShape != nil, speed > 0.04 {
            drawBlurredSymbol(in: context, speed: speed)
        } else { drawSymbol(in: context) }
    }

    private func drawBlurredSymbol(in context: CGContext, speed: Double) {
        let magnitude = hypot(dragVelocity.dx, dragVelocity.dy)
        let direction = CGVector(dx: dragVelocity.dx / magnitude, dy: dragVelocity.dy / magnitude)
        let opacity = min(1, max(0, (min(form.depth, form.body) - 0.55) / 0.45))
        context.saveGState()
        context.setBlendMode(.plusLighter)
        for along in -7...7 {
            let travel = Double(along) / 7 * speed * 11
            for across in -2...2 {
                let softness = Double(across) * speed * 1.2
                let weight = exp(-Double(across * across) / 2) / (15 * 2.4837318859)
                context.saveGState()
                context.translateBy(x: direction.dx * travel - direction.dy * softness,
                                    y: direction.dy * travel + direction.dx * softness)
                context.setAlpha(opacity * weight)
                drawSymbol(in: context)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    private func drawSymbol(in context: CGContext) {
        context.setStrokeColor(NSColor.white.cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(2.3)
        switch symbol {
        case .waveform:
            for index in 0..<7 {
                let length = BezelGeometry.barLength(energy: bands[index])
                let y = Double(index - 3) * 5
                context.move(to: CGPoint(x: -length / 2, y: y))
                context.addLine(to: CGPoint(x: length / 2, y: y))
                context.strokePath()
            }
        case .spinner:
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
            context.strokeEllipse(in: CGRect(x: -8, y: -8, width: 16, height: 16))
            context.setStrokeColor(NSColor.white.cgColor)
            let angle = reducedMotion ? -.pi / 2 : time.truncatingRemainder(dividingBy: 0.9) / 0.9 * .pi * 2
            context.addArc(center: .zero, radius: 8, startAngle: angle, endAngle: angle + .pi * 1.25, clockwise: false)
            context.strokePath()
        case .checkmark:
            context.move(to: CGPoint(x: -8.5, y: 0))
            context.addLine(to: CGPoint(x: -2.5, y: 6))
            context.addLine(to: CGPoint(x: 8.5, y: -6))
            context.strokePath()
        case .failure:
            context.move(to: CGPoint(x: 0, y: -8))
            context.addLine(to: CGPoint(x: 0, y: 2))
            context.strokePath()
            context.fillEllipse(in: CGRect(x: -1.3, y: 6, width: 2.6, height: 2.6))
        }
    }
}
