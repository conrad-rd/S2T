import AppKit
import CoreImage
import S2TCore

enum ChromaFilterProbe {
    static func verify() throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        for size in [CGSize(width: 61.25, height: 47.75), CGSize(width: 320, height: 240)] {
            let image = ContourMask.render(size: size) { drawing in
                for y in stride(from: 0, to: Int(size.height), by: 9) {
                    drawing.setFillColor(CGColor(red: Double(y % 7) / 7, green: 0.3,
                        blue: 0.8, alpha: Double(y % 5 + 1) / 5))
                    drawing.fill(CGRect(x: 3, y: y, width: Int(size.width) - 11, height: 6))
                }
            }!
            for expansion in [0.7, 1.0, 1.2] {
                let expanded = ChromaExpansion.image(image, geometry: .bottom, size: size, factor: expansion)!
                let source = expanded.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                for radius in [0.5, 4.0, 12.0] {
                    let input = CIImage(cgImage: source)
                    let reference = input.clampedToExtent()
                        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * Double(source.width) / size.width])
                        .cropped(to: input.extent)
                    let expected = context.createCGImage(reference, from: input.extent)!
                    guard let actual = ChromaAppearance.blurRepeatingEdges(expanded, radius: radius)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil),
                        actual.dataProvider!.data! as Data == expected.dataProvider!.data! as Data else {
                        throw ServiceError.message("Direct-texture blur differs at \(size), expansion \(expansion), radius \(radius)")
                    }
                }
            }
        }
        print("PASS: direct-texture blur matches the original uploaded-image filter byte for byte across fractional bounds, expansion, translucency and three blur radii.")
    }
}
