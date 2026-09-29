import AppKit
import Metal
import S2TCore

@MainActor enum WithinInputExpansionProbe {
    static func benchmark() throws {
        // The 2x vector texture is larger than the existing 96 MiB NSCache budget.
        let size = CGSize(width: 1900, height: 1800)
        let contour = InputContour(rect: CGRect(x: 350, y: 700, width: 1200, height: 260), radius: 28)
        var times: [Double] = []
        var prior: MTLTexture?
        var reused = 0
        for _ in 0..<4 {
            let start = CACurrentMediaTime()
            guard let field = ChromaExpansion.field(geometry: .withinInput(contour), size: size) else { throw failure("Missing field") }
            times.append((CACurrentMediaTime() - start) * 1000)
            if let prior, prior === field { reused += 1 }
            prior = field
        }
        print("Within Input 1900x1800 points, 2x vectors: " + times.map { String(format: "%.2f ms", $0) }.joined(separator: ", ") + "; reused \(reused)/3 textures; \(prior!.width * prior!.height * 8) bytes per texture.")
    }

    static func verify() throws {
        for style in [InputCornerStyle.continuous, .circular] {
            for size in [CGSize(width: 161.5, height: 123.25), CGSize(width: 420, height: 300)] {
                let contour = InputContour(rect: CGRect(x: 20.25, y: 30.5, width: size.width - 40, height: size.height - 65), radius: 24, style: style)
                let geometry = ChromaAppearance.Geometry.withinInput(contour)
                guard let texture = ChromaExpansion.field(geometry: geometry, size: size) else { throw failure("Missing generated field") }
                let width = texture.width, height = texture.height
                var pixels = [SIMD2<Float>](repeating: .zero, count: width * height)
                pixels.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
                let field = WithinInputField(contour: contour)
                var maximum: Float = 0
                for y in 0..<height { for x in 0..<width {
                    let point = CGPoint(x: (Double(x) + 0.5) / Double(width) * size.width,
                        y: (Double(y) + 0.5) / Double(height) * size.height)
                    // Independent reference: the original per-pixel finite differences.
                    let distance = max(0, field.distance(point))
                    let dx = field.distance(CGPoint(x: point.x + 0.1, y: point.y)) - field.distance(CGPoint(x: point.x - 0.1, y: point.y))
                    let dy = field.distance(CGPoint(x: point.x, y: point.y + 0.1)) - field.distance(CGPoint(x: point.x, y: point.y - 0.1))
                    let length = hypot(dx, dy)
                    let expected = length > 0 ? SIMD2(Float(dx * distance / length), Float(dy * distance / length)) : .zero
                    let actual = pixels[y * width + x]
                    maximum = max(maximum, abs(expected.x - actual.x), abs(expected.y - actual.y))
                } }
                guard maximum <= 0.0001 else { throw failure("Expansion changed by \(maximum) points") }
                guard let repeatField = ChromaExpansion.field(geometry: geometry, size: size), repeatField === texture else { throw failure("Stable geometry recreated the expansion field") }
            }
        }
        print("Within Input expansion matches the original per-pixel field within 0.0001 points, including fractional bounds and both corner styles. Generated data only.")
    }

    private static func failure(_ message: String) -> Error { ServiceError.message(message) }
}
