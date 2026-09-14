import Foundation

public struct GlowResponseSettings: Equatable {
    public var width: Double
    public var minimum: Double
    // Bounded expansion fits the original padding. Slider edits must not resize the panel.
    public var paddingScale: Double { 1 }
    public var maximum: Double
    public var tuning: GlowTuning
    public init(width: Double = 1, minimum: Double = 0.3, maximum: Double = 2, tuning: GlowTuning = .init()) {
        self.width = min(1, max(0.25, width))
        self.minimum = min(2, max(0, minimum))
        self.maximum = min(5, max(self.minimum, maximum))
        self.tuning = tuning.normalized
    }
}

public enum GlowSpeechEnvelope {
    public static func gain(energy: Double, selected: Double, settings: GlowResponseSettings = .init()) -> Double {
        let energy = energy.isFinite ? min(1, max(0, energy)) : 0
        return min(1, max(0, selected / 1.3)) * (settings.minimum + (settings.maximum - settings.minimum) * energy)
    }

    public static func expansion(energy: Double, selected: Double, reducedMotion: Bool, settings: GlowResponseSettings = .init()) -> Double {
        if reducedMotion { return min(1, max(0, selected / 1.3)) }
        let amount = gain(energy: energy, selected: selected, settings: settings)
        return 2 * amount / (1 + amount)
    }

    /// Raise useful blur at low amounts, then approach a ceiling without a hard clamp.
    public static func blurGain(_ amount: Double) -> Double {
        let amount = amount.isFinite ? min(5, max(0, amount)) : 0
        return 2 * amount / (amount + 1.0 / 3)
    }
}
