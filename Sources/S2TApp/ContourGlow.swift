import SwiftUI
import S2TCore

/// The Bottom sweep's palette and transfer, fitted to an exterior contour.
enum ContourGlow {
    static func gradient(width: CGFloat, failed: Bool, origin: CGFloat = 0) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: GlowSweep.stops.map { stop in
            .init(color: failed ? .orange : Color(red: stop.rgb[0], green: stop.rgb[1], blue: stop.rgb[2]), location: stop.position)
        }), startPoint: CGPoint(x: origin, y: 0), endPoint: CGPoint(x: origin + width, y: 0))
    }

    static func drawSweep(context: inout GraphicsContext, size: CGSize, bounds: ClosedRange<CGFloat>,
                          body: NSImage, highlight: NSImage, brightness: Double, failed: Bool,
                          deformation: CGAffineTransform, illumination: (Double) -> Double = { _ in 1 }) {
        let rect = CGRect(origin: .zero, size: size)
        for layer in 0..<3 {
            context.drawLayer { face in
                if layer != 2 { face.concatenate(deformation) }
                let colors = GlowSweep.stops.map { stop -> Gradient.Stop in
                    var rgb = failed ? [1, 0.5, 0] : stop.rgb
                    if layer == 0 { rgb = [1, 1, 1] }
                    if layer == 2 { rgb = rgb.map { 1 - (1 - $0) * 0.45 } }
                    return .init(color: Color(red: rgb[0], green: rgb[1], blue: rgb[2]), location: stop.position)
                }
                face.opacity = brightness * (layer == 0 ? GlowSweep.whiteLift : layer == 1 ? GlowSweep.colorOpacity : 1)
                face.fill(Path(rect), with: .linearGradient(Gradient(stops: colors),
                    startPoint: CGPoint(x: bounds.lowerBound, y: 0), endPoint: CGPoint(x: bounds.upperBound, y: 0)))
                face.opacity = 1
                face.blendMode = .destinationIn
                face.draw(Image(nsImage: layer == 2 ? highlight : body).interpolation(.high), in: rect)
                if layer != 2 {
                    face.fill(Path(rect), with: .linearGradient(Gradient(stops: (0...32).map { index in
                        let x = Double(index) / 32
                        return .init(color: .white.opacity(illumination(x)), location: x)
                    }), startPoint: CGPoint(x: bounds.lowerBound, y: 0), endPoint: CGPoint(x: bounds.upperBound, y: 0)))
                }
            }
        }
    }

    static func draw(context: inout GraphicsContext, path: Path, gradient: GraphicsContext.Shading,
                     extent: Double, brightness: Double, gentle: Bool = false, deformation: CGAffineTransform = .identity) {
        context.drawLayer { haze in
            haze.concatenate(deformation)
            var previous = 0.0
            for step in stride(from: Int(ceil(extent)), through: 1, by: -1) {
                let depth = max(0, 1 - Double(step - 1) / extent)
                let coverage = gentle ? depth * depth : GlowSweep.vertical(depth)
                let alpha = coverage * brightness * (gentle ? 0.24 : GlowSweep.colorOpacity)
                haze.opacity = max(0, alpha - previous) / max(0.001, 1 - previous)
                haze.stroke(path, with: gradient, lineWidth: Double(step) * 2)
                previous = alpha
            }
        }
        drawEdge(context: &context, path: path, gradient: gradient, brightness: brightness, gentle: gentle)
    }

    static func drawEdge(context: inout GraphicsContext, path: Path, gradient: GraphicsContext.Shading,
                         brightness: Double, gentle: Bool) {
        if gentle {
            var previousEdge = 0.0
            for step in stride(from: 16, through: 1, by: -1) {
                let depth = 1 - Double(step - 1) / 16
                let coverage = depth * depth * (3 - 2 * depth)
                let alpha = coverage * brightness * 0.32
                context.opacity = (alpha - previousEdge) / max(0.001, 1 - previousEdge)
                context.stroke(path, with: gradient, lineWidth: Double(step) * 0.5)
                previousEdge = alpha
            }
        }
        context.opacity = brightness * (gentle ? 0.18 : 0.95)
        context.stroke(path, with: gradient, lineWidth: gentle ? 1 : 2.5)
        context.opacity = brightness * (gentle ? 0.10 : 0.55)
        context.stroke(path, with: .color(.white), lineWidth: 1)
        context.opacity = 1
    }
}
