import Foundation

public struct GlowTuning: Codable, Equatable {
    public var backgroundBlur: Double
    public var softness: Double
    public var inputSizeEnabled: Bool
    public var inputMinimumSize: Double
    public var inputMaximumSize: Double
    public var falloff: Double
    public var edgeBrightness: Double
    public var edgeBlur: Double
    public var edgeGlow: Double
    public var edgeHeight: Double
    public var edgeOpacity: Double
    public var gradientSpeed: Double
    public var gradients: [String: GlowGradient]
    public var bodyOpacity: Double

    public init(backgroundBlur: Double = 1, softness: Double = 0, falloff: Double = 1, edgeBrightness: Double = 1,
                edgeBlur: Double = 0, edgeGlow: Double = 0, edgeHeight: Double = 1, edgeOpacity: Double = 1,
                bodyOpacity: Double = 1, gradientSpeed: Double = 0.1, gradients: [String: GlowGradient] = [:],
                inputSizeEnabled: Bool = false, inputMinimumSize: Double = 0.65, inputMaximumSize: Double = 1.3) {
        self.gradients = gradients
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        self.inputSizeEnabled = inputSizeEnabled
        self.inputMinimumSize = bounded(inputMinimumSize, 0.5...2, 0.65)
        self.inputMaximumSize = max(self.inputMinimumSize, bounded(inputMaximumSize, 0.5...2, 1.3))
        self.backgroundBlur = bounded(backgroundBlur, 0...2, 1)
        self.softness = bounded(softness, 0...12, 0)
        self.falloff = bounded(falloff, 0.5...2, 1)
        self.edgeBrightness = bounded(edgeBrightness, 0...2, 1)
        self.edgeBlur = bounded(edgeBlur, 0...12, 0)
        self.edgeGlow = bounded(edgeGlow, 0...2, 0)
        self.edgeHeight = bounded(edgeHeight, 0...1, 1)
        self.edgeOpacity = bounded(edgeOpacity, 0...1, 1)
        self.gradientSpeed = bounded(gradientSpeed, 0...1, 0.1)
        self.bodyOpacity = bounded(bodyOpacity, 0...1, 1)
    }

    private enum CodingKeys: String, CodingKey {
        case inputSizeEnabled, inputMinimumSize, inputMaximumSize, backgroundBlur, softness, falloff, edgeBrightness, edgeBlur, edgeGlow, edgeHeight, edgeOpacity, bodyOpacity, gradientSpeed, gradients
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(backgroundBlur: try values.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 1,
                  softness: try values.decodeIfPresent(Double.self, forKey: .softness) ?? 0,
                  falloff: try values.decodeIfPresent(Double.self, forKey: .falloff) ?? 1,
                  edgeBrightness: try values.decodeIfPresent(Double.self, forKey: .edgeBrightness) ?? 1,
                  edgeBlur: try values.decodeIfPresent(Double.self, forKey: .edgeBlur) ?? 0,
                  edgeGlow: try values.decodeIfPresent(Double.self, forKey: .edgeGlow) ?? 0,
                  edgeHeight: try values.decodeIfPresent(Double.self, forKey: .edgeHeight) ?? 1,
                  edgeOpacity: try values.decodeIfPresent(Double.self, forKey: .edgeOpacity) ?? 1,
                  bodyOpacity: try values.decodeIfPresent(Double.self, forKey: .bodyOpacity) ?? 1,
                  gradientSpeed: try values.decodeIfPresent(Double.self, forKey: .gradientSpeed) ?? 0.1,
                  gradients: try values.decodeIfPresent([String: GlowGradient].self, forKey: .gradients) ?? [:],
                  inputSizeEnabled: try values.decodeIfPresent(Bool.self, forKey: .inputSizeEnabled) ?? false,
                  inputMinimumSize: try values.decodeIfPresent(Double.self, forKey: .inputMinimumSize) ?? 0.65,
                  inputMaximumSize: try values.decodeIfPresent(Double.self, forKey: .inputMaximumSize) ?? 1.3)
    }

    public var normalized: Self {
        .init(backgroundBlur: backgroundBlur, softness: softness, falloff: falloff, edgeBrightness: edgeBrightness,
              edgeBlur: edgeBlur, edgeGlow: edgeGlow, edgeHeight: edgeHeight, edgeOpacity: edgeOpacity, bodyOpacity: bodyOpacity, gradientSpeed: gradientSpeed, gradients: gradients, inputSizeEnabled: inputSizeEnabled,
              inputMinimumSize: inputMinimumSize, inputMaximumSize: inputMaximumSize)
    }

    public func forInput(size: CGSize, preview: Bool = false) -> Self {
        guard inputSizeEnabled else { return self }
        var result = normalized
        // The shorter dimension prevents a wide single-line field from getting a large glow.
        let progress = min(1, max(0, (min(size.width, size.height) - 32) / 208))
        let blend = preview ? 1 : progress * progress * (3 - 2 * progress)
        let amount = preview ? result.inputMaximumSize : result.inputMinimumSize + (result.inputMaximumSize - result.inputMinimumSize) * blend
        result.falloff = falloff / amount
        return result
    }

    public static func coverage(_ value: Double, distance: Double, extent: Double, falloff: Double) -> Double {
        guard falloff != 1 else { return value }
        let alpha = pow(min(1, max(0, value)), falloff)
        guard falloff < 1 else { return alpha }
        // A longer tail must still finish inside the reserved field.
        let t = min(1, max(0, (distance / extent - 0.65) / 0.35))
        return alpha * (1 - t * t * (3 - 2 * t))
    }
}
