import Foundation

/// Bottom uses the approved E study. Contours fit the same transfer to their native exterior bands.
public enum BrighterEdgeStyle {
    public enum Mode: CaseIterable {
        case bottom, notch, input
        public var fieldScale: Double { self == .input ? 1.5 : self == .notch ? 1.2 : 1 }
        public var blurRadius: Double { self == .input ? 18 : 12 }
    }

    public struct Field {
        public let color: SIMD3<Double>
        public let alpha: Double
        public let edgeColor: SIMD3<Double>
        public let edgeAlpha: Double
        public let blur: Double
    }

    private static let colors = [SIMD3<Double>(142, 0, 255), SIMD3<Double>(0, 93, 255),
                                 SIMD3<Double>(253, 90, 189), SIMD3<Double>(255, 0, 250)]
    private static let stops = [0.0, 0.33, 0.83, 1.0]

    public static func hue(mode: Mode, x: Double, y: Double) -> SIMD3<Double> {
        let position = clamp(x / 1080)
        let next = position <= stops[1] ? 1 : position <= stops[2] ? 2 : 3
        let fraction = (position - stops[next - 1]) / (stops[next] - stops[next - 1])
        let rgb = (colors[next - 1] * (1 - fraction) + colors[next] * fraction) / 255
        return SIMD3(linear(rgb.x), linear(rgb.y), linear(rgb.z))
    }

    public static func sample(mode: Mode, distance: Double, x: Double, y: Double,
                              hue suppliedHue: SIMD3<Double>? = nil) -> Field {
        let d = max(0, distance) * mode.fieldScale
        let lateral = mode == .bottom ? pow(max(0, sin(.pi * clamp(x / 1080))), 0.48) : 1
        let coverage = 0.52 * pow(max(0, 1 - d / 310), 3) * lateral
        let blur = pow(max(0, 1 - d / 265), 2.3) * lateral
        let rim = 0.98 * exp(-max(0, d - 5) / 15) * lateral
        let white = 0.09
        let lift = clamp(0.20 * pow(max(0, 1 - d / 320), 1.2) * min(1, d / 24) * lateral * 1.08)
        let hue = suppliedHue ?? hue(mode: mode, x: x, y: y)
        let linearColor = hue * (1 - white) + SIMD3(repeating: white)
        let color = SIMD3(srgb(linearColor.x), srgb(linearColor.y), srgb(linearColor.z))
        let body = clamp(coverage * 1.08)
        let alpha = clamp(max(coverage * 1.08, rim * 1.35))
        let bodyAlpha = body + lift * (1 - body)
        let bodyColor = bodyAlpha > 0 ? (color * body + SIMD3(repeating: lift * (1 - body))) / bodyAlpha : .zero
        // Over-compositing this anchored edge gives exactly max(body, rim), without doubling the halo.
        let edgeAlpha = body < 1 ? (alpha - body) / (1 - body) : 0
        return Field(color: bodyColor, alpha: bodyAlpha, edgeColor: color, edgeAlpha: edgeAlpha, blur: blur)
    }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private static func linear(_ x: Double) -> Double { x > 0.04045 ? pow((x + 0.055) / 1.055, 2.4) : x / 12.92 }
    private static func srgb(_ x: Double) -> Double { x > 0.0031308 ? 1.055 * pow(x, 1 / 2.4) - 0.055 : x * 12.92 }
}
