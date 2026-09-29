import AppKit
import ImageIO
import UniformTypeIdentifiers
import S2TCore

struct PromptScreenshot: Sendable {
    let png: Data
    let pointer: CGPoint
    let region: CGRect
    let thumbnail: CGImage?

    init(png: Data, pointer: CGPoint, region: CGRect, thumbnail: CGImage? = nil) {
        self.png = png; self.pointer = pointer; self.region = region; self.thumbnail = thumbnail
    }

    func relocated(to region: CGRect) -> PromptScreenshot {
        PromptScreenshot(png: png, pointer: pointer, region: region, thumbnail: thumbnail)
    }

    static func thumbnail(from png: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 420, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }

    static func thumbnail(from image: CGImage) -> CGImage? {
        let scale = min(1, 420 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    static var permissionGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Encodes a captured selection. The PNG and the deck thumbnail are prepared in parallel.
    static func encode(_ image: CGImage, region: CGRect, thumbnail known: CGImage? = nil) -> PromptScreenshot? {
        let png = ConcurrentSlots<Data>(count: 1), preview = ConcurrentSlots<CGImage>(count: 1)
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination) { png[0] = output as Data }
            } else { preview[0] = known ?? thumbnail(from: image) }
        }
        guard let data = png[0] else { return nil }
        return PromptScreenshot(png: data, pointer: CGPoint(x: CGFloat(image.width) / 2, y: CGFloat(image.height) / 2),
            region: region, thumbnail: preview[0])
    }

    static func quartzRect(fromCocoa rect: CGRect, screenFrame: CGRect, quartzBounds: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX + quartzBounds.minX,
               y: screenFrame.maxY - rect.maxY + quartzBounds.minY,
               width: rect.width, height: rect.height)
    }

    static func cocoaRect(fromQuartz rect: CGRect, screenFrame: CGRect, quartzBounds: CGRect) -> CGRect {
        CGRect(x: rect.minX - quartzBounds.minX + screenFrame.minX,
               y: screenFrame.maxY - (rect.minY - quartzBounds.minY) - rect.height,
               width: rect.width, height: rect.height)
    }

    func cropped(to selection: CGRect) throws -> PromptScreenshot {
        try Self.decode(png, pointer: pointer, region: region, selection: selection)
    }

    static func decode(_ data: Data, pointer: CGPoint, region: CGRect, selection: CGRect? = nil) throws -> PromptScreenshot {
        let area = selection.map { region.intersection($0.standardized) } ?? region
        guard !area.isNull, area.width >= 4, area.height >= 4,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ServiceError.message("Select a larger area inside one display.")
        }
        let sx = CGFloat(image.width) / region.width, sy = CGFloat(image.height) / region.height
        let pixels = CGRect(x: (area.minX - region.minX) * sx, y: (area.minY - region.minY) * sy,
                            width: area.width * sx, height: area.height * sy).integral
        guard let crop = selection == nil ? image : image.cropping(to: pixels) else {
            throw ServiceError.message("Could not crop the selected screenshot.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ServiceError.message("Could not prepare the selected screenshot.")
        }
        CGImageDestinationAddImage(destination, crop, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ServiceError.message("Could not prepare the selected screenshot.")
        }
        return PromptScreenshot(png: output as Data, pointer: selection == nil ? pointer : CGPoint(x: CGFloat(crop.width) / 2, y: CGFloat(crop.height) / 2),
            region: CGRect(x: region.minX + pixels.minX / sx, y: region.minY + pixels.minY / sy,
                           width: pixels.width / sx, height: pixels.height / sy), thumbnail: thumbnail(from: crop))
    }
}
