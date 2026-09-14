import Foundation

/// Broad movement of the existing light field, derived from spectral balance.
public struct GlowDistortion: Equatable {
    public let horizontal: Double
    public let vertical: Double
    public let stretch: Double
    public static let identity = GlowDistortion(horizontal: 0, vertical: 0, stretch: 0)

    private init(horizontal: Double, vertical: Double, stretch: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.stretch = stretch
    }

    public init(bands: [Double], reducedMotion: Bool = false) {
        let clean = (0..<AudioSpectrum.bandCount).map { index in
            index < bands.count && bands[index].isFinite ? min(1, max(0, bands[index])) : 0
        }
        let peak = clean.max() ?? 0
        guard !reducedMotion, peak > 0.04 else { self = .identity; return }
        let weights = clean.map { pow($0 / peak, 2) }
        let total = weights.reduce(0, +)
        let gate = min(1, (peak - 0.04) / 0.08)
        let centroid = weights.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element } / total
        let middle = weights[2...4].reduce(0, +) / total
        horizontal = (centroid - 3) * gate
        vertical = (middle - 3.0 / 7) * 3 * gate
        stretch = (weights[0] + weights[6] - weights[3]) / total * gate
    }

    public var isIdentity: Bool { self == .identity }

    public func blended(toward target: Self, fraction: Double) -> Self {
        let t = min(1, max(0, fraction))
        return Self(horizontal: horizontal + (target.horizontal - horizontal) * t,
                    vertical: vertical + (target.vertical - vertical) * t,
                    stretch: stretch + (target.stretch - stretch) * t)
    }
}
