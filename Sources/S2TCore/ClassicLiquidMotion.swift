import CoreGraphics
import Foundation

public struct ClassicLiquidMotion {
    public private(set) var stretch = CGPoint.zero
    private var velocity = CGPoint.zero
    private var previousPoint: CGPoint?
    private var previousTime: Double?

    public init() {}

    public mutating func update(point: CGPoint, time: Double, reducedMotion: Bool) {
        defer { previousPoint = point; previousTime = time }
        guard let previousPoint, let previousTime else { return }
        let elapsed = time - previousTime
        guard elapsed > 0 else { return }
        if reducedMotion || elapsed > 0.2 {
            stretch = .zero
            velocity = .zero
            return
        }
        let dt = min(0.05, elapsed)
        let dx = (point.x - previousPoint.x) / elapsed
        let dy = (point.y - previousPoint.y) / elapsed
        let target = CGPoint(x: tanh(dx / 900), y: tanh(dy / 900))
        func step(_ value: CGFloat, _ speed: CGFloat, _ target: CGFloat) -> (CGFloat, CGFloat) {
            let damping = 18.0, frequency = 15.0
            let offset = value - target
            let slope = (speed + damping * offset) / frequency
            let wave = offset * cos(frequency * dt) + slope * sin(frequency * dt)
            let decay = exp(-damping * dt)
            return (target + decay * wave,
                decay * (frequency * (-offset * sin(frequency * dt) + slope * cos(frequency * dt)) - damping * wave))
        }
        (stretch.x, velocity.x) = step(stretch.x, velocity.x, target.x)
        (stretch.y, velocity.y) = step(stretch.y, velocity.y, target.y)
    }
}
