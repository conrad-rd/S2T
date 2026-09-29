import Foundation

public struct ClassicDockMotion {
    public private(set) var amount: Double
    public private(set) var velocity = 0.0
    private var previousTime: Double?

    public init(attached: Bool = false) { amount = attached ? 1 : 0 }

    public mutating func update(attached: Bool, time: Double, reducedMotion: Bool) {
        let target = attached ? 1.0 : 0.0
        let dt = min(0.05, max(0, time - (previousTime ?? time)))
        previousTime = time
        if reducedMotion { amount = target; velocity = 0; return }
        let frequency = 11.5
        let offset = amount - target
        let slope = velocity + frequency * offset
        let decay = exp(-frequency * dt)
        amount = target + (offset + slope * dt) * decay
        velocity = (velocity - frequency * slope * dt) * decay
        if abs(amount - target) < 0.0005 && abs(velocity) < 0.01 { amount = target; velocity = 0 }
    }
}
