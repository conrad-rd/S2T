import Foundation
import CoreGraphics

public enum NotchAura {
    public static let maximumBlurRadius = BrighterEdgeStyle.Mode.notch.blurRadius
    public static func extent(strength: Double) -> Double {
        88 + 16 * min(1, max(0, strength / 1.3))
    }

    public static let colorExtent = 116.0
    public static let palette = GlowSweep.stops

    public static func colorCoverage(distance: Double, strength: Double) -> Double {
        let extent = colorExtent * (0.85 + 0.15 * min(1, max(0, strength / 1.3)))
        return GlowSweep.contourCoverage(distance: distance, extent: extent)
    }

    public static func easedCoverage(distance: Double, extent: Double) -> Double {
        let remaining = max(0, min(1, 1 - distance / max(1, extent)))
        return remaining * remaining * remaining
    }

    public static func blurCoverage(distance: Double, strength: Double) -> Double {
        easedCoverage(distance: distance, extent: extent(strength: strength))
    }

    public static func speechVisibility(energy: Double) -> Double {
        let t = min(1, max(0, energy / 0.3))
        return t * t * (3 - 2 * t)
    }

    public static func deformation(_ distortion: GlowDistortion) -> GlowDistortion {
        .identity.blended(toward: distortion, fraction: 0.45)
    }

    public static func illumination(at position: Double, distortion: GlowDistortion) -> Double {
        let x = min(1, max(0, position)) * 2 - 1
        return min(1, max(0.6, 0.82 + 0.12 * distortion.horizontal / 3 * x
            + 0.10 * distortion.vertical / 2 * (1 - abs(x)) + 0.04 * distortion.stretch * x * x))
    }

    public static func paletteBounds(layout: TopGlowLayout) -> ClosedRange<CGFloat> {
        if let notch = layout.notch {
            return (notch.minX + layout.cornerRadius)...(notch.maxX - layout.cornerRadius)
        }
        return (layout.frame.width * 0.2)...(layout.frame.width * 0.8)
    }
}
