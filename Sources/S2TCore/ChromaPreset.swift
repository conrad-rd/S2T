import Foundation

public struct ChromaPreset: Codable, Equatable {
    public struct Curve: Codable, Equatable {
        public let x1, x2, y1, y2: Double

        public func value(_ input: Double) -> Double {
            guard input > 0, input < 1 else { return min(1, max(0, input)) }
            if x1 == y1 && x2 == y2 { return input }
            func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
                let v = 1 - t
                return 3 * v * v * t * a + 3 * v * t * t * b + t * t * t
            }
            var low = 0.0, high = 1.0
            for _ in 0..<16 {
                let t = (low + high) / 2
                if coordinate(t, x1, x2) < input { low = t } else { high = t }
            }
            return coordinate((low + high) / 2, y1, y2)
        }
    }

    public struct Sweep: Codable, Equatable {
        public let blur, brightness, height, saturation, speed, width: Double
        public let enabled: Bool
    }

    public struct Settings: Codable, Equatable {
        public let blur, centerX, centerY, effectBlur, glow, quality, scale, spread, surfaceOpacity: Double
        public let style: Int
        public let falloffCurve: Curve
        public let sweep: Sweep
    }

    public let app, appVersion, display, style: String
    public let schemaVersion: Int
    public let backgroundBlurRadiusPoints, displayHeightPoints, displayWidthPoints: Double
    public let liveDesktopActive: Bool
    public let settings: Settings

    public static let bottom = bundled("bottom")
    public static let box = bundled("box")
    public static let notch = bundled("notch")

    private static func bundled(_ name: String) -> Self {
        // These immutable resources are validated against the user's exports in the domain tests.
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("S2T_S2TCore.bundle")) }
        let url = (packaged ?? Bundle.module).url(forResource: name, withExtension: "json", subdirectory: "ChromaPresets")!
        return try! JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func falloff(_ value: Double) -> Double { settings.falloffCurve.value(value) }

    public var fieldExtent: Double {
        switch settings.style {
        case 0: return 260 * settings.scale * settings.spread + 4 * settings.effectBlur
        case 1: return 300 * settings.scale * settings.spread + 4 * settings.effectBlur
        default: return 8 * 36 * settings.scale * settings.spread + 4 * settings.effectBlur
        }
    }

    public func field(distance: Double, position: Double, sideDistance: Double = 0) -> (color: Double, blur: Double) {
        let s = settings.scale, spread = settings.spread, d = max(0, distance)
        switch settings.style {
        case 0:
            let horizontal = pow(max(0, sin(.pi * min(1, max(0, position)))), 0.42)
            let map = pow(max(0, 1 - d / (260 * s * spread)), 3.7) * horizontal
            let core = exp(-d / (2.6 * s)) * horizontal
            return (map * 0.38 + core * 0.68, map)
        case 1:
            let core = exp(-d / (3.5 * s))
            let t = min(1, max(0, (d - 220 * s * spread) / (80 * s * spread)))
            let halo = (0.30 * exp(-d / (30 * s * spread)) + 0.15 * exp(-d / (75 * s * spread))) * (1 - t * t * (3 - 2 * t))
            return (min(1, core * 0.72 + halo), distance < 0 ? 1 : halo)
        default:
            let side = exp(-pow(abs(sideDistance) / (470 * s), 4))
            let halo = side * (0.36 * exp(-d / (36 * s * spread)) + 0.72 * exp(-d / (3.8 * s)))
            return distance < 0 ? (0, 0) : (halo, min(1, halo))
        }
    }

    public func sweepPhase(time: Double) -> Double {
        let phase = 0.5 + settings.sweep.speed * time / 6
        return phase - floor(phase)
    }

    public func sweepCoverage(along: Double, perpendicular: Double, length: Double) -> Double {
        let sweep = settings.sweep
        guard sweep.enabled else { return 0 }
        let x = max(1, length * sweep.width * 0.5), y = max(0.5, sweep.height)
        let sx = hypot(x, sweep.blur), sy = hypot(y, sweep.blur)
        return min(1, sweep.brightness * x * y / (sx * sy)
            * exp(-0.5 * (pow(along / sx, 2) + pow(perpendicular / sy, 2))))
    }
}
