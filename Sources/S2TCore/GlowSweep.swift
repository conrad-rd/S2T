import Foundation

/// Captured AE values; midpoint interpolation and radial multiplication are native approximations.
public enum GlowSweep {
    public static let stops: [(position: Double, rgb: [Double])] = [
        (0, [142 / 255.0, 0, 1]), (0.33125, [0, 93 / 255.0, 1]),
        (0.825, [253 / 255.0, 90 / 255.0, 189 / 255.0]), (1, [1, 0, 250 / 255.0])
    ]
    public static let radialRadius = hypot(-933.2692413330078 - 540, -440.43817138671875 - 1080.0000457763672)
    public static func height(crest: Double, strength: Double = 1) -> Double {
        min(240, 80 + 120 * min(1, max(0, strength / 1.3)) + max(0, crest) * 0.4)
    }

    public static func brightness(energy: Double, strength: Double) -> Double {
        (0.25 + 0.75 * min(1, max(0, strength / 1.3))) * (0.8 + 0.2 * min(1, max(0, energy)))
    }

    public static func sideFade(x: Double) -> Double {
        let t = max(0, min(1, min(x, 1 - x) / 0.20))
        return t * t * (3 - 2 * t)
    }

    public static func contourCoverage(distance: Double, extent: Double, position: Double = 0.5) -> Double {
        guard distance < extent else { return 0 }
        let depth = max(0, min(1, 1 - distance / extent))
        return vertical(depth)
    }

    public static func contourHighlight(distance: Double, extent: Double) -> Double {
        let width = min(18, extent)
        let t = max(0, distance / width)
        let stops = [(0.0, 0.95), (0.10, 0.60), (0.40, 0.20), (1.0, 0.0)]
        for index in 1..<stops.count where t <= stops[index].0 {
            let a = stops[index - 1], b = stops[index]
            return a.1 + (b.1 - a.1) * (t - a.0) / (b.0 - a.0)
        }
        return 0
    }

    public static let colorOpacity = 0.50
    public static let whiteLift = 0.06
    public static let maximumBlurRadius = BrighterEdgeStyle.Mode.bottom.blurRadius

    public static func vertical(_ depth: Double) -> Double {
        let distance = 1 - max(0, min(1, depth))
        let tail = max(0, min(1, (1 - distance) / 0.25))
        return 0.9882352948188782 * exp(-6 * distance * distance) * tail * tail * (3 - 2 * tail)
    }

    public static func radial(_ distance: Double) -> Double {
        1 - pow(max(0, min(1, distance / radialRadius)), log(0.5) / log(0.540625))
    }

    public static func mask(x: Double, depth: Double) -> Double {
        vertical(depth) * radial(hypot(x * 1080 - 540, max(0, min(1, depth)) * 1080 - 1080)) * sideFade(x: x)
    }

}
