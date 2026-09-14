import Foundation

public enum ProcessingSweep {
    public struct Stop: Equatable {
        public let position: Double
        public let rgb: [Double]
        public let opacity: Double
    }

    public static let stops: [Stop] = [
        .init(position: 0, rgb: [0.68, 0.4, 1], opacity: 0),
        .init(position: 0.25, rgb: [0.68, 0.4, 1], opacity: 0.8),
        .init(position: 0.55, rgb: [0.28, 0.55, 1], opacity: 1),
        .init(position: 0.66, rgb: [1, 1, 1], opacity: 1),
        .init(position: 0.76, rgb: [1, 1, 1], opacity: 1),
        .init(position: 0.84, rgb: [0.28, 0.55, 1], opacity: 0.95),
        .init(position: 1, rgb: [0.28, 0.55, 1], opacity: 0)
    ]

    public static let orbitStops: [Stop] = stops.map {
        Stop(position: $0.position * 0.30, rgb: $0.rgb, opacity: $0.opacity)
    } + [Stop(position: 1, rgb: [0.28, 0.55, 1], opacity: 0)]

    public static func phase(time: Double, reducedMotion: Bool) -> Double {
        if reducedMotion { return 0.25 }
        let turns = time / 2.8
        return turns - floor(turns)
    }
}
