import CoreGraphics
import Foundation

public struct GlassWaveformMotion {
    public private(set) var values = Array(repeating: 0.0, count: 7)
    private var velocities = Array(repeating: 0.0, count: 7)
    private var reducedMotion = false
    public init() {}

    public mutating func update(bands: [Double], delta: Double, reducedMotion: Bool = false) {
        self.reducedMotion = reducedMotion
        let dt = delta.isFinite ? min(0.1, max(0, delta)) : 0
        let frequency = 24.0, damping = 0.74
        let decay = damping * frequency
        let oscillation = frequency * sqrt(1 - damping * damping)
        for i in values.indices {
            let input = bands.indices.contains(i) && bands[i].isFinite ? bands[i] : 0
            let target = min(1, max(0, input))
            if reducedMotion { values[i] = target; velocities[i] = 0; continue }
            let offset = values[i] - target
            let slope = (velocities[i] + decay * offset) / oscillation
            let wave = offset * cos(oscillation * dt) + slope * sin(oscillation * dt)
            let derivative = oscillation * (-offset * sin(oscillation * dt) + slope * cos(oscillation * dt))
            values[i] = target + exp(-decay * dt) * wave
            velocities[i] = exp(-decay * dt) * (derivative - decay * wave)
        }
    }

    public func bar(at index: Int) -> GlassWaveformBar {
        let value = min(1.05, max(0, values[index]))
        let stretch = reducedMotion ? 0 : min(1, max(-1, velocities[index] / 10))
        let balance = values[min(6, index + 1)] - values[max(0, index - 1)]
        return GlassWaveformBar(height: 6 + 34 * value,
            width: 5.4 - 0.35 * stretch + 0.15 * value,
            lean: reducedMotion ? 0 : min(0.8, max(-0.8, balance * 0.6)),
            lift: stretch * 0.45)
    }
}

public struct GlassWaveformBar {
    public let height, width, lean, lift: Double

    public func path(center: CGPoint) -> CGPath {
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2 + lift, width: width, height: height)
        let corner = LisseCorner(radius: width * 0.43, budget: width / 2)
        let p = corner.p
        let path = CGMutablePath()
        var cursor = CGPoint(x: rect.minX + p, y: rect.minY)
        path.move(to: cursor)
        func line(_ point: CGPoint) { path.addLine(to: point); cursor = point }
        func turn(_ point: CGPoint, _ vertical: Bool) {
            corner.append(to: path, from: cursor, to: point, verticalFirst: vertical)
            cursor = point
        }
        line(CGPoint(x: rect.maxX - p, y: rect.minY))
        turn(CGPoint(x: rect.maxX, y: rect.minY + p), false)
        line(CGPoint(x: rect.maxX, y: rect.maxY - p))
        turn(CGPoint(x: rect.maxX - p, y: rect.maxY), true)
        line(CGPoint(x: rect.minX + p, y: rect.maxY))
        turn(CGPoint(x: rect.minX, y: rect.maxY - p), false)
        line(CGPoint(x: rect.minX, y: rect.minY + p))
        turn(CGPoint(x: rect.minX + p, y: rect.minY), true)
        path.closeSubpath()
        var shear = CGAffineTransform(a: 1, b: 0, c: lean / height, d: 1,
            tx: -lean / height * (center.y + lift), ty: 0)
        return path.copy(using: &shear)!
    }
}
