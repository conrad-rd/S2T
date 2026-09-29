import Foundation
import S2TCore

/// The approved reference supplies only light and motion. Its colors are never used at runtime.
enum ReferenceLoadingField {
    static let duration = 1.8
    static let paletteDuration = duration * 2
    static let verticalCycles = 1.17

    static func phase(heightFraction: Double, time: Double) -> Double {
        (heightFraction * verticalCycles + time.truncatingRemainder(dividingBy: duration) / duration) * 2 * .pi
    }

    struct Frame {
        let time: Double
        private let palette: ProcessingPalette
        private let position: Double

        init(time: Double, gradient: GlowGradient) {
            self.time = time
            palette = ProcessingPalette(gradient)
            position = time.truncatingRemainder(dividingBy: paletteDuration) / paletteDuration
        }

        func paletteColor(at position: Double) -> SIMD3<Double> {
            palette.color(at: position + self.position)
        }

        var rim: SIMD3<Float> {
            let saved = OKLab.fromSRGB(paletteColor(at: -0.25))
            let chroma = hypot(saved.y, saved.z)
            let tint = chroma > 0.0001 ? min(1, 0.09 / chroma) : 0
            return Self.linear(OKLab.toSRGB(SIMD3(0.86, saved.y * tint, saved.z * tint)))
        }

        func lightPalettePosition(heightFraction: Double) -> Double {
            // The complete gradient spans two consecutive waves. Colors travel
            // upward with the light, with half the saved spacing in each wave.
            position + heightFraction * verticalCycles / 2 - 0.25
        }

        func row(heightFraction: Double) -> Row {
            let p = phase(heightFraction: heightFraction, time: time)
            // Sample the saved stops in order across the two-wave color field.
            let saved = OKLab.fromSRGB(palette.color(at: lightPalettePosition(heightFraction: heightFraction)))
            // Measured scalar light/chroma envelopes from the approved reference.
            // The saved gradient alone supplies hue; it is never spread into columns.
            let lightness = 0.644727 + 0.205585 * cos(p) - 0.079190 * sin(p)
                + 0.000196 * cos(2 * p) + 0.001478 * sin(2 * p)
            let referenceChroma = 0.115666 - 0.039738 * cos(p) + 0.014232 * sin(p)
                - 0.011019 * cos(2 * p) + 0.008770 * sin(2 * p)
            let chroma = hypot(saved.y, saved.z)
            let tint = chroma > 0.0001 ? min(1, referenceChroma / chroma) : 0
            let rgb = OKLab.toSRGB(SIMD3(lightness, saved.y * tint, saved.z * tint))
            return Row(color: Self.linear(rgb), phase: p)
        }

        private static func linear(_ rgb: SIMD3<Double>) -> SIMD3<Float> {
            func channel(_ value: Double) -> Float {
                Float(value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
            }
            return SIMD3(channel(rgb.x), channel(rgb.y), channel(rgb.z))
        }
    }

    struct Row {
        let color: SIMD3<Float>
        let phase: Double
        let shoulder: Double

        init(color: SIMD3<Float>, phase: Double) {
            self.color = color; self.phase = phase
            shoulder = exp(-3 * (1 - cos(phase - 0.6)))
        }

        static func across(widthFraction: Double) -> Double {
            exp(-0.5 * pow((widthFraction - 0.4) / 0.38, 2))
        }

        func opening(widthFraction: Double) -> Float {
            // Open the luminous shoulder. Making the dark fold transparent
            // washes away the reference's depth over light message bars.
            return Float(Self.across(widthFraction: widthFraction) * shoulder)
        }

        func sample(widthFraction: Double) -> SIMD4<Float> {
            sample(opening: opening(widthFraction: widthFraction))
        }

        func sample(opening: Float) -> SIMD4<Float> {
            let alpha = 0.97 - 0.37 * opening
            return SIMD4(color.x * alpha, color.y * alpha, color.z * alpha, alpha)
        }

        func blur(widthFraction: Double) -> Float { 0.08 + 0.32 * opening(widthFraction: widthFraction) }
    }
}

/// Continuous slopes remove the vertical seams of piecewise-linear color stops.
/// Tangents stay within neighboring slopes, preserving each saved color without overshoot.
private struct ProcessingPalette {
    private let positions: [Double]
    private let colors: [SIMD3<Double>]
    private let labs: [SIMD3<Double>]
    private let tangents: [SIMD3<Double>]

    init(_ gradient: GlowGradient) {
        // Keep 0% and 100% distinct, as in the editor. Only the sample position
        // wraps; wrapping the stops discards the first color at the loop seam.
        var stops = [GlowGradient.Stop]()
        for stop in gradient.stops {
            if let previous = stops.last, previous.position == stop.position, previous.color == stop.color { continue }
            stops.append(stop)
        }
        positions = stops.map(\.position)
        colors = stops.map(\.color)
        labs = colors.map(OKLab.fromSRGB)
        let count = positions.count
        var slopes = [SIMD3<Double>]()
        for index in 0..<count {
            let next = (index + 1) % count
            let span = positions[next] + (next == 0 ? 1 : 0) - positions[index]
            // Coincident stops form an intentional color boundary. Zero slopes
            // preserve both sides without dividing by a zero-length interval.
            slopes.append(span > 0 ? (labs[next] - labs[index]) / span : .zero)
        }
        let savedColors = colors
        tangents = (0..<count).map { index in
            let previous = slopes[(index + count - 1) % count], next = slopes[index]
            var tangent = SIMD3<Double>.zero
            // A saturated stop lies on the display gamut boundary. Ease into it
            // so RGB clipping cannot turn an otherwise smooth tangent into a seam.
            if (0..<3).contains(where: { savedColors[index][$0] <= 0.001 || savedColors[index][$0] >= 0.999 }) {
                return tangent
            }
            for channel in 0..<3 where previous[channel] * next[channel] > 0 {
                tangent[channel] = (next[channel] < 0 ? -1 : 1) * min(abs(previous[channel]), abs(next[channel]))
            }
            return tangent
        }
    }

    func color(at position: Double) -> SIMD3<Double> {
        guard position.isFinite, positions.count > 1 else { return colors[0] }
        let x = position - floor(position)
        let upper = positions.firstIndex { $0 > x } ?? positions.count
        let lower = upper == 0 ? positions.count - 1 : upper - 1
        let next = upper % positions.count
        let start = positions[lower] - (upper == 0 ? 1 : 0)
        let end = positions[next] + (upper == positions.count ? 1 : 0)
        let span = end - start, t = (x - start) / span
        if t == 0 { return colors[lower] }
        let t2 = t * t, t3 = t2 * t
        let value = labs[lower] * (2*t3 - 3*t2 + 1) + tangents[lower] * (span * (t3 - 2*t2 + t))
            + labs[next] * (-2*t3 + 3*t2) + tangents[next] * (span * (t3 - t2))
        return OKLab.toSRGB(value)
    }
}
