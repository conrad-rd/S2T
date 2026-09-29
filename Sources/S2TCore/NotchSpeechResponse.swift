import Foundation

/// Bridges short microphone gaps for the notch and input glows.
public struct NotchSpeechResponse {
    public private(set) var energy = 0.0
    public private(set) var distortion = GlowDistortion.identity
    private var velocity = 0.0
    private var distortionStage = GlowDistortion.identity
    private var previousTime: Double?
    private var silenceStarted: Double?
    private var silenceEnergy = 0.0

    public init() {}

    public mutating func update(level: Double, bands: [Double], time: Double, reducedMotion: Bool, active: Bool = true) {
        guard active else {
            energy = 0
            velocity = 0
            distortion = .identity
            distortionStage = .identity
            previousTime = time
            silenceStarted = nil
            return
        }
        let level = level.isFinite ? level : 0
        let targetEnergy = pow(max(0, min(1, (level - 0.06) / 0.94)), 0.7)
        let target = GlowDistortion(bands: bands, reducedMotion: reducedMotion)
        guard let previous = previousTime, time >= previous, time - previous < 0.5 else {
            energy = targetEnergy
            velocity = 0
            distortion = target
            distortionStage = target
            previousTime = time
            silenceStarted = nil
            return
        }
        guard time > previous else { return }
        let elapsed = min(0.05, time - previous)
        previousTime = time
        if targetEnergy == 0 {
            if silenceStarted == nil {
                silenceStarted = time
                silenceEnergy = energy
                velocity = 0
            }
            // Smoothstep leaves the hold and reaches zero without a visible kink at either end.
            let progress = min(1, max(0, (time - silenceStarted! - 0.11) / 0.32))
            energy = silenceEnergy * (1 - progress * progress * (3 - 2 * progress))
        } else {
            silenceStarted = nil
            // A critically damped spring keeps velocity continuous, so microphone jitter
            // rolls off smoothly instead of kinking the glow on every meter sample.
            // The rates match the former 90 ms attack and 240 ms release at their midpoint.
            let rate = targetEnergy > energy ? 27.0 : 10.1
            (energy, velocity) = Self.spring(value: energy, velocity: velocity, target: targetEnergy, rate: rate, elapsed: elapsed)
            if energy < 0 || energy > 1 {
                energy = min(1, max(0, energy))
                velocity = 0
            }
        }
        if reducedMotion || energy == 0 {
            distortion = .identity
            distortionStage = .identity
        } else {
            // Two cascaded stages form a critically damped filter: the shape eases into
            // each spectral change instead of starting at full speed.
            let fraction = 1 - exp(-elapsed / 0.05)
            distortionStage = distortionStage.blended(toward: target, fraction: fraction)
            distortion = distortion.blended(toward: distortionStage, fraction: fraction)
        }
    }

    /// Exact critically damped step, stable for any frame interval.
    static func spring(value: Double, velocity: Double, target: Double, rate: Double, elapsed: Double) -> (Double, Double) {
        let offset = value - target
        let decay = exp(-rate * elapsed)
        let term = (velocity + rate * offset) * elapsed
        return (target + (offset + term) * decay, (velocity - rate * term) * decay)
    }
}
