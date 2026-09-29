import SwiftUI
import S2TCore

/// Maps angular shading to distance along the actual input outline.
enum InputGradientCycle {
    struct Sample {
        let angle: Double
        let distance: Double
    }
    private final class Samples {
        let values: [Sample]
        init(_ values: [Sample]) { self.values = values }
    }
    private static let cache: NSCache<NSString, Samples> = {
        let cache = NSCache<NSString, Samples>()
        cache.countLimit = 8
        return cache
    }()

    static func samples(rect: CGRect, radius: CGFloat, cornerStyle: InputCornerStyle = .continuous) -> [Sample] {
        samples(contour: InputContour(rect: rect, radius: radius, style: cornerStyle))
    }

    static func samples(contour: InputContour) -> [Sample] {
        let rect = contour.bounds
        let key = String(describing: contour) as NSString
        if let cached = cache.object(forKey: key) { return cached.values }
        let path = contour.path
        var points: [CGPoint] = []
        var current = CGPoint.zero, start = CGPoint.zero
        func append(_ point: CGPoint) { points.append(point); current = point }
        path.cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                start = element.points[0]; append(start)
            case .addLineToPoint: append(element.points[0])
            case .addQuadCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1]
                for i in 1...64 {
                    let t = Double(i) / 64, v = 1 - t
                    append(CGPoint(x: v*v*a.x + 2*v*t*b.x + t*t*c.x,
                                   y: v*v*a.y + 2*v*t*b.y + t*t*c.y))
                }
            case .addCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1], d = element.points[2]
                for i in 1...64 {
                    let t = Double(i) / 64, v = 1 - t
                    append(CGPoint(x: v*v*v*a.x + 3*v*v*t*b.x + 3*v*t*t*c.x + t*t*t*d.x,
                                   y: v*v*v*a.y + 3*v*v*t*b.y + 3*v*t*t*c.y + t*t*t*d.y))
                }
            case .closeSubpath: append(start)
            @unknown default: break
            }
        }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let perimeter = lengths.reduce(0, +)
        var travelled = 0.0
        var values: [Sample] = []
        for (index, length) in lengths.enumerated() {
            let a = points[index], b = points[index + 1]
            let steps = max(1, Int(ceil(length / (perimeter / 512))))
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                let point = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let angle = atan2(point.y - rect.midY, point.x - rect.midX) / (2 * .pi)
                values.append(Sample(angle: angle < 0 ? angle + 1 : angle,
                                     distance: (travelled + length * t) / perimeter))
            }
            travelled += length
        }
        values.sort { $0.angle < $1.angle }
        let first = values.first!, last = values.last!
        var delta = first.distance - last.distance
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        let seamGap = first.angle + 1 - last.angle
        let seam = seamGap > 0 ? last.distance + delta * (1 - last.angle) / seamGap : first.distance
        values.insert(Sample(angle: 0, distance: seam), at: 0)
        values.append(Sample(angle: 1, distance: seam))
        cache.setObject(Samples(values), forKey: key)
        return values
    }

    static func shading(rect: CGRect, radius: CGFloat, time: Double, cornerStyle: InputCornerStyle = .continuous) -> GraphicsContext.Shading {
        shading(contour: InputContour(rect: rect, radius: radius, style: cornerStyle), time: time)
    }

    static func shading(contour: InputContour, time: Double, custom: GlowGradient.Sampler? = nil) -> GraphicsContext.Shading {
        let rect = contour.bounds
        let stops = samples(contour: contour).map { sample -> Gradient.Stop in
            let rgb = custom?.color(at: sample.distance + time / GlowColorCycle.duration)
                ?? GlowColorCycle.color(position: sample.distance / 0.75, time: time)
            return .init(color: Color(red: rgb.x, green: rgb.y, blue: rgb.z), location: sample.angle)
        }
        return .conicGradient(Gradient(stops: stops), center: CGPoint(x: rect.midX, y: rect.midY))
    }
}
