import Foundation

/// A closed color loop. Stop identities survive dragging past other colors.
public struct GlowGradient: Codable, Equatable {
    public struct Stop: Codable, Equatable, Identifiable {
        public let id: UUID
        public var position: Double
        public var color: SIMD3<Double>
        public init(id: UUID = UUID(), position: Double, color: SIMD3<Double>) {
            self.id = id
            self.position = position
            self.color = color
        }
        private enum CodingKeys: CodingKey { case id, position, color }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(id: try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                      position: try values.decode(Double.self, forKey: .position),
                      color: try values.decode(SIMD3<Double>.self, forKey: .color))
        }
    }

    public private(set) var stops: [Stop]
    public static let defaultStops: [Stop] = GlowColorCycle.colors.enumerated().map {
        .init(position: Double($0.offset) / Double(GlowColorCycle.colors.count), color: $0.element / 255)
    }

    public init(stops: [Stop] = defaultStops) {
        var seen = Set<UUID>()
        let clean = stops.filter { $0.position.isFinite }.map { stop -> Stop in
            let id = seen.insert(stop.id).inserted ? stop.id : UUID()
            return Stop(id: id, position: min(1, max(0, stop.position)), color: Self.boundedColor(stop.color))
        }
        self.stops = clean.isEmpty ? Self.defaultStops : clean
        sortStops()
    }

    private enum CodingKeys: CodingKey { case stops }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Older preferences may contain an enabled flag. Keep their colors; editing is now always available.
        self.init(stops: try values.decodeIfPresent([Stop].self, forKey: .stops) ?? Self.defaultStops)
    }

    public var isDefault: Bool {
        stops.count == Self.defaultStops.count && zip(stops, Self.defaultStops).allSatisfy {
            $0.position == $1.position && $0.color == $1.color
        }
    }
    public func index(of id: UUID) -> Int? { stops.firstIndex { $0.id == id } }

    public mutating func setColor(_ color: SIMD3<Double>, id: UUID) {
        guard let index = index(of: id) else { return }
        stops[index].color = Self.boundedColor(color)
    }

    public mutating func moveStop(id: UUID, to position: Double) {
        guard let index = index(of: id), position.isFinite else { return }
        stops[index].position = min(1, max(0, position))
        sortStops()
    }

    public mutating func spaceEvenly() {
        for i in stops.indices { stops[i].position = Double(i) / Double(stops.count) }
    }

    @discardableResult public mutating func addStop(at requested: Double? = nil) -> UUID {
        let position: Double
        if let requested, requested.isFinite { position = min(1, max(0, requested)) }
        else {
            let gaps = stops.indices.map { i in
                (i == stops.count - 1 ? stops[0].position + 1 : stops[i + 1].position) - stops[i].position
            }
            let i = gaps.indices.max(by: { gaps[$0] < gaps[$1] })!
            position = (stops[i].position + gaps[i] / 2).truncatingRemainder(dividingBy: 1)
        }
        let stop = Stop(position: position, color: sampler.color(at: position))
        stops.append(stop)
        sortStops()
        return stop.id
    }

    public mutating func removeStop(id: UUID) {
        guard stops.count > 1, let index = index(of: id) else { return }
        stops.remove(at: index)
    }

    private mutating func sortStops() {
        stops = stops.enumerated().sorted {
            $0.element.position == $1.element.position ? $0.offset < $1.offset : $0.element.position < $1.element.position
        }.map(\.element)
    }
    private static func boundedColor(_ color: SIMD3<Double>) -> SIMD3<Double> {
        var result = color
        for channel in 0..<3 { result[channel] = color[channel].isFinite ? min(1, max(0, color[channel])) : 0 }
        return result
    }

    public var sampler: Sampler { Sampler(stops: stops) }

    public struct Sampler {
        private let stops: [Stop]
        private let labs: [SIMD3<Double>]
        fileprivate init(stops: [Stop]) {
            self.stops = stops
            labs = stops.map { OKLab.fromSRGB($0.color) }
        }
        public func color(at position: Double) -> SIMD3<Double> {
            guard position.isFinite else { return stops[0].color }
            let x = position - floor(position)
            let upper = stops.firstIndex { $0.position > x } ?? stops.count
            let lower = upper == 0 ? stops.count - 1 : upper - 1
            let next = upper % stops.count
            let start = stops[lower].position - (upper == 0 ? 1 : 0)
            let end = stops[next].position + (upper == stops.count ? 1 : 0)
            let amount = (x - start) / (end - start)
            if amount == 0 || stops.count == 1 { return stops[lower].color }
            return OKLab.toSRGB(labs[lower] + (labs[next] - labs[lower]) * amount)
        }
    }
}

/// Björn Ottosson's public-domain OKLab matrices, with sRGB transfer functions.
/// https://bottosson.github.io/posts/oklab/
public enum OKLab {
    public static func fromSRGB(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
        let l = cbrt(0.4122214708*r + 0.5363325363*g + 0.0514459929*b)
        let m = cbrt(0.2119034982*r + 0.6806995451*g + 0.1073969566*b)
        let s = cbrt(0.0883024619*r + 0.2817188376*g + 0.6299787005*b)
        return SIMD3(0.2104542553*l + 0.7936177850*m - 0.0040720468*s,
                     1.9779984951*l - 2.4285922050*m + 0.4505937099*s,
                     0.0259040371*l + 0.7827717662*m - 0.8086757660*s)
    }
    public static func toSRGB(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let l = pow(lab.x + 0.3963377774*lab.y + 0.2158037573*lab.z, 3)
        let m = pow(lab.x - 0.1055613458*lab.y - 0.0638541728*lab.z, 3)
        let s = pow(lab.x - 0.0894841775*lab.y - 1.2914855480*lab.z, 3)
        func encoded(_ v: Double) -> Double {
            min(1, max(0, v <= 0.0031308 ? 12.92*v : 1.055*pow(v, 1 / 2.4) - 0.055))
        }
        return SIMD3(encoded(4.0767416621*l - 3.3077115913*m + 0.2309699292*s),
                     encoded(-1.2684380046*l + 2.6097574011*m - 0.3413193965*s),
                     encoded(-0.0041960863*l - 0.7034186147*m + 1.7076147010*s))
    }
}
