import Foundation

public enum GlassCapsulePhase: Sendable { case listening, processing, success, failure }

public struct GlassCapsuleAnimation {
    public private(set) var phase = GlassCapsulePhase.listening
    public private(set) var previousPhase = GlassCapsulePhase.listening
    public private(set) var blend = 1.0
    public private(set) var scaleX = 1.0
    public private(set) var scaleY = 1.0
    public private(set) var offsetY = 0.0
    public private(set) var elapsed = 0.0
    private var phaseStart: Double?
    private var entranceStart: Double?
    private var previousTime: Double?
    private var energy = 0.0
    private var velocity = 0.0
    public init() {}

    public mutating func update(phase: GlassCapsulePhase, energy targetEnergy: Double, time: Double, reducedMotion: Bool) {
        if entranceStart == nil { entranceStart = time }
        if phaseStart == nil { phaseStart = time }
        if self.phase != phase {
            previousPhase = self.phase
            self.phase = phase
            phaseStart = time
        }
        elapsed = max(0, time - (phaseStart ?? time))
        let dt = min(0.05, max(0, time - (previousTime ?? time - 1.0 / 60)))
        previousTime = time
        if reducedMotion {
            blend = 1; scaleX = 1; scaleY = 1; offsetY = 0
            energy = 0; velocity = 0
            return
        }
        let target = phase == .listening && targetEnergy.isFinite ? min(1, max(0, targetEnergy)) : 0
        let decay = 18.0, frequency = 16.0
        let offset = energy - target, slope = (velocity + decay * offset) / frequency
        let wave = offset * cos(frequency * dt) + slope * sin(frequency * dt)
        energy = target + exp(-decay * dt) * wave
        velocity = exp(-decay * dt) * (frequency * (-offset * sin(frequency * dt) + slope * cos(frequency * dt)) - decay * wave)
        let t = min(1, elapsed / 0.22)
        blend = t * t * (3 - 2 * t)
        let entering = max(0, time - (entranceStart ?? time))
        let approach = -0.08 * (1 + 25 * entering) * exp(-25 * entering)
        let settle = 0.009 * exp(-pow((entering - 0.19) / 0.065, 2))
        offsetY = -10 * (1 + 24 * entering) * exp(-24 * entering)
        let success = phase == .success ? 0.009 * exp(-14 * elapsed) * sin(10 * elapsed) : 0
        scaleX = 1 + approach + settle + 0.004 * energy + success
        scaleY = 1 + approach + settle + 0.008 * energy + success
    }
}
