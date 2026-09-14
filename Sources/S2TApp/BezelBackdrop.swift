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
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / size.width, y: -CGFloat(height) / size.height)
        context.setBlendMode(.copy)
        context.setLineJoin(.round)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(path)
        context.fillPath()
        context.addRect(CGRect(origin: .zero, size: size))
        context.addPath(path)
        context.clip(using: .evenOdd)
        for step in stride(from: Int(Self.extent), through: 1, by: -1) {
            let distance = CGFloat(step)
            let t = max(0, 1 - distance / Self.extent)
            let falloff = t * t * t * (t * (t * 6 - 15) + 10)
            context.setStrokeColor(NSColor.black.withAlphaComponent(falloff).cgColor)
            context.setLineWidth(distance * 2)
            context.addPath(path)
            context.strokePath()
        }
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }
}
