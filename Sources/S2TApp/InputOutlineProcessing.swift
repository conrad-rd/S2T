import SwiftUI
import S2TCore

enum InputOutlineProcessing {
    static func draw(context: inout GraphicsContext, path: Path, size: CGSize, time: Double,
                     reducedMotion: Bool, reducedTransparency: Bool) {
        let colors = ProcessingSweep.orbitStops.map { stop in
            Gradient.Stop(color: Color(red: stop.rgb[0], green: stop.rgb[1], blue: stop.rgb[2]).opacity(stop.opacity),
                          location: stop.position)
        }
        let bounds = path.boundingRect
        let sweep = GraphicsContext.Shading.conicGradient(Gradient(stops: colors),
            center: CGPoint(x: bounds.midX, y: bounds.midY),
            angle: .degrees(ProcessingSweep.phase(time: time, reducedMotion: reducedMotion) * 360))
        if !reducedTransparency {
            context.drawLayer { bloom in
                var exterior = Path(CGRect(origin: .zero, size: size))
                exterior.addPath(path)
                bloom.clip(to: exterior, style: FillStyle(eoFill: true))
                bloom.addFilter(.blur(radius: 3))
                bloom.opacity = 0.45
                bloom.stroke(path, with: sweep, lineWidth: 6)
            }
        }
        context.stroke(path, with: sweep, lineWidth: 2.5)
    }
}
