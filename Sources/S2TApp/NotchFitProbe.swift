import AppKit
import SwiftUI
import S2TCore

@MainActor enum NotchFitProbe {
    static func run() throws {
        for width in [220.0, 220.5] {
            let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 38,
                topLeft: CGRect(x: 0, y: 1131, width: (1800 - width) / 2, height: 38),
                topRight: CGRect(x: (1800 + width) / 2, y: 1131, width: (1800 - width) / 2, height: 38))
            let layout = TopGlowLayout(display: display)
            guard let housing = layout.notch,
                  let assets = ChromaAppearance.assets(geometry: .notch(layout), size: layout.frame.size),
                  let bitmap = assets.color.representations.first as? NSBitmapImageRep else {
                throw failure("Missing notch color fixture.")
            }
            func alpha(_ point: CGPoint) -> Double {
                let x = point.x / bitmap.size.width * Double(bitmap.pixelsWide) - 0.5
                let y = point.y / bitmap.size.height * Double(bitmap.pixelsHigh) - 0.5
                let ix = Int(floor(x)), iy = Int(floor(y)), dx = x - floor(x), dy = y - floor(y)
                func value(_ column: Int, _ row: Int) -> Double {
                    Double(bitmap.colorAt(x: max(0, min(bitmap.pixelsWide - 1, column)),
                                          y: max(0, min(bitmap.pixelsHigh - 1, row)))?.alphaComponent ?? 0)
                }
                return (value(ix, iy) * (1 - dx) + value(ix + 1, iy) * dx) * (1 - dy)
                    + (value(ix, iy + 1) * (1 - dx) + value(ix + 1, iy + 1) * dx) * dy
            }
            let boundaries: [(CGPoint, CGPoint)] = [
                (CGPoint(x: housing.midX, y: housing.maxY), CGPoint(x: 0, y: 1)),
                (CGPoint(x: housing.minX, y: 16), CGPoint(x: -1, y: 0)),
                (CGPoint(x: housing.maxX, y: 16), CGPoint(x: 1, y: 0))
            ]
            for (edge, direction) in boundaries {
                let values = [0.25, 0.75, 1.5, 2.5, 4.0].map { offset in
                    alpha(CGPoint(x: edge.x + direction.x * offset, y: edge.y + direction.y * offset))
                }
                guard values[0] >= (values.max() ?? 0) - 1 / 255.0 else {
                    throw failure("Notch color pulls away from its existing boundary at width \(width): \(values).")
                }
            }
            guard housing.width == width, housing.height == 38,
                  layout.cornerRadius == 8, layout.topJoinRadius == 6 else {
                throw failure("The established physical-notch geometry changed.")
            }
        }
        print("PASS: notch color begins at the established lower/side boundaries, including fractional geometry; no detached color rim.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NotchFitProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
