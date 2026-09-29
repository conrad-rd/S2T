import AppKit
import CoreImage

/// Diffuse the generated floating-point light before the contour lens refracts it.
enum ProcessingDiffusion {
    struct Grid {
        let size: CGSize
        let width: Int
        let height: Int
        let radius: Double
        let paddingX: Int
        let paddingY: Int

        init(size: CGSize) {
            self.size = size
            width = max(2, min(480, Int(ceil(size.width))))
            height = max(2, min(300, Int(ceil(size.height))))
            radius = max(1.5, min(5, min(size.width, size.height) * 0.025))
            paddingX = Int(ceil(radius * 3 * Double(width) / size.width))
            paddingY = Int(ceil(radius * 3 * Double(height) / size.height))
        }

        var paddedWidth: Int { width + paddingX * 2 }
        var paddedHeight: Int { height + paddingY * 2 }
        func x(_ index: Int) -> Double { (Double(index - paddingX) + 0.5) / Double(width) }
        func y(_ index: Int) -> Double { (Double(index - paddingY) + 0.5) / Double(height) }
    }

    private static let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private static let context = CIContext(options: [
        .cacheIntermediates: false, .workingColorSpace: space, .workingFormat: CIFormat.RGBAf.rawValue
    ])

    static func apply(_ pixels: [Float], grid: Grid) -> [Float] {
        let data = pixels.withUnsafeBytes { Data($0) }
        let input = CIImage(bitmapData: data, bytesPerRow: grid.paddedWidth * 16,
            size: CGSize(width: grid.paddedWidth, height: grid.paddedHeight), format: .RGBAf, colorSpace: space)
        let points = CGAffineTransform(scaleX: grid.size.width / Double(grid.width),
                                      y: grid.size.height / Double(grid.height))
        let blurred = input.transformed(by: points)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: grid.radius])
            .transformed(by: points.inverted())
        var output = [Float](repeating: 0, count: grid.width * grid.height * 4)
        output.withUnsafeMutableBytes { bytes in
            context.render(blurred, toBitmap: bytes.baseAddress!, rowBytes: grid.width * 16,
                bounds: CGRect(x: grid.paddingX, y: grid.paddingY, width: grid.width, height: grid.height),
                format: .RGBAf, colorSpace: space)
        }
        return output
    }

    static func soften(_ pixels: [Float], width: Int, height: Int, size: CGSize, radius: Double) -> [Float] {
        let data = pixels.withUnsafeBytes { Data($0) }
        let input = CIImage(bitmapData: data, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
        let points = CGAffineTransform(scaleX: size.width / Double(width), y: size.height / Double(height))
        let blurred = input.clampedToExtent().transformed(by: points)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .transformed(by: points.inverted())
        var output = pixels
        output.withUnsafeMutableBytes { bytes in
            context.render(blurred, toBitmap: bytes.baseAddress!, rowBytes: width * 16,
                bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: space)
        }
        return output
    }
}
