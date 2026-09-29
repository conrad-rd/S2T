import AppKit
import S2TCore

/// Measured reference falloff: a nearly black body, broad lower fade, and restrained curved ends.
enum GlassCapsuleArtwork {
    static func path(in rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
    }

    private static var cachedOverlay: (size: CGSize, image: CGImage)?

    static func drawOverlay(in rect: CGRect, context: CGContext) {
        let image: CGImage
        if let cached = cachedOverlay, cached.size == rect.size { image = cached.image }
        else {
            let scale = 3.0
            let width = Int(ceil(rect.width * scale)), height = Int(ceil(rect.height * scale))
            guard width > 0, height > 0 else { return }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let radius = rect.height / 2
            let straight = rect.width / 2 - radius
            for y in 0..<height { for x in 0..<width {
                let px = (Double(x) + 0.5) / Double(width) * rect.width
                let py = (Double(y) + 0.5) / Double(height) * rect.height
                let depth = radius - hypot(max(0, abs(px - rect.width / 2) - straight), py - radius)
                guard depth >= 0 else { continue }
                let capX = max(0, abs(px - rect.width / 2) - straight)
                let lowerCurve = radius - sqrt(max(0, radius * radius - capX * capX))
                let position = (py + 0.85 * lowerCurve) / rect.height
                let progress = min(1, max(0, (position - 0.33) / 0.67))
                let glass = 0.80 * pow(progress, 3.7)
                let alpha = 1 - glass
                let offset = (y * width + x) * 4
                pixels[offset + 3] = UInt8((alpha * 255).rounded())
            } }
            let data = Data(pixels) as CFData
            guard let provider = CGDataProvider(data: data),
                  let generated = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
            image = generated
            cachedOverlay = (rect.size, image)
        }
        context.saveGState()
        context.addPath(path(in: rect))
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// Classic fade: black across the upper quarter, easing to clear at the bottom.
    /// It is placed beneath the glass, so the glass refracts it and its highlights stay on top.
    static func makeFadeLayer() -> CAGradientLayer {
        let layer = CAGradientLayer()
        let locations = (0...16).map { Double($0) / 16 }
        layer.colors = locations.map { position -> CGColor in
            let t = min(1, max(0, (position - 0.24) / 0.72))
            let clear = t * t * (3 - 2 * t)
            return CGColor(gray: 0, alpha: 1 - clear)
        }
        layer.locations = locations.map { NSNumber(value: $0) }
        layer.startPoint = CGPoint(x: 0.5, y: 1)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        return layer
    }

    /// Sinks the Classic body into the Bezel's solid black while docking.
    static func drawDarkening(in rect: CGRect, amount: Double, context: CGContext) {
        guard amount > 0 else { return }
        context.setFillColor(CGColor(gray: 0, alpha: min(1, amount)))
        context.fill(rect)
    }

    static func drawCancel(in rect: CGRect, pressed: Bool, context: CGContext) {
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: pressed ? 0.18 : 0.045))
        context.fillEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
        context.setLineWidth(0.75)
        context.strokeEllipse(in: rect.insetBy(dx: 0.75, dy: 0.75))
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        context.setLineWidth(1.15)
        context.setLineCap(.round)
        for direction in [-1.0, 1.0] {
            context.move(to: CGPoint(x: rect.midX - 2.75, y: rect.midY - 2.75 * direction))
            context.addLine(to: CGPoint(x: rect.midX + 2.75, y: rect.midY + 2.75 * direction))
            context.strokePath()
        }
        context.restoreGState()
    }

    static let processingCycle = 1.5

    static func drawProcessing(in rect: CGRect, time: Double, center: CGPoint? = nil,
                               reducedMotion: Bool = false, context: CGContext) {
        let center = center ?? CGPoint(x: rect.midX + 12, y: rect.midY)
        let turns = reducedMotion ? 0.22 : time / processingCycle
        let phase = turns - floor(turns)
        context.saveGState()
        context.addPath(path(in: rect))
        context.clip()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setAlpha(1)
        for index in 0..<5 {
            let wave = 0.5 + 0.5 * cos(2 * .pi * (phase - Double(index) * 0.14))
            let lift = wave * wave
            let height = 4 + 12 * lift
            let bar = CGRect(x: center.x + Double(index - 2) * 6 - 1.6,
                y: center.y - height / 2, width: 3.2, height: height)
            context.setFillColor(CGColor(gray: 1, alpha: 0.48 + 0.42 * lift))
            context.addPath(CGPath(roundedRect: bar, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
            context.fillPath()
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    static func drawSuccess(center: CGPoint, elapsed: Double, reducedMotion: Bool, context: CGContext) {
        let progress = reducedMotion ? 1 : min(1, max(0, elapsed / 0.32))
        let start = CGPoint(x: center.x - 6, y: center.y)
        let bend = CGPoint(x: center.x - 1.5, y: center.y - 4)
        let end = CGPoint(x: center.x + 7, y: center.y + 5.5)
        func mix(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        context.saveGState()
        if !reducedMotion {
            let ripple = min(1, elapsed / 0.65)
            let radius = 9 + 7 * ripple
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.18 * pow(1 - ripple, 2)))
            context.setLineWidth(0.8)
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(1.8)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        if progress < 0.35 { context.addLine(to: mix(start, bend, progress / 0.35)) }
        else { context.addLine(to: bend); context.addLine(to: mix(bend, end, (progress - 0.35) / 0.65)) }
        context.strokePath()
        context.restoreGState()
    }
}
