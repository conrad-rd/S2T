import Foundation

public enum GlowColorCycle {
    public static let duration = 10.0
    private static let colors = [SIMD3<Double>(142, 0, 255), SIMD3<Double>(0, 93, 255),
                                 SIMD3<Double>(253, 90, 189), SIMD3<Double>(255, 0, 250)]

    public static func color(position: Double, time: Double) -> SIMD3<Double> {
        let turn = position * 0.75 + time / duration
        let wrapped = turn - floor(turn)
        let segment = wrapped * Double(colors.count)
        let index = min(colors.count - 1, Int(segment))
        let fraction = segment - Double(index)
        let blend = fraction * fraction * (3 - 2 * fraction)
        let start = colors[index] / 255
        let end = colors[(index + 1) % colors.count] / 255
        return start + (end - start) * blend
    }
}

/// Integrates elapsed time so changing speed does not jump to a different color.
public final class GlowColorCycleClock {
    private var previousTime: Double?
    private var previousSpeed = 0.1
    private var phaseTime = 0.0

    public init() {}

    public func sample(time: Double, speed: Double) -> Double {
        if let previousTime {
            phaseTime += max(0, time - previousTime) * previousSpeed * GlowColorCycle.duration
        } else {
            phaseTime = time * speed * GlowColorCycle.duration
        }
        phaseTime.formTruncatingRemainder(dividingBy: GlowColorCycle.duration)
        previousTime = time
        previousSpeed = speed
        return phaseTime
    }
}
