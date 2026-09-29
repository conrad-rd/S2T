import AppKit
import S2TCore

/// A curved inner lens that resamples the completed, blurred color field.
enum ProcessingGlassRefraction {
    enum Surface { case messageBar, indicator }

    static func messageBarVisibility(alpha: Float, edge: Float = 0, heightFraction: Float = 0) -> Float {
        let sheen = max(0, min(1, (0.97 - alpha) / 0.37))
        let lower = max(0, min(1, (heightFraction - 0.55) / 0.45))
        return 0.010 + 0.11 * sheen + 0.16 * edge * lower * lower * (3 - 2 * lower)
    }

    private final class Mapping {
        let samples: [SIMD2<Float>]
        let glow: [Float]
        let core: [Float]
        let coverage: [Float]
        let softening: [Float]
        init(_ samples: [SIMD2<Float>], glow: [Float], core: [Float], coverage: [Float], softening: [Float]) {
            self.samples = samples; self.glow = glow; self.core = core
            self.coverage = coverage; self.softening = softening
        }
    }
    private static let cache: NSCache<NSString, Mapping> = {
        let cache = NSCache<NSString, Mapping>()
        cache.countLimit = 4
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    static func apply(_ pixels: [Float], width: Int, height: Int, size: CGSize, contour: InputContour,
                      rim: SIMD3<Float>? = nil, surface: Surface = .indicator) -> [Float] {
        let key = "\(width)-\(height)-\(size)-\(contour)" as NSString
        let mapping: Mapping
        if let cached = cache.object(forKey: key) { mapping = cached }
        else {
            let boundary = ProcessingGlassBoundary(contour: contour)
            let band = min(36, max(10, min(contour.bounds.width, contour.bounds.height) * 0.22))
            var samples = [SIMD2<Float>](repeating: .zero, count: width * height)
            var glow = [Float](repeating: 0, count: width * height)
            var core = glow
            var coverage = glow
            var softening = glow
            let depths = boundary.depths(width: width, height: height, size: size)
            var left = [Double](repeating: size.width, count: height), right = [Double](repeating: 0, count: height)
            var top = [Double](repeating: size.height, count: width), bottom = [Double](repeating: 0, count: width)
            for y in 0..<height { for x in 0..<width {
                let point = CGPoint(
                    x: (Double(x) + 0.5) / Double(width) * size.width,
                    y: (Double(y) + 0.5) / Double(height) * size.height)
                let depth = depths[y * width + x]
                if depth >= 0 {
                    left[y] = min(left[y], point.x); right[y] = max(right[y], point.x)
                    top[x] = min(top[x], point.y); bottom[x] = max(bottom[x], point.y)
                }
            } }
            let wrapWidth = min(64, min(size.height * 0.28, size.width * 0.18))
            let shoulder = max(3, wrapWidth * 0.75)
            for y in 0..<height where left[y] > right[y] { left[y] = 0; right[y] = size.width }
            for x in 0..<width where top[x] > bottom[x] { top[x] = 0; bottom[x] = size.height }
            left = smooth(left, radius: shoulder * Double(height) / size.height)
            right = smooth(right, radius: shoulder * Double(height) / size.height)
            top = smooth(top, radius: wrapWidth * Double(width) / size.width)
            bottom = smooth(bottom, radius: wrapWidth * Double(width) / size.width)
            func attraction(_ distance: Double, width: Double) -> Double {
                let t = max(0, distance) / max(1, width)
                let tail = min(1, max(0, 3 - t))
                return exp(-0.5 * t * t) * tail * tail * (3 - 2 * tail)
            }
            for y in 0..<height { for x in 0..<width {
                let point = CGPoint(x: (Double(x) + 0.5) / Double(width) * size.width,
                                    y: (Double(y) + 0.5) / Double(height) * size.height)
                let depth = depths[y * width + x]
                let edge = min(1, max(0, depth / 3.5))
                coverage[y * width + x] = Float(edge * edge * (3 - 2 * edge))
                let transition = min(1, max(0, (depth - band) / 12))
                softening[y * width + x] = Float(1 - transition * transition * (3 - 2 * transition))
                var source = point
                if depth >= 0 && depth < band {
                    let broad = band * 0.4
                    let t = min(1, (band - depth) / (band * 0.2))
                    let fade = t * t * (3 - 2 * t)
                    glow[y * width + x] = Float(exp(-0.5 * pow(depth / broad, 2)) * fade)
                    core[y * width + x] = Float(0.48 * exp(-0.5 * pow((depth - 2.5) / 2.2, 2)))
                }
                // Smooth spans of the merged outline carry the curl farther
                // into the wave without switching direction at footer shoulders.
                let fromLeft = attraction(point.x - left[y], width: wrapWidth)
                let fromRight = attraction(right[y] - point.x, width: wrapWidth)
                let middle = (top[x] + bottom[x]) * 0.5
                let compression = 0.62 * max(fromLeft, fromRight)
                source.x += (fromLeft - fromRight) * min(8, size.height * 0.05)
                source.y += (middle - point.y) * compression
                let lipWidth = min(8, size.height * 0.04)
                source.y += (1 - compression) * min(5, size.height * 0.03)
                    * (attraction(point.y - top[x], width: lipWidth)
                       - attraction(bottom[x] - point.y, width: lipWidth))
                samples[y * width + x] = SIMD2(Float(source.x / size.width * Double(width) - 0.5),
                                               Float(source.y / size.height * Double(height) - 0.5))
            } }
            mapping = Mapping(samples, glow: glow, core: core, coverage: coverage, softening: softening)
            cache.setObject(mapping, forKey: key, cost: samples.count * (MemoryLayout<SIMD2<Float>>.stride + 4 * MemoryLayout<Float>.stride))
        }
        var result = pixels
        for index in mapping.samples.indices {
            let point = mapping.samples[index]
            let sx = min(Float(width - 1), max(0, point.x)), sy = min(Float(height - 1), max(0, point.y))
            let x0 = Int(sx), y0 = Int(sy), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = sx - Float(x0), fy = sy - Float(y0)
            for channel in 0..<4 {
                let top = pixels[(y0 * width + x0) * 4 + channel] * (1 - fx) + pixels[(y0 * width + x1) * 4 + channel] * fx
                let bottom = pixels[(y1 * width + x0) * 4 + channel] * (1 - fx) + pixels[(y1 * width + x1) * 4 + channel] * fx
                result[index * 4 + channel] = top * (1 - fy) + bottom * fy
            }
        }
        if let rim {
            // Let the passing wave light the broad reflection. Source-over
            // composition retains its gradients instead of clipping them white.
            for index in mapping.glow.indices {
                let wrap = mapping.glow[index]
                let core = mapping.core[index]
                guard wrap + core > 0 else { continue }
                let offset = index * 4
                let alpha = max(0.0001, result[offset + 3])
                let local = SIMD3(result[offset], result[offset + 1], result[offset + 2]) / alpha
                let luminance = max(0, min(1, local.x * 0.2126 + local.y * 0.7152 + local.z * 0.0722))
                let reflection = wrap * (0.44 + 0.55 * sqrt(luminance))
                for channel in 0..<3 {
                    let light = min(1, rim[channel] * 1.3 + local[channel] * 0.4)
                    let reflected = result[offset + channel] * (1 - reflection) + light * reflection
                    result[offset + channel] = reflected * (1 - core) + core
                }
                result[offset + 3] = 1 - (1 - result[offset + 3]) * (1 - reflection) * (1 - core)
            }
        }
        // Smooth the completed lens and reflection, not just their source light.
        // Coverage is applied afterwards so native blur cannot leak outside.
        let softened = ProcessingDiffusion.soften(result, width: width, height: height, size: size, radius: 3.5)
        for index in mapping.coverage.indices {
            let alpha = result[index * 4 + 3] + (softened[index * 4 + 3] - result[index * 4 + 3]) * mapping.softening[index]
            // Preserve the complete curled light, but reveal the actual message
            // bar between moving highlights. Most color stays at the perimeter.
            let visibility = surface == .messageBar && rim != nil
                ? messageBarVisibility(alpha: alpha, edge: mapping.glow[index],
                    heightFraction: (Float(index / width) + 0.5) / Float(height)) : 1
            for channel in 0..<4 {
                let offset = index * 4 + channel
                result[offset] += (softened[offset] - result[offset]) * mapping.softening[index]
                result[offset] *= mapping.coverage[index] * visibility
            }
        }
        return result
    }

    private static func smooth(_ values: [Double], radius: Double) -> [Double] {
        let extent = Int(ceil(radius * 3))
        let weights = (-extent...extent).map { exp(-0.5 * pow(Double($0) / max(1, radius), 2)) }
        let total = weights.reduce(0, +)
        return values.indices.map { index in
            (-extent...extent).reduce(0.0) { sum, offset in
                sum + values[min(values.count - 1, max(0, index + offset))] * weights[offset + extent]
            } / total
        }
    }
}

/// Interior distance must follow the merged perimeter. The minimum of each
/// part's signed distance leaves false edges where an editor meets its controls.
private struct ProcessingGlassBoundary {
    private struct Segment {
        let start: CGPoint
        let delta: CGPoint
        let lengthSquared: Double
        let bounds: CGRect
    }
    private let path: CGPath
    private let bounds: CGRect
    private let segments: [Segment]

    init(contour: InputContour) {
        path = contour.path.cgPath
        bounds = contour.bounds
        var edges = [Segment]()
        var current = CGPoint.zero, start = CGPoint.zero
        func append(_ point: CGPoint) {
            let delta = CGPoint(x: point.x - current.x, y: point.y - current.y)
            let length = delta.x * delta.x + delta.y * delta.y
            if length > 0 {
                edges.append(Segment(start: current, delta: delta, lengthSquared: length,
                    bounds: CGRect(x: min(current.x, point.x), y: min(current.y, point.y),
                        width: abs(delta.x), height: abs(delta.y))))
            }
            current = point
        }
        path.applyWithBlock { item in
            let element = item.pointee
            switch element.type {
            case .moveToPoint: current = element.points[0]; start = current
            case .addLineToPoint: append(element.points[0])
            case .addQuadCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1]
                for index in 1...32 {
                    let t = Double(index) / 32, v = 1 - t
                    append(CGPoint(x: v*v*a.x + 2*v*t*b.x + t*t*c.x,
                        y: v*v*a.y + 2*v*t*b.y + t*t*c.y))
                }
            case .addCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1], d = element.points[2]
                for index in 1...32 {
                    let t = Double(index) / 32, v = 1 - t
                    append(CGPoint(x: v*v*v*a.x + 3*v*v*t*b.x + 3*v*t*t*c.x + t*t*t*d.x,
                        y: v*v*v*a.y + 3*v*v*t*b.y + 3*v*t*t*c.y + t*t*t*d.y))
                }
            case .closeSubpath: append(start)
            @unknown default: break
            }
        }
        segments = edges
    }

    func depths(width: Int, height: Int, size: CGSize) -> [Double] {
        let edges = segments.map { SIMD4<Float>(Float($0.start.x), Float($0.start.y), Float($0.delta.x), Float($0.delta.y)) }
        if let values = ProcessingBoundaryDepth.render(edges: edges, bounds: bounds, width: width, height: height, size: size) {
            return values.map(Double.init)
        }
        return (0..<(width * height)).map { index in
            signedDepth(CGPoint(x: (Double(index % width) + 0.5) / Double(width) * size.width,
                y: (Double(index / width) + 0.5) / Double(height) * size.height))
        }
    }

    func signedDepth(_ point: CGPoint) -> Double {
        let inside = path.contains(point)
        let rectangleDepth = min(point.x - bounds.minX, bounds.maxX - point.x,
            point.y - bounds.minY, bounds.maxY - point.y)
        var nearest = inside ? rectangleDepth * rectangleDepth : Double.infinity
        for edge in segments {
            let dx = max(0, edge.bounds.minX - point.x, point.x - edge.bounds.maxX)
            let dy = max(0, edge.bounds.minY - point.y, point.y - edge.bounds.maxY)
            if dx * dx + dy * dy >= nearest { continue }
            let x = point.x - edge.start.x, y = point.y - edge.start.y
            let t = min(1, max(0, (x * edge.delta.x + y * edge.delta.y) / edge.lengthSquared))
            let px = x - t * edge.delta.x, py = y - t * edge.delta.y
            nearest = min(nearest, px * px + py * py)
        }
        return sqrt(nearest) * (inside ? 1 : -1)
    }
}
