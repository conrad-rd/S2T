import CoreGraphics
import Foundation

public enum ClassicBarPlacement {
    public static func offset(home: CGRect, obstacle: CGRect, container: CGRect,
                              side: BezelSide?, previous: CGPoint = .zero) -> CGPoint {
        let gap = 14.0
        guard home.insetBy(dx: -gap, dy: -gap).intersects(obstacle) else { return .zero }
        let available = container.insetBy(dx: 8, dy: 8)
        func fits(_ offset: CGPoint) -> Bool {
            available.contains(home.offsetBy(dx: offset.x, dy: offset.y))
        }
        if let side {
            let offset = CGPoint(x: side == .left ? obstacle.maxX + gap - home.minX : obstacle.minX - gap - home.maxX, y: 0)
            if fits(offset) { return offset }
        }
        let above = CGPoint(x: 0, y: obstacle.maxY + gap - home.minY)
        let below = CGPoint(x: 0, y: obstacle.minY - gap - home.maxY)
        let choices = [above, below].filter(fits)
        if choices.count == 2 {
            if previous.y > 0 && abs(above.y) <= abs(below.y) + 24 { return above }
            if previous.y < 0 && abs(below.y) <= abs(above.y) + 24 { return below }
        }
        return choices.min { abs($0.y) < abs($1.y) } ?? .zero
    }
}

public struct ClassicBarMotion {
    public private(set) var position = CGPoint.zero
    public private(set) var velocity = CGPoint.zero
    public var target = CGPoint.zero
    private var previousTime: Double?
    public init() {}
    public mutating func resume(time: Double) { previousTime = time }

    public mutating func update(time: Double, reducedMotion: Bool) {
        let dt = min(0.05, max(0, time - (previousTime ?? time)))
        previousTime = time
        if reducedMotion { position = target; velocity = .zero; return }
        let frequency = 20.0
        func step(_ value: CGFloat, _ speed: CGFloat, _ goal: CGFloat) -> (CGFloat, CGFloat) {
            let offset = value - goal
            let slope = speed + frequency * offset
            let decay = exp(-frequency * dt)
            let next = goal + (offset + slope * dt) * decay
            let velocity = (speed - frequency * slope * dt) * decay
            return abs(next - goal) < 0.05 && abs(velocity) < 0.1 ? (goal, 0) : (next, velocity)
        }
        (position.x, velocity.x) = step(position.x, velocity.x, target.x)
        (position.y, velocity.y) = step(position.y, velocity.y, target.y)
    }
    public var settled: Bool { position == target && velocity == .zero }
}
