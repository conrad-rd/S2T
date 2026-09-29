import AppKit
import S2TCore

@MainActor final class ClassicIndicatorView: NSView {
    let glass = GlassWaveformView(frame: CGRect(origin: .zero, size: BezelGeometry.size))
    let bezel = BezelIndicatorView(frame: CGRect(origin: .zero, size: BezelGeometry.size))
    private(set) var motion = ClassicDockMotion()
    private(set) var shape = BezelGeometry.shape(form: .shown, side: .right)
    private(set) var attachmentSide = BezelSide.right
    private var initialized = false
    private var liquid = ClassicLiquidMotion()
    var amount: Double { motion.amount }
    var hitPath: CGPath {
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        return shape.path.copy(using: &flip)!
    }

    init() {
        super.init(frame: CGRect(origin: .zero, size: BezelGeometry.size))
        addSubview(glass)
        addSubview(bezel)
    }
    required init?(coder: NSCoder) { nil }

    func update(center: CGPoint, screen: CGRect, side: BezelSide?, symbol: BezelSymbol, spectrum: [Double], level: Double,
                time: Double, reducedMotion: Bool, reducedTransparency: Bool, gradient: GlowGradient) {
        if !initialized { motion = ClassicDockMotion(attached: side != nil); initialized = true }
        let changingSides = side != nil && side != attachmentSide && motion.amount > 0 && !reducedMotion
        if let side, !changingSides { attachmentSide = side }
        motion.update(attached: side != nil && !changingSides, time: time, reducedMotion: reducedMotion)
        glass.frame = bounds
        bezel.frame = bounds
        glass.update(spectrum: spectrum, symbol: symbol, time: time, reducedMotion: reducedMotion,
            reducedTransparency: reducedTransparency, gradient: gradient)
        liquid.update(point: CGPoint(x: center.x - screen.minX, y: center.y - screen.minY),
            time: time, reducedMotion: reducedMotion)
        let rect = glass.animatedBodyRect.offsetBy(dx: center.x - bounds.midX, dy: center.y - bounds.midY)
        let flippedRect = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        let amount = motion.amount
        let response = 1 - amount
        let horizontal = liquid.stretch.x * response
        let vertical = liquid.stretch.y * response
        // Kept small: the capsule should lean into a drag, not wobble.
        let scale = 1 + 0.045 * abs(horizontal) - 0.03 * abs(vertical)
        var deformation = CGAffineTransform(a: scale, b: -vertical * 0.015,
            c: horizontal * 0.045, d: 1 / scale, tx: 0, ty: 0)
        // Apply the deformation around the capsule center, leaving pointer placement exact.
        deformation.tx = flippedRect.midX - deformation.a * flippedRect.midX - deformation.c * flippedRect.midY
        deformation.ty = flippedRect.midY - deformation.b * flippedRect.midX - deformation.d * flippedRect.midY
        let speech = reducedMotion || symbol != .waveform ? 0 : level
        let dock = ClassicDockShape.make(floating: flippedRect, edge: attachmentSide == .left ? screen.minX : screen.maxX,
            side: attachmentSide, dockedY: bounds.height - center.y, speech: speech, amount: amount,
            symbolOffset: glass.allowsCancellation ? 12 : 0)
        var body = dock.body
        if amount < 1 {
            shape = BezelShape(path: dock.shape.path.copy(using: &deformation)!, symbolCenter: dock.shape.symbolCenter)
            body = body.applying(deformation)
        } else {
            let attached = BezelGeometry.shape(form: .shown, side: attachmentSide, level: speech)
            var shift = CGAffineTransform(translationX: attachmentSide == .left ? screen.minX : screen.maxX - BezelGeometry.size.width,
                y: bounds.height - center.y - BezelGeometry.size.height / 2)
            shape = BezelShape(path: attached.path.copy(using: &shift)!, symbolCenter: attached.symbolCenter.applying(shift))
        }
        // The waveform turns a quarter, landing on the Bezel's stacked bars in the same order.
        let turn = min(1, amount / 0.92)
        let rotation = -turn * turn * (3 - 2 * turn) * .pi / 2
        glass.applyClassicShape(shape, body: body, amount: amount, rotation: rotation)
        bezel.side = attachmentSide
        bezel.previewShape = shape
        bezel.update(form: .shown, symbol: symbol, level: level, spectrum: spectrum, time: time, reducedMotion: reducedMotion)
        // The glass carries the whole transition. By the last degree of the turn both layers match in
        // shape, color and glyph, so the Bezel takes over without a crossfade that would double the bars.
        glass.alphaValue = 1
        bezel.alphaValue = 1
        glass.isHidden = amount == 1
        bezel.isHidden = amount < 0.985
    }

    static func frame(center: CGPoint, screen: CGRect, attachment: BezelSide? = nil) -> CGRect {
        var rect = CGRect(x: min(screen.maxX - 200, max(screen.minX, center.x - 100)),
            y: center.y - 190, width: 200, height: 380)
        if let attachment {
            let edge = CGRect(x: attachment == .left ? screen.minX : screen.maxX - 200,
                y: rect.minY, width: 200, height: 380)
            rect = rect.union(edge)
        }
        return rect
    }
}

/// One continuous body between the floating capsule and the docked Bezel: the capsule slides to the edge,
/// grows into the Bezel's proportions, and a meniscus forms where it meets the screen edge.
enum ClassicDockShape {
    static func make(floating rect: CGRect, edge: CGFloat, side: BezelSide, dockedY: CGFloat, speech: Double,
                     amount: Double, symbolOffset: CGFloat) -> (shape: BezelShape, body: CGRect) {
        let e = min(1, max(0, amount))
        let floatingSymbol = CGPoint(x: rect.midX + symbolOffset, y: rect.midY)
        if e == 0 { return (BezelShape(path: GlassCapsuleArtwork.path(in: rect), symbolCenter: floatingSymbol), rect) }
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        func smooth(_ from: Double, _ to: Double, _ value: Double) -> Double {
            let t = min(1, max(0, (value - from) / (to - from)))
            return t * t * (3 - 2 * t)
        }
        // Docked proportions from BezelGeometry.shape(form: .shown).
        let front = 46 + speech, dockedHalf = 35 + speech, neck = 20.0
        let near = side == .left ? rect.minX - edge : edge - rect.maxX
        // Travel leads, proportions follow slightly behind, and the meniscus arrives last.
        let travel = smooth(0, 0.8, e), form = e
        // The body slides as one piece; it never stretches across the gap to the edge.
        let u0 = near * (1 - travel), u1 = u0 + max(1, mix(rect.width, front, form))
        let bridge = smooth(0.15, 1, e) * smooth(0, 1, 1 - u0 / 24)
        let middle = mix(rect.midY, dockedY, travel)
        let half = mix(rect.height / 2, dockedHalf, form)
        let top = middle - half, bottom = middle + half
        let limit = min(half, (u1 - u0) / 2)
        let outer = min(limit, mix(rect.height / 2, min(24, front - 22, dockedHalf * 0.68), form))
        let inner = min(limit, rect.height / 2 * (1 - bridge))
        func x(_ u: CGFloat) -> CGFloat { side == .left ? edge + u : edge - u }

        let path = CGMutablePath()
        // Body, clockwise with y down. The edge-facing corners square off as the meniscus takes over.
        path.move(to: CGPoint(x: x(u0 + inner), y: top))
        path.addLine(to: CGPoint(x: x(u1 - outer), y: top))
        path.addArc(tangent1End: CGPoint(x: x(u1), y: top), tangent2End: CGPoint(x: x(u1), y: bottom), radius: outer)
        path.addArc(tangent1End: CGPoint(x: x(u1), y: bottom), tangent2End: CGPoint(x: x(u0), y: bottom), radius: outer)
        path.addArc(tangent1End: CGPoint(x: x(u0), y: bottom), tangent2End: CGPoint(x: x(u0), y: top), radius: inner)
        path.addArc(tangent1End: CGPoint(x: x(u0), y: top), tangent2End: CGPoint(x: x(u1), y: top), radius: inner)
        path.closeSubpath()
        if bridge > 0.001 {
            // Meniscus: a soft waist where the body meets the edge, opening into the Bezel's concave neck.
            let reach = min(u1 - outer, u0 + inner + neck * bridge)
            let upper = top - neck * bridge, lower = bottom + neck * bridge
            let pinch = (1 - bridge) * reach * 0.5
            path.move(to: CGPoint(x: x(0), y: upper))
            path.addCurve(to: CGPoint(x: x(reach), y: top),
                control1: CGPoint(x: x(pinch), y: upper + bridge * 0.55 * (top - upper)),
                control2: CGPoint(x: x(reach - 0.55 * reach), y: top))
            path.addLine(to: CGPoint(x: x(reach), y: bottom))
            path.addCurve(to: CGPoint(x: x(0), y: lower),
                control1: CGPoint(x: x(reach - 0.55 * reach), y: bottom),
                control2: CGPoint(x: x(pinch), y: lower - bridge * 0.55 * (lower - bottom)))
            path.closeSubpath()
        }
        let dockedSymbol = CGPoint(x: x(front / 2), y: dockedY)
        let symbol = CGPoint(x: mix(floatingSymbol.x, dockedSymbol.x, travel), y: mix(floatingSymbol.y, dockedSymbol.y, travel))
        let body = CGRect(x: min(x(u0), x(u1)), y: top, width: u1 - u0, height: bottom - top)
        return (BezelShape(path: path, symbolCenter: symbol), body)
    }
}
