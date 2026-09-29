import AppKit
import SwiftUI
import S2TCore

enum ContourMaskProbe {
    static func verify() throws {
        for size in [CGSize(width: 157, height: 111), CGSize(width: 157.25, height: 111.75), CGSize(width: 157.25, height: 511.75)] {
            let image = ContourMask.render(size: size) { context in
                for x in stride(from: 0, to: 158, by: 7) {
                    context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.2, alpha: Double(x % 5 + 1) / 5))
                    context.fill(CGRect(x: x, y: 13, width: 5, height: 82))
                }
            }!
            var exterior = Path(CGRect(origin: .zero, size: size))
            exterior.addEllipse(in: CGRect(x: 25.5, y: 35.25, width: 84.75, height: 40.5))
            let transform = CGAffineTransform(a: 0.97, b: 0.015, c: -0.013, d: 1.02, tx: 2.3, ty: -1.7)
            for constant in [0.0, 0.37, 1.0, -1] {
                let illumination: (Double) -> Double = { constant < 0 ? $0 * $0 : constant }
                let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                // Frozen original operation, including both applications of the antialiased clip.
                let reference = ContourMask.render(size: size) { context in
                    context.addPath(exterior.cgPath)
                    context.clip(using: .evenOdd)
                    context.saveGState()
                    context.concatenate(transform)
                    context.translateBy(x: 0, y: size.height)
                    context.scaleBy(x: 1, y: -1)
                    context.interpolationQuality = .high
                    context.draw(source, in: CGRect(origin: .zero, size: size))
                    context.restoreGState()
                    context.setBlendMode(.destinationIn)
                    let positions = (0...32).map { CGFloat($0) / 32 }
                    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                        colors: positions.map { CGColor(gray: 1, alpha: illumination($0)) } as CFArray,
                        locations: positions)!
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }!
                guard let actual = ContourMask.transformed(image, size: size, transform: transform,
                    exterior: exterior, illumination: illumination, bounds: 0...size.width),
                    pixels(actual) == pixels(reference) else {
                    throw ServiceError.message("Contour mask changed for coverage \(constant) at \(size)")
                }
            }
        }
        print("PASS: constant and varying mask illumination matches the original gradient byte for byte, including fractional bounds, affine sampling and antialiased input exclusion.")
    }

    private static func pixels(_ image: NSImage) -> Data {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)!.dataProvider!.data! as Data
    }
}
