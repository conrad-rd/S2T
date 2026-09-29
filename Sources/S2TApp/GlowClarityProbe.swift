import AppKit
import SwiftUI
import S2TCore

@MainActor enum GlowClarityProbe {
    static func run() throws {
        try verifyTransparentResampling()
        try verifyThinEdges()
    }

    private static func verifyTransparentResampling() throws {
        // A red field remains red through a transparency fade. Filtering alpha must not add black.
        for straightAlpha in [true, false] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: straightAlpha ? .alphaNonpremultiplied : [], bytesPerRow: 64, bitsPerPixel: 32),
                let bytes = bitmap.bitmapData else { throw failure("No generated alpha fixture") }
            for y in 0..<16 { for x in 0..<16 {
                let i = (y * 16 + x) * 4
                let alpha: UInt8 = y < 8 ? 128 : 0
                bytes[i] = alpha == 0 ? 0 : straightAlpha ? 255 : alpha
                bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = alpha
            } }
            bitmap.size = CGSize(width: 16, height: 16)
            let source = NSImage(size: bitmap.size); source.addRepresentation(bitmap)
            guard let resized = ChromaExpansion.image(source, geometry: .bottom, size: bitmap.size, factor: 1.3),
                  let generated = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("No resampled alpha fixture") }
            let output = NSBitmapImageRep(cgImage: generated)
            var samples = 0
            for y in 0..<16 {
                guard let color = output.colorAt(x: 8, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.02 && color.alphaComponent < 0.45 {
                    samples += 1
                    guard color.redComponent > 0.98 else { throw failure("Resampling darkened a translucent red edge: red=\(color.redComponent), alpha=\(color.alphaComponent)") }
                }
            }
            guard samples > 0 else { throw failure("Fixture missed the translucent boundary") }
        }
        print("PASS: straight and premultiplied alpha both retain their color through resized translucent edges.")
    }

    private static func verifyThinEdges() throws {
        let screen = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 900, height: 700), safeTop: 32,
            topLeft: CGRect(x: 0, y: 668, width: 370, height: 32), topRight: CGRect(x: 530, y: 668, width: 370, height: 32))
        let notch = TopGlowLayout(display: screen)
        let fixtures: [(String, ChromaAppearance.Geometry, CGSize)] = [
            ("bottom", .bottom, CGSize(width: 900, height: 400)),
            ("notch", .notch(notch), notch.frame.size),
            ("input", .input(CGRect(x: 120, y: 160, width: 600, height: 58), 29, .circular), CGSize(width: 840, height: 390))
        ]
        let before = GlowTuning(backgroundBlur: 0.145, softness: 8.8555, falloff: 1.9144, edgeBrightness: 2,
            edgeBlur: 2.0057, edgeGlow: 2, edgeHeight: 0.0536, edgeOpacity: 1, bodyOpacity: 0.615, gradientSpeed: 0.1988)
        var after = before
        after.edgeBlur = 0; after.edgeGlow = 0.5; after.softness = 10
        for (name, geometry, size) in fixtures {
            guard let assets = ChromaAppearance.assets(geometry: geometry, size: size),
                  let edge = assets.edge.representations.first as? NSBitmapImageRep,
                  CGFloat(edge.pixelsWide) / size.width >= 2 else { throw failure("\(name) rim is below Retina resolution") }
            var originalRadius: Data?
            for (label, tuning) in [("before", before), ("after", after)] {
                var profile = GlowProfile(energy: 0.55, heights: [], sweepStrength: 0.568)
                profile.response = .init(minimum: 0.2586, maximum: 2.2187, tuning: tuning)
                switch geometry {
                case .bottom: break
        case let .windowBottom(layout): profile.windowBottom = layout
                case let .notch(layout): profile.topLayout = layout
                case let .withinInput(contour): profile.inputOutline = .init(contour: contour, strength: 0.568, withinInput: true)
                case let .input(contour): profile.inputOutline = .init(contour: contour, strength: 0.568)
                }
                guard let frame = ChromaFrame.render(.init(geometry: geometry, size: size, profile: profile,
                    brightness: profile.speechGain, backdrop: true)) else { throw failure("Missing \(name) clarity fixture") }
                guard let radius = frame.radiusMap?.tiffRepresentation else { throw failure("Missing \(name) native blur map") }
                if let originalRadius {
                    guard radius == originalRadius else { throw failure("Color adjustment changed \(name) background blur") }
                } else { originalRadius = radius }
                try GlowFixture.write(ChromaFrameCanvas(frame: frame), size: size, name: "clarity-\(name)-\(label)")
            }
        }
        print("PASS: Bottom, Notch and Input preserve at least two samples per point for thin rims and render the shared clarity adjustment.")
    }

    private static func failure(_ message: String) -> NSError { NSError(domain: "GlowClarityProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
