import AppKit
import SwiftUI
import S2TCore

struct ClassicPreview: NSViewRepresentable {
    @ObservedObject var state: AppState
    let phase: Int
    let time: Double
    var onPlacement: ((NSView, CGRect, BezelSide?) -> Void)?
    let reducedMotion: Bool
    let reducedTransparency: Bool

    func makeNSView(context: Context) -> ClassicPreviewView { ClassicPreviewView() }
    func updateNSView(_ view: ClassicPreviewView, context: Context) {
        view.onPlacement = onPlacement
        view.onMove = { center, bounds, side in
            let screen = NSScreen.screens.first
            state.classicAnchor = GlassCapsuleAnchor(center: center, visibleFrame: bounds,
                displayID: state.classicAnchor?.displayID ?? screen.map(GlassCapsulePlacementStore.identifier(for:)) ?? "", side: side)
        }
        view.synchronize(anchor: state.classicAnchor, legacySide: state.glowAppearance == .bezel ? state.bezelSide : nil,
            legacyPosition: state.bezelVerticalPosition, phase: phase, time: time,
            reducedMotion: reducedMotion, reducedTransparency: reducedTransparency,
            gradient: state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init())
    }
}

@MainActor final class ClassicPreviewView: NSView {
    let indicator = ClassicIndicatorView()
    var glass: GlassWaveformView { indicator.glass }
    var bezel: BezelIndicatorView { indicator.bezel }
    var onMove: ((CGPoint, CGRect, BezelSide?) -> Void)?
    var onPlacement: ((NSView, CGRect, BezelSide?) -> Void)?
    private(set) var side: BezelSide?
    private(set) var center = CGPoint.zero
    private var anchor: GlassCapsuleAnchor?
    private var legacySide: BezelSide?
    private var legacyPosition = 0.5
    private var drag: GlassCapsuleDrag?
    private var overlay: NSView?
    private var timer: Timer?
    private var phase = 0
    private var reducedMotion = false
    private var reducedTransparency = false
    private var gradient = GlowGradient()
    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        addSubview(indicator)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Classic placement")
        toolTip = "Drag to either edge for Bezel. Drag away for Liquid Glass. Arrow keys move; Space floats; Escape cancels."
    }
    required init?(coder: NSCoder) { nil }

    func synchronize(anchor: GlassCapsuleAnchor?, legacySide: BezelSide?, legacyPosition: Double,
                     phase: Int, time: Double, reducedMotion: Bool, reducedTransparency: Bool, gradient: GlowGradient = .init()) {
        self.anchor = anchor
        self.legacySide = legacySide
        self.legacyPosition = legacyPosition
        if drag == nil { restorePlacement() }
        self.phase = phase
        self.reducedMotion = reducedMotion
        self.reducedTransparency = reducedTransparency
        self.gradient = gradient
        place()
    }
    override func layout() {
        super.layout()
        if drag == nil { restorePlacement() }
        place()
    }
    private func restorePlacement() {
        side = anchor?.side ?? (anchor == nil ? legacySide : nil)
        center = anchor?.center(in: bounds) ?? CGPoint(x: bounds.midX, y: max(80, bounds.height - 150))
        if anchor == nil, side != nil {
            center.y = BezelGeometry.frame(screen: bounds, side: side!, verticalPosition: legacyPosition).midY
        }
    }
    private func place() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let attachment = side ?? (indicator.amount > 0 ? indicator.attachmentSide : nil)
        let rect = ClassicIndicatorView.frame(center: center, screen: bounds, attachment: attachment)
        indicator.frame = convert(rect, to: overlay ?? self)
        indicator.setBoundsSize(rect.size)
        let now = CACurrentMediaTime()
        indicator.update(center: CGPoint(x: center.x - rect.minX, y: center.y - rect.minY),
            screen: bounds.offsetBy(dx: -rect.minX, dy: -rect.minY), side: side,
            symbol: phase == 2 ? .spinner : .waveform,
            spectrum: GlassWaveformController.previewBands(time: reducedMotion ? 0 : now), level: 0.65,
            time: now, reducedMotion: reducedMotion, reducedTransparency: reducedTransparency, gradient: gradient)
        onPlacement?(indicator, indicator.hitPath.boundingBoxOfPath, side)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = indicator.convert(convert(point, from: superview), from: self)
        return indicator.hitPath.contains(local) ? self : nil
    }
    private func animate() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.place()
                if self.drag == nil && self.indicator.amount == (self.side == nil ? 0 : 1) {
                    self.timer?.invalidate(); self.timer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if indicator.amount == 1 {
            let rect = convert(indicator.hitPath.boundingBoxOfPath, from: indicator)
            center = CGPoint(x: rect.midX, y: rect.midY)
        }
        drag = GlassCapsuleDrag(pointer: point, center: center, screenMidX: bounds.midX)
        window?.makeFirstResponder(self)
        animate()
        if let root = window?.contentView {
            let overlay = ClassicDragOverlay(frame: root.bounds)
            overlay.autoresizingMask = [.width, .height]
            root.addSubview(overlay, positioned: .above, relativeTo: nil)
            overlay.addSubview(indicator)
            self.overlay = overlay
            place()
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard var drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        center = drag.update(pointer: point, visibleFrame: bounds)
        side = GlassCapsuleAnchor.dockingSide(pointer: point, screen: bounds, attached: side)
        self.drag = drag
        place()
    }
    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        mouseDragged(with: event)
        commitPlacement()
        finishDrag()
        animate()
    }
    private func commitPlacement() {
        anchor = GlassCapsuleAnchor(center: center, visibleFrame: bounds, displayID: anchor?.displayID ?? "", side: side)
        onMove?(center, bounds, side)
    }
    private func finishDrag() {
        drag = nil
        addSubview(indicator)
        overlay?.removeFromSuperview()
        overlay = nil
        place()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finishDrag()
            restorePlacement()
            place()
            return
        }
        switch event.keyCode {
        case 123: side = .left; center.x = 66
        case 124: side = .right; center.x = bounds.maxX - 66
        case 126: center.y = min(bounds.maxY - 60, center.y + 20)
        case 125: center.y = max(60, center.y - 20)
        case 49: side = nil; center.x = bounds.midX
        default: super.keyDown(with: event); return
        }
        animate()
        commitPlacement()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(cancelPlacement), name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(cancelPlacement), name: NSWindow.didResignKeyNotification, object: window)
        } else { cancelPlacement() }
    }
    @objc private func cancelPlacement() {
        guard drag != nil else { return }
        finishDrag()
        restorePlacement()
        place()
    }
    override func viewDidHide() { super.viewDidHide(); cancelPlacement() }
    override func accessibilityPerformIncrement() -> Bool { moveVertically(20); return true }
    override func accessibilityPerformDecrement() -> Bool { moveVertically(-20); return true }
    private func moveVertically(_ amount: CGFloat) {
        cancelPlacement()
        center.y = min(bounds.maxY - 60, max(60, center.y + amount))
        animate()
        commitPlacement()
    }
    deinit { timer?.invalidate() }
    override func accessibilityValue() -> Any? { side.map { "Bezel, \($0.title)" } ?? "Floating Liquid Glass" }
}

@MainActor private final class ClassicDragOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
