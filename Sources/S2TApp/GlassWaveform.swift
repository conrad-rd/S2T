import AppKit
import SwiftUI
import S2TCore

/// Screenshot reference: a dark glass body and seven softly rounded white bars.
/// The desktop is composed by AppKit; no exported background or captured pixels are used.
@MainActor final class GlassWaveformView: NSView {
    static let size = CGSize(width: 132, height: 96)
    static let bodyInsetY: CGFloat = 30
    var bodyRect: CGRect { CGRect(x: bounds.midX - 56, y: bounds.midY - 18, width: 112, height: 36) }
    private(set) var glass: NSView?
    private var body: NSView?
    private let ink = GlassWaveformInk()
    /// Sits beneath the glass, so the glass refracts the fade and keeps its rim highlights on top.
    private let fade = GlassCapsuleArtwork.makeFadeLayer()
    private var motion = GlassWaveformMotion()
    private(set) var animation = GlassCapsuleAnimation()
    let dropShadow = CALayer()
    var cancelButton: GlassCancelButton { ink.cancelButton }
    var onCancel: (() -> Void)? {
        get { ink.cancelButton.onCancel }
        set { ink.cancelButton.onCancel = newValue }
    }
    var allowsCancellation: Bool { animation.phase == .listening || animation.phase == .processing }
    var animatedBodyRect: CGRect {
        CGRect(x: bodyRect.midX - bodyRect.width * animation.scaleX / 2,
            y: bodyRect.midY + animation.offsetY - bodyRect.height * animation.scaleY / 2,
            width: bodyRect.width * animation.scaleX, height: bodyRect.height * animation.scaleY)
    }
    var cancelFrame: CGRect {
        let center = CGPoint(x: bodyRect.midX + (18 - bodyRect.width / 2) * animation.scaleX,
            y: bodyRect.midY + animation.offsetY)
        return CGRect(x: center.x - 12 * animation.scaleX, y: center.y - 12 * animation.scaleY,
            width: 24 * animation.scaleX, height: 24 * animation.scaleY)
    }
    func restart() { animation = GlassCapsuleAnimation(); lastTime = nil }
    static let cornerRadius: CGFloat = 18
    var waveformView: NSView { ink.waveform }
    var materialContent: NSView { ink }
    var processingGradient: GlowGradient { ink.gradient }
    private(set) var bands = Array(repeating: 0.0, count: 7)
    private var lastTime: Double?
    private var reducesTransparency: Bool?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dropShadow.frame = bodyRect
        dropShadow.shadowPath = GlassCapsuleArtwork.path(in: CGRect(origin: .zero, size: bodyRect.size))
        dropShadow.shadowColor = NSColor.black.cgColor
        dropShadow.shadowOpacity = 0.14
        dropShadow.shadowRadius = 4
        dropShadow.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(dropShadow)
        setAccessibilityLabel("Classic dictation indicator")
    }
    required init?(coder: NSCoder) { nil }

    func update(spectrum: [Double], symbol: BezelSymbol, time: Double,
                reducedMotion: Bool, reducedTransparency: Bool, gradient: GlowGradient = .init()) {
        if reducesTransparency != reducedTransparency {
            ink.removeFromSuperview()
            body?.removeFromSuperview()
            let body = NSView(frame: bodyRect)
            body.wantsLayer = true
            let mask = CAShapeLayer()
            mask.path = GlassCapsuleArtwork.path(in: body.bounds)
            body.layer?.mask = mask
            ink.frame = body.bounds
            ink.autoresizingMask = [.width, .height]
            let surface: NSView
            if !reducedTransparency, #available(macOS 26.0, *) {
                let effect = NSGlassEffectView(frame: body.bounds)
                effect.style = .clear
                effect.cornerRadius = Self.cornerRadius
                effect.tintColor = nil
                effect.appearance = NSAppearance(named: .darkAqua)
                effect.contentView = ink
                LiquidGlassLens.apply(to: effect)
                surface = effect
            } else {
                let fallback = NSView(frame: body.bounds)
                fallback.wantsLayer = true
                fallback.layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.065, blue: 0.09, alpha: 1).cgColor
                fallback.layer?.cornerRadius = Self.cornerRadius
                fallback.layer?.cornerCurve = .circular
                fallback.addSubview(ink)
                surface = fallback
            }
            body.addSubview(surface)
            fade.removeFromSuperlayer()
            body.layer?.insertSublayer(fade, at: 0)
            addSubview(body)
            self.body = body
            glass = surface
            reducesTransparency = reducedTransparency
        }
        if let body, let glass {
            body.layer?.transform = CATransform3DIdentity
            body.frame = bodyRect
            body.bounds = CGRect(origin: .zero, size: bodyRect.size)
            (body.layer?.mask as? CAShapeLayer)?.path = GlassCapsuleArtwork.path(in: body.bounds)
            glass.frame = body.bounds
            if #available(macOS 26, *), let effect = glass as? NSGlassEffectView {
                effect.cornerRadius = Self.cornerRadius
                LiquidGlassLens.apply(to: effect)
            }
            ink.classicAmount = 0
            ink.classicCenter = nil
            ink.classicBody = nil
            fade.frame = body.bounds
            ink.glyphRotation = 0
        }
        let delta = min(0.1, max(0, time - (lastTime ?? time - 1.0 / 60)))
        lastTime = time
        motion.update(bands: symbol == .waveform ? spectrum : [], delta: delta, reducedMotion: reducedMotion)
        bands = motion.values.map { min(1, max(0, $0)) }
        ink.waveform.motion = motion
        ink.waveform.needsDisplay = true
        let phase: GlassCapsulePhase
        switch symbol {
        case .waveform: phase = .listening
        case .spinner: phase = .processing
        case .checkmark: phase = .success
        case .failure: phase = .failure
        }
        animation.update(phase: phase, energy: bands.reduce(0, +) / 7, time: time, reducedMotion: reducedMotion)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let position = CGPoint(x: bodyRect.midX, y: bodyRect.midY + animation.offsetY)
        body?.layer?.position = position
        dropShadow.position = position
        let transform = CATransform3DMakeScale(animation.scaleX, animation.scaleY, 1)
        body?.layer?.transform = transform
        dropShadow.transform = transform
        CATransaction.commit()
        ink.update(animation: animation, time: time, reducedMotion: reducedMotion, gradient: gradient)
    }
    /// `body` is the capsule part of `shape` (flipped coordinates); the glyph turns by `rotation` radians while docking.
    func applyClassicShape(_ shape: BezelShape, body bodyShape: CGRect, amount: Double, rotation: Double) {
        guard let body, let glass else { return }
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        let path = shape.path.copy(using: &flip)!
        let rect = path.boundingBoxOfPath
        var translation = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        let local = path.copy(using: &translation)!
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.layer?.transform = CATransform3DIdentity
        body.frame = rect
        body.bounds = CGRect(origin: .zero, size: rect.size)
        (body.layer?.mask as? CAShapeLayer)?.path = local
        glass.frame = body.bounds
        if #available(macOS 26, *), let effect = glass as? NSGlassEffectView {
            effect.cornerRadius = Self.cornerRadius * (1 - amount)
            LiquidGlassLens.apply(to: effect)
        }
        ink.classicAmount = amount
        ink.classicCenter = CGPoint(x: shape.symbolCenter.x - rect.minX,
            y: bounds.height - shape.symbolCenter.y - rect.minY)
        ink.classicBody = CGRect(x: bodyShape.minX - rect.minX, y: bounds.height - bodyShape.maxY - rect.minY,
            width: bodyShape.width, height: bodyShape.height)
        fade.frame = ink.classicBody ?? body.bounds
        ink.glyphRotation = rotation
        ink.needsLayout = true
        ink.needsDisplay = true
        dropShadow.transform = CATransform3DIdentity
        dropShadow.bounds = CGRect(origin: .zero, size: rect.size)
        dropShadow.position = CGPoint(x: rect.midX, y: rect.midY)
        dropShadow.shadowPath = local
        CATransaction.commit()
    }

}

@MainActor private final class GlassWaveformInk: NSView {
    let waveform = GlassWaveformDrawing()
    let cancelButton = GlassCancelButton(frame: CGRect(x: 6, y: 6, width: 24, height: 24))
    private var animation = GlassCapsuleAnimation()
    private var time = 0.0
    private var reducedMotion = false
    private var contentOffset = 12.0
    private var cancelVisibility = 1.0
    var classicAmount = 0.0
    var classicCenter: CGPoint?
    var classicBody: CGRect?
    var glyphRotation = 0.0 { didSet { waveform.rotation = glyphRotation } }
    private(set) var gradient = GlowGradient()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(waveform)
        addSubview(cancelButton)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        let center = classicCenter ?? CGPoint(x: bounds.midX + contentOffset, y: bounds.midY)
        waveform.frame = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
        cancelButton.alphaValue = cancelVisibility * max(0, 1 - classicAmount * 5)
    }
    func update(animation: GlassCapsuleAnimation, time: Double, reducedMotion: Bool, gradient: GlowGradient) {
        self.gradient = gradient
        self.animation = animation
        self.time = time
        self.reducedMotion = reducedMotion
        func cancellable(_ phase: GlassCapsulePhase) -> Double { phase == .listening || phase == .processing ? 1 : 0 }
        let cancelOpacity = cancellable(animation.previousPhase) * (1 - animation.blend) + cancellable(animation.phase) * animation.blend
        cancelVisibility = cancelOpacity
        contentOffset = 12 * cancelOpacity
        cancelButton.alphaValue = cancelOpacity
        cancelButton.isHidden = cancelOpacity == 0
        cancelButton.isEnabled = cancellable(animation.phase) == 1
        waveform.alphaValue = animation.phase == .listening ? (animation.previousPhase == .listening ? 1 : animation.blend)
            : animation.previousPhase == .listening ? 1 - animation.blend : 0
        waveform.isHidden = waveform.alphaValue == 0
        needsLayout = true
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Past the midpoint the body is already sinking into the Bezel's solid black.
        let darkening = min(1, max(0, (classicAmount - 0.05) / 0.55))
        GlassCapsuleArtwork.drawDarkening(in: bounds, amount: darkening * darkening * (3 - 2 * darkening), context: context)
        let center = classicCenter ?? CGPoint(x: bounds.midX + contentOffset, y: bounds.midY)
        func draw(_ phase: GlassCapsulePhase, opacity: Double) {
            guard opacity > 0 else { return }
            context.saveGState()
            context.setAlpha(opacity)
            switch phase {
            case .listening: break
            case .processing:
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: glyphRotation)
                context.translateBy(x: -center.x, y: -center.y)
                GlassCapsuleArtwork.drawProcessing(in: bounds, time: time, center: center,
                    reducedMotion: reducedMotion, context: context)
            case .success:
                GlassCapsuleArtwork.drawSuccess(center: center, elapsed: animation.elapsed, reducedMotion: reducedMotion, context: context)
            case .failure:
                context.setStrokeColor(CGColor(gray: 1, alpha: 1))
                context.setLineWidth(1.8)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: center.x - 4, y: center.y - 4))
                context.addLine(to: CGPoint(x: center.x + 4, y: center.y + 4))
                context.move(to: CGPoint(x: center.x - 4, y: center.y + 4))
                context.addLine(to: CGPoint(x: center.x + 4, y: center.y - 4))
                context.strokePath()
            }
            context.restoreGState()
        }
        if animation.previousPhase != animation.phase { draw(animation.previousPhase, opacity: 1 - animation.blend) }
        draw(animation.phase, opacity: animation.previousPhase == animation.phase ? 1 : animation.blend)
    }
}

@MainActor private final class GlassWaveformDrawing: NSView {
    var motion = GlassWaveformMotion()
    var rotation = 0.0 { didSet { if rotation != oldValue { needsDisplay = true } } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: rotation)
        context.scaleBy(x: 0.4, y: 0.4)
        for index in 0..<7 {
            context.addPath(motion.bar(at: index).path(center: CGPoint(x: Double(index - 3) * 12.5417, y: 0)))
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()
    }
}

@MainActor final class GlassWaveformController {
    private let state: AppState
    private let presentsWindows: Bool
    private(set) var panel: NSPanel?
    private(set) var classicIndicator: ClassicIndicatorView?
    var indicator: GlassWaveformView? { classicIndicator?.glass }
    private(set) var interactionPanel: GlassInteractionPanel?
    private var backdrop: ProgressiveBackdropView?
    private var visibility: OverlayVisibility?
    private var timer: Timer?
    private var previewStarted: Double?
    private let placement: GlassCapsulePlacementStore
    private var placementScreens: [NSScreen] = []
    private var placedScreen: NSScreen?
    private var restingCenter = CGPoint.zero
    private var drag: GlassCapsuleDrag?
    private(set) var dockedSide: BezelSide?

    init(state: AppState, presentsWindows: Bool = true, placement: GlassCapsulePlacementStore? = nil) {
        self.state = state
        self.presentsWindows = presentsWindows
        self.placement = placement ?? GlassCapsulePlacementStore(
            read: { state.classicAnchor.flatMap { try? JSONEncoder().encode($0) } },
            write: { state.classicAnchor = try? JSONDecoder().decode(GlassCapsuleAnchor.self, from: $0) })
    }
    @discardableResult func prepareWindow(screens: [NSScreen], pointer: CGPoint) -> NSPanel? {
        placementScreens = screens
        if drag != nil { return panel }
        let anchor = placement.anchor
        dockedSide = anchor?.side
        let pinned = anchor.flatMap { anchor in screens.firstIndex { GlassCapsulePlacementStore.identifier(for: $0) == anchor.displayID } }
        guard let index = pinned ?? GlowDisplay.preferredIndex(in: screens.map { GlowDisplay(screen: $0) }, pointer: pointer) else { return nil }
        let screen = screens[index]
        placedScreen = screen
        restingCenter = anchor?.center(in: screen.visibleFrame, screenMidX: screen.frame.midX)
            ?? CGPoint(x: screen.frame.midX, y: screen.visibleFrame.minY + 50)
        if panel == nil {
            let frame = ClassicIndicatorView.frame(center: restingCenter, screen: screen.frame)
            let panel = BackdropWindowHosting.makePanel()
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.setFrame(frame, display: false)
            let backdrop = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: frame.size))
            let indicator = ClassicIndicatorView()
            indicator.frame = backdrop.bounds
            indicator.autoresizingMask = [.width, .height]
            backdrop.addSubview(indicator)
            panel.contentView = backdrop
            indicator.glass.onCancel = { [weak self] in
                guard let self, self.state.canCancel else { return }
                self.state.cancel()
                self.hide()
            }
            let interactionPanel = GlassInteractionPanel()
            interactionPanel.button.onCancel = { [weak indicator] in indicator?.glass.cancelButton.performClick(nil) }
            interactionPanel.interaction.onBegin = { [weak self] in self?.beginDrag(at: $0) }
            interactionPanel.interaction.onDrag = { [weak self] in self?.moveDrag(to: $0) }
            interactionPanel.interaction.onEnd = { [weak self] in self?.endDrag(at: $0) }
            self.interactionPanel = interactionPanel
            self.classicIndicator = indicator
            self.backdrop = backdrop
            self.panel = panel
            visibility = OverlayVisibility(panel: panel, appearanceDuration: 0.08)
        }
        render(at: ProcessInfo.processInfo.systemUptime)
        return panel
    }
    func show(screens: [NSScreen], pointer: CGPoint) {
        guard prepareWindow(screens: screens, pointer: pointer) != nil else { hide(); return }
        if timer == nil && panel?.isVisible != true { indicator?.restart() }
        tick(at: ProcessInfo.processInfo.systemUptime)
        if presentsWindows { visibility?.setVisible(true); updateInteractionPanel() }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(at: ProcessInfo.processInfo.systemUptime) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func tick(at time: Double) { render(at: time); updateInteractionPanel() }

    private func render(at time: Double) {
        guard let panel, let view = classicIndicator, let screen = placedScreen else { return }
        let attachment = dockedSide ?? (view.amount > 0 ? view.attachmentSide : nil)
        let frame = ClassicIndicatorView.frame(center: restingCenter, screen: screen.frame, attachment: attachment)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.frame = CGRect(origin: .zero, size: frame.size)
        var symbol = BezelSymbol.resolve(phase: state.phase, waiting: state.isWaitingToPaste, deliveryHint: state.pasteHint)
        var bands = state.speechSpectrum
        if state.phase == .preview {
            if previewStarted == nil { previewStarted = time }
            let elapsed = time - (previewStarted ?? time)
            symbol = elapsed < 3.6 ? .waveform : elapsed < 5.1 ? .spinner : .checkmark
            bands = Self.previewBands(time: time)
        } else { previewStarted = nil }
        let reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        view.update(center: CGPoint(x: restingCenter.x - frame.minX, y: restingCenter.y - frame.minY),
            screen: screen.frame.offsetBy(dx: -frame.minX, dy: -frame.minY), side: dockedSide,
            symbol: symbol, spectrum: bands, level: state.glowLevel, time: time,
            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            reducedTransparency: reducedTransparency,
            gradient: state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init())
        if reducedTransparency || view.amount == 0 { backdrop?.profile = nil }
        else { backdrop?.apply(profile: GlowProfile(energy: view.amount, heights: [], bezel: BezelBackdrop(path: view.shape.path)), radiusMap: nil) }
    }
    private func beginDrag(at pointer: CGPoint) {
        guard let screen = placedScreen else { return }
        if let panel, let view = classicIndicator, view.amount == 1 {
            let rect = view.hitPath.boundingBoxOfPath
            restingCenter = CGPoint(x: panel.frame.minX + rect.midX, y: panel.frame.minY + rect.midY)
        }
        drag = GlassCapsuleDrag(pointer: pointer, center: restingCenter, screenMidX: screen.frame.midX)
    }
    private func moveDrag(to pointer: CGPoint) {
        guard var drag, let index = GlowDisplay.preferredIndex(in: placementScreens.map { GlowDisplay(screen: $0) }, pointer: pointer) else { return }
        let screen = placementScreens[index]
        restingCenter = drag.update(pointer: pointer, visibleFrame: screen.visibleFrame, screenMidX: screen.frame.midX)
        self.drag = drag
        placedScreen = screen
        dockedSide = GlassCapsuleAnchor.dockingSide(pointer: pointer, screen: screen.frame, attached: dockedSide)
        if timer == nil { tick(at: ProcessInfo.processInfo.systemUptime) }
    }
    private func endDrag(at pointer: CGPoint?) {
        if let pointer, drag != nil {
            moveDrag(to: pointer)
            if let screen = placedScreen {
                placement.save(GlassCapsuleAnchor(center: restingCenter, visibleFrame: screen.visibleFrame,
                    displayID: GlassCapsulePlacementStore.identifier(for: screen), screenMidX: screen.frame.midX, side: dockedSide))
            }
        }
        drag = nil
        _ = prepareWindow(screens: placementScreens, pointer: placedScreen?.frame.origin ?? .zero)
        updateInteractionPanel()
    }
    private func updateInteractionPanel() {
        guard let panel, let view = classicIndicator, let interactionPanel else { return }
        let local = view.hitPath.boundingBoxOfPath
        let frame = local.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        if interactionPanel.frame != frame { interactionPanel.setFrame(frame, display: false) }
        var translate = CGAffineTransform(translationX: -local.minX, y: -local.minY)
        interactionPanel.interaction.shape = view.hitPath.copy(using: &translate)
        interactionPanel.interaction.needsLayout = true
        interactionPanel.interaction.layoutSubtreeIfNeeded()
        interactionPanel.button.isEnabled = dockedSide == nil && view.amount < 0.01 && view.glass.allowsCancellation && state.canCancel
        interactionPanel.button.isHidden = !interactionPanel.button.isEnabled
        interactionPanel.updateHitTesting(pointer: NSEvent.mouseLocation)
        if presentsWindows && panel.isVisible {
            if interactionPanel.parent == nil { panel.addChildWindow(interactionPanel, ordered: .above) }
            if !interactionPanel.isVisible { interactionPanel.orderFrontRegardless() }
        } else if !presentsWindows {
            interactionPanel.orderOut(nil)
        }
    }
    static func previewBands(time: Double) -> [Double] {
        (0..<7).map { index -> Double in
            let angle = time * 3.0 + Double(index) * 0.8
            return 0.15 + 0.7 * (0.5 + 0.5 * sin(angle))
        }
    }
    func hide() {
        timer?.invalidate(); timer = nil
        previewStarted = nil; drag = nil
        if let interactionPanel {
            interactionPanel.interaction.cancelDrag()
            panel?.removeChildWindow(interactionPanel)
            interactionPanel.orderOut(nil)
        }
        if presentsWindows { visibility?.setVisible(false) }
    }
    deinit { timer?.invalidate() }
}

struct GlassWaveformPreview: NSViewRepresentable {
    let phase: Int
    let time: Double
    let reducedMotion: Bool
    let reducedTransparency: Bool
    var gradient = GlowGradient()
    func makeNSView(context: Context) -> GlassWaveformView { GlassWaveformView(frame: CGRect(origin: .zero, size: GlassWaveformView.size)) }
    func updateNSView(_ view: GlassWaveformView, context: Context) {
        view.update(spectrum: GlassWaveformController.previewBands(time: reducedMotion ? 0 : time),
            symbol: phase == 2 ? .spinner : .waveform, time: time,
            reducedMotion: reducedMotion, reducedTransparency: reducedTransparency, gradient: gradient)
    }
}

/// Keeps the Classic capsule clear, refracting Liquid Glass with no blur. When the system Liquid Glass
/// preference is set toward Tinted, AppKit lays a frosted blur fill over the glass, which reads as plain
/// background blur at this size. Only this capsule's glass filter is adjusted; other windows follow the system.
@available(macOS 26.0, *)
@MainActor enum LiquidGlassLens {
    fileprivate static let values: [String: Double] = [
        "inputBlurFillBlurRadius": 0, "inputBlurFillNormalOpacity": 0,
        // No blur at all: the background stays sharp and only bends at the rim.
        "inputBlurRadius": 0, "inputBlurOpacity0": 0, "inputBlurOpacity1": 0, "inputBlurOpacity2": 0,
        "inputBlurOpacity3": 0, "inputBlurOpacity4": 0,
        "inputInnerRefractionAmount": -30, "inputInnerRefractionHeight": 12,
        "inputAberrationAmount": 0.65, "inputAberrationHeight": 8,
        "inputKeyFillHighlightAmount": 0.8,
        // Keep blacks black so the fade beneath the glass reaches true black at the top.
        "inputFaceColorMatrixBlack": 0, "inputFaceColorMatrixWhite": 1
    ]
    private static var observers: [ObjectIdentifier: LiquidGlassLensObserver] = [:]

    static func apply(to effect: NSGlassEffectView) {
        guard let root = effect.layer, let backdrop = backdrop(in: root) else { return }
        observers = observers.filter { $0.value.effect != nil }
        let key = ObjectIdentifier(effect)
        if observers[key]?.backdrop !== backdrop || observers[key]?.effect !== effect {
            // AppKit rebuilds the glass filter whenever the capsule resizes, later in the same frame.
            // Watching the layer re-applies the lens inside that transaction instead of one frame late.
            observers[key] = LiquidGlassLensObserver(effect: effect, backdrop: backdrop)
        }
        observers[key]?.scale = effect.window?.backingScaleFactor ?? 2
        observers[key]?.enforce()
    }

    fileprivate static func backdrop(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)) == "CABackdropLayer" { return layer }
        for sublayer in layer.sublayers ?? [] { if let found = backdrop(in: sublayer) { return found } }
        return nil
    }
}

@available(macOS 26.0, *)
private final class LiquidGlassLensObserver: NSObject {
    weak var effect: NSGlassEffectView?
    // Held strongly so the observed layer cannot be released while registered.
    let backdrop: CALayer
    var scale: CGFloat = 2

    init(effect: NSGlassEffectView, backdrop: CALayer) {
        self.effect = effect
        self.backdrop = backdrop
        super.init()
        for key in ["filters", "scale"] { backdrop.addObserver(self, forKeyPath: key, options: [], context: nil) }
    }

    func enforce() {
        guard let filter = backdrop.filters?.first as? NSObject,
              filter.value(forKey: "type") as? String == "glassBackground" else { return }
        let values = LiquidGlassLens.values
        if !values.allSatisfy({ (filter.value(forKey: $0.key) as? Double) == $0.value }), let copy = filter.copy() as? NSObject {
            // Filters are submitted by value; publish a modified copy rather than mutating in place.
            for (key, value) in values { copy.setValue(value, forKey: key) }
            backdrop.filters = [copy]
        }
        if (backdrop.value(forKey: "scale") as? Double) != Double(scale) { backdrop.setValue(scale, forKey: "scale") }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        MainActor.assumeIsolated { enforce() }
    }

    deinit {
        for key in ["filters", "scale"] { backdrop.removeObserver(self, forKeyPath: key) }
    }
}
