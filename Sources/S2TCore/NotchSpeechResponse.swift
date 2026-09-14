import Foundation

/// Bridges short microphone gaps for the notch and input glows.
public struct NotchSpeechResponse {
    public private(set) var energy = 0.0
    public private(set) var distortion = GlowDistortion.identity
    private var previousTime: Double?
    private var silenceStarted: Double?
    private var silenceEnergy = 0.0

    public init() {}

    public mutating func update(level: Double, bands: [Double], time: Double, reducedMotion: Bool, active: Bool = true) {
        guard active else {
            energy = 0
            distortion = .identity
            previousTime = time
            silenceStarted = nil
            return
        }
        let level = level.isFinite ? level : 0
        let targetEnergy = pow(max(0, min(1, (level - 0.06) / 0.94)), 0.7)
        let target = GlowDistortion(bands: bands, reducedMotion: reducedMotion)
        guard let previous = previousTime, time >= previous, time - previous < 0.5 else {
            energy = targetEnergy
            distortion = target
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
            }
            let progress = min(1, max(0, (time - silenceStarted! - 0.11) / 0.32))
            energy = silenceEnergy * (1 - progress) * (1 - progress)
        } else {
            silenceStarted = nil
            let duration = targetEnergy > energy ? 0.09 : 0.24
            energy += (targetEnergy - energy) * (1 - exp(-elapsed / duration))
        }
        if reducedMotion || energy == 0 {
            distortion = .identity
        } else {
            distortion = distortion.blended(toward: target, fraction: 1 - exp(-elapsed / 0.12))
        }
    }
}
