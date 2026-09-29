import AppKit
import SwiftUI
import S2TCore

@MainActor enum NotchFitProbe {
    static func run() throws {
        try verifyPreviewArtwork()
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
            for height in [0.025, 0.053612385321100915, 0.1] {
                guard let images = ChromaAppearance.expandedImages(assets: assets, geometry: .notch(layout),
                    size: layout.frame.size, expansion: 1, edgeHeight: height),
                      let edge = images[1].representations.first as? NSBitmapImageRep else {
                    throw failure("Missing thin-edge fixture.")
                }
                for side in [-1.0, 1.0] {
                    let boundary = side < 0 ? housing.minX : housing.maxX
                    for offset in stride(from: 3.25, through: 12.25, by: 0.5) {
                        for y in [6.25, 6.75, 7.25] {
                            let x = Int((boundary + side * offset) * 2)
                            let alpha = edge.colorAt(x: x, y: Int(y * 2))?.alphaComponent ?? 1
                            guard alpha <= 1 / 255.0 else {
                                throw failure("Thin notch edge protrudes beside its upper join at height \(height): \(alpha).")
                            }
                        }
                    }
                }
            }
            if width == 220 {
                var profile = GlowProfile(energy: 0.4, heights: [3], topLayout: layout)
                profile.response.tuning = GlowTuning(softness: 10, edgeBrightness: 2,
                    edgeGlow: 0.5, edgeHeight: 0.053612385321100915, bodyOpacity: 0.61496559633027525)
                let request = ChromaFrameRequest(geometry: .notch(layout), size: layout.frame.size,
                    profile: profile, brightness: 1, backdrop: false)
                guard let frame = ChromaFrame.render(request) else { throw failure("Missing rendered notch fixture.") }
                try GlowFixture.write(ChromaFrameCanvas(frame: frame, cycleTime: 0),
                    size: layout.frame.size, name: "notch-thin-corners")
            }
            guard housing.width == width, housing.height == 38,
                  layout.cornerRadius == 8, layout.topJoinRadius == 6 else {
                throw failure("The established physical-notch geometry changed.")
            }
        }
        print("PASS: thin notch edges at 2.5%, 5.36% and 10% have no horizontal upper-corner tabs on either side.")
        print("PASS: notch color begins at the established lower/side boundaries, including fractional geometry; no detached color rim.")
    }

    static func verifyPreviewArtwork() throws {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Appearance/Figma-Notch-Housing.png")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Appearance/Figma-Notch-Housing.png")
        guard let bitmap = [bundled, source].compactMap({ $0 }).compactMap({ try? Data(contentsOf: $0) }).compactMap({ NSBitmapImageRep(data: $0) }).first,
              let notch = AppearancePreviewScene.notch.notch else { throw failure("Missing authored notch silhouette.") }
        let image = AppearanceDesignArtwork.notchImageFrame
        let scale = image.width / CGFloat(bitmap.pixelsWide)
        let origin = AppearancePreviewScene.renderOrigin(for: .aroundNotch)
        let placed = notch.offsetBy(dx: origin.x, dy: origin.y)
        for row in [30, 36, 40] {
            let opaque = (0..<bitmap.pixelsWide).filter { bitmap.colorAt(x: $0, y: row)!.alphaComponent >= 0.5 }
            guard let left = opaque.first, let right = opaque.last else { throw failure("Missing straight housing sides in source artwork.") }
            let expectedLeft = image.minX + CGFloat(left) * scale
            let expectedRight = image.minX + CGFloat(right + 1) * scale
            guard abs(placed.minX - expectedLeft) <= scale, abs(placed.maxX - expectedRight) <= scale else {
                throw failure("Preview glow uses image padding instead of the black notch: glow \(placed), source sides \(expectedLeft)...\(expectedRight).")
            }
        }
        let centerColumn = Int((placed.midX - image.minX) / scale)
        guard let bottom = (0..<bitmap.pixelsHigh).last(where: { bitmap.colorAt(x: centerColumn, y: $0)!.alphaComponent >= 0.5 }),
              abs(placed.maxY - (image.minY + CGFloat(bottom + 1) * scale)) <= scale,
              abs(placed.minY - AppearanceDesignArtwork.notchTop) < 0.001 else {
            throw failure("Preview glow misses the housing bottom or the display's top edge.")
        }
        guard AppearancePreviewScene.geometry(.aroundNotch) == .notch(AppearancePreviewScene.notch),
              AppearancePreviewScene.renderSize(for: .aroundNotch).width == AppearancePreviewScene.notch.frame.width else {
            throw failure("The mounted renderer does not use the artwork-aligned notch geometry.")
        }
        print("PASS: preview glow follows both visible source-artwork sides and the bottom within one source pixel, excluding transparent image padding.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NotchFitProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
