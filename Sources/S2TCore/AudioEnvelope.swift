import Foundation

public struct AudioEnvelope {
    public private(set) var level: Double = 0
    public init() {}
    public mutating func update(rms: Double, peak: Double, duration: Double) -> Double {
        let signal = max(rms, peak * 0.32)
        let decibels = 20 * log10(max(signal, 0.000001))
        let normalized = max(0, min(1, (decibels + 58) / 40))
        let target = pow(normalized, 0.8)
        let timeConstant = target > level ? 0.004 : 0.055
        let blend = 1 - exp(-max(0, duration) / timeConstant)
        level += (target - level) * blend
        return level
    }
}
