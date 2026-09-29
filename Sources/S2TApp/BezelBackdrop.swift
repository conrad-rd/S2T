import AppKit

struct BezelBackdrop: Equatable {
    static let extent: CGFloat = 120
    static let radius: CGFloat = 1.5
    static let opacity: Float = 1
    let path: CGPath

    func mask(size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let width = Int(ceil(size.width)), height = Int(ceil(size.height))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / size.width, y: -CGFloat(height) / size.height)
        context.setBlendMode(.copy)
        context.setLineJoin(.round)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(path)
        context.fillPath()
        guard let pixels = bitmap.bitmapData else { return nil }
        let limit = Double(Self.extent * Self.extent + 1)
        var field = [Double](repeating: limit, count: width * height)
        for index in field.indices where pixels[index * 4 + 3] >= 128 { field[index] = 0 }
        let count = max(width, height)
        var input = [Double](repeating: 0, count: count)
        var output = input
        var sites = [Int](repeating: 0, count: count)
        var breaks = [Double](repeating: 0, count: count + 1)
        func transform(_ length: Int) {
            var last = 0
            sites[0] = 0
            breaks[0] = -.infinity
            breaks[1] = .infinity
            for q in 1..<length {
                var crossing: Double
                repeat {
                    let v = sites[last]
                    crossing = ((input[q] + Double(q * q)) - (input[v] + Double(v * v))) / Double(2 * (q - v))
                    if crossing > breaks[last] { break }
                    last -= 1
                } while last >= 0
                last += 1
                sites[last] = q
                breaks[last] = crossing
                breaks[last + 1] = .infinity
            }
            last = 0
            for q in 0..<length {
                while breaks[last + 1] < Double(q) { last += 1 }
                let delta = q - sites[last]
                output[q] = Double(delta * delta) + input[sites[last]]
            }
        }
        for y in 0..<height {
            for x in 0..<width { input[x] = field[y * width + x] }
            transform(width)
            for x in 0..<width { field[y * width + x] = output[x] }
        }
        for x in 0..<width {
            for y in 0..<height { input[y] = field[y * width + x] }
            transform(height)
            for y in 0..<height {
                let t = max(0, 1 - sqrt(output[y]) / Self.extent)
                let falloff = t * t * t * (t * (t * 6 - 15) + 10)
                pixels[(y * width + x) * 4 + 3] = UInt8((falloff * 255).rounded())
            }
        }
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}
