import AppKit
import SwiftUI

/// Stable contour images are reused; speech only transforms their samples.
enum ContourMask {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func cached(key: String, create: () -> NSImage?) -> NSImage? {
        if let image = images.object(forKey: key as NSString) { return image }
        guard let image = create() else { return nil }
        images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * 16))
        return image
    }

    static func render(size: CGSize, scale: CGFloat = 1, draw: (CGContext) -> Void) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / size.width, y: -CGFloat(height) / size.height)
        draw(context)
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    static func stroked(path: Path, size: CGSize, extent: Double, scale: CGFloat,
                        coverage: (Double) -> Double) -> NSImage? {
        render(size: size, scale: scale) { context in
            context.setBlendMode(.copy)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for step in stride(from: Int(ceil(extent * scale)), through: 1, by: -1) {
                let distance = Double(step) / scale
                context.setStrokeColor(CGColor(gray: 1, alpha: coverage(max(0, distance - 1 / scale))))
                context.setLineWidth(distance * 2)
                context.addPath(path.cgPath)
                context.strokePath()
            }
        }
    }

    static func transformed(_ image: NSImage, size: CGSize, transform: CGAffineTransform,
                            exterior: Path, illumination: (Double) -> Double,
                            bounds: ClosedRange<CGFloat>) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let positions = (0...32).map { CGFloat($0) / 32 }
        let coverage = positions.map { illumination($0) }
        let solid = (coverage[0] == 0 || coverage[0] == 1) && coverage.allSatisfy { $0 == coverage[0] }
        let band = solid ? contentBand(cgImage, size: size)?.applying(transform).insetBy(dx: -1, dy: -1).integral : nil
        return render(size: size) { context in
            if let band { context.clip(to: band) }
            context.addPath(exterior.cgPath)
            context.clip(using: .evenOdd)
            context.saveGState()
            context.concatenate(transform)
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
            context.setBlendMode(.destinationIn)
            if solid {
                // Keep the second contour clip, including its antialiasing, without shading a constant gradient.
                context.setFillColor(CGColor(gray: 1, alpha: coverage[0]))
                context.fill(CGRect(origin: .zero, size: size))
            } else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                colors: coverage.map { CGColor(gray: 1, alpha: $0) } as CFArray, locations: positions) {
                context.drawLinearGradient(gradient, start: CGPoint(x: bounds.lowerBound, y: 0),
                    end: CGPoint(x: bounds.upperBound, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }

        }
    }

    private static func contentBand(_ image: CGImage, size: CGSize) -> CGRect? {
        let byteOrder = image.bitmapInfo.intersection(.byteOrderMask)
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.alphaInfo == .premultipliedLast,
              byteOrder.isEmpty || byteOrder == .byteOrder32Big,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        func isClear(_ y: Int) -> Bool {
            let row = bytes.advanced(by: y * image.bytesPerRow)
            for x in 0..<image.width where row[x * 4 + 3] != 0 { return false }
            return true
        }
        var first = 0, last = image.height
        while first < last && isClear(first) { first += 1 }
        while last > first && isClear(last - 1) { last -= 1 }
        // Retain transparent samples around the band for high-quality image interpolation.
        first = max(0, first - 4)
        last = min(image.height, last + 4)
        return CGRect(x: 0, y: Double(first) / Double(image.height) * size.height,
            width: size.width, height: Double(last - first) / Double(image.height) * size.height)
    }
}
