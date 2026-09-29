import AppKit
import SwiftUI
import S2TCore

@MainActor enum GlowConsistencyProbe {
    static func run() throws {
        let size = CGSize(width: 640, height: 400)
        let display = GlowDisplay(frame: CGRect(origin: .zero, size: size), safeTop: 32,
            topLeft: CGRect(x: 0, y: 368, width: 220, height: 32),
            topRight: CGRect(x: 420, y: 368, width: 220, height: 32))
        let layout = TopGlowLayout(display: display)
        let input = InputContour(rect: CGRect(x: 100, y: 180, width: 440, height: 160), radius: 30)
        let fixtures: [(ChromaAppearance.Geometry, CGSize, Double)] = [
            (.bottom, size, size.height),
            (.input(input), size, input.bounds.minY),
            (.withinInput(input), size, input.bounds.maxY),
            (.notch(layout), layout.frame.size, Double(layout.notch?.maxY ?? 0))
        ]
        for falloff in [0.5, 1, 2] {
            for edge in [0.1, 0.5, 1.0] {
                var reference: [Double]?
                for (geometry, canvas, boundary) in fixtures {
                    guard let assets = ChromaAppearance.assets(geometry: geometry, size: canvas,
                        falloff: falloff, edgeExpansion: edge) else { throw failure("Missing assets") }
                    var values: [Double] = []
                    for image in [assets.color, assets.edge, assets.radius] {
                        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                        for distance in [1.5, 4.5, 10.5, 24.5, 48.5, 90.5] {
                            let y = geometry.appearance == .aroundNotch ? boundary + distance : boundary - distance
                            let px = Int(canvas.width / 2 / image.size.width * Double(bitmap.pixelsWide))
                            let row = y / image.size.height * Double(bitmap.pixelsHigh) - 0.5
                            let py = Int(floor(row)), fraction = row - floor(row)
                            let a = Double(bitmap.colorAt(x: px, y: py)?.alphaComponent ?? -1)
                            let b = Double(bitmap.colorAt(x: px, y: py + 1)?.alphaComponent ?? -1)
                            values.append(a * (1 - fraction) + b * fraction)
                        }
                    }
                    if let reference {
                        let error = zip(reference, values).map { abs($0 - $1) }.max() ?? 0
                        guard error < 0.045 else { throw failure("\(geometry.appearance) field mismatch \(error), falloff \(falloff), edge \(edge)") }
                    } else { reference = values }
                    guard geometry.maximumBlurRadius == 12 else { throw failure("Different native blur strength") }
                }
            }
        }
        print("PASS: four actual appearance asset sets match body, edge and native-map coverage within 4.5 percent at six physical depths, three falloffs and three edge heights; shared 12-point native blur. No screen capture.")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "GlowConsistencyProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
