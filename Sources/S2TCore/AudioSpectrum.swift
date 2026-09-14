import Foundation

/// Streaming speech bands. Filter state is owned by the audio callback; only levels leave it.
public struct AudioSpectrum {
    public static let bandCount = 7
    private var filters: [Band]
    private let blend: Double

    public init(sampleRate: Double) {
        precondition(sampleRate > 0 && sampleRate.isFinite)
        let edges = [90.0, 200, 400, 800, 1600, 3200, 6000, 10000]
        filters = (0..<Self.bandCount).map { index in
            Band(low: edges[index], high: min(edges[index + 1], sampleRate * 0.45), rate: sampleRate)
        }
        blend = 1 - exp(-1 / (sampleRate * 0.018))
    }

    public mutating func consume(_ sample: Double) {
        let finite = sample.isFinite ? min(1, max(-1, sample)) : 0
        for index in filters.indices { filters[index].consume(finite, blend: blend) }
    }

    public var levels: [Double] {
        filters.map { band in
            let decibels = 10 * log10(max(0.000000000001, band.energy))
            return pow(min(1, max(0, (decibels + 62) / 42)), 1.3)
        }
    }

    private struct Band {
        var b0 = 0.0
        var a1 = 0.0
        var a2 = 0.0
        var z1 = 0.0
        var z2 = 0.0
        var energy = 0.0

        init(low: Double, high: Double, rate: Double) {
            guard high > low else { return }
            let center = sqrt(low * high)
            let omega = 2 * .pi * center / rate
            let alpha = sin(omega) / (2 * center / (high - low))
            b0 = alpha / (1 + alpha)
            a1 = -2 * cos(omega) / (1 + alpha)
            a2 = (1 - alpha) / (1 + alpha)
        }

        mutating func consume(_ sample: Double, blend: Double) {
            let output = b0 * sample + z1
            z1 = -a1 * output + z2
            z2 = -b0 * sample - a2 * output
            energy += (output * output - energy) * blend
        }
    }
}
