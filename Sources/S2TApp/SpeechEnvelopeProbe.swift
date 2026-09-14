import AppKit
import SwiftUI
import S2TCore

@MainActor enum SpeechEnvelopeProbe {
    static func run() throws {
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 38,
            topLeft: CGRect(x: 0, y: 1131, width: 790, height: 38),
            topRight: CGRect(x: 1010, y: 1131, width: 790, height: 38))
        let notch = TopGlowLayout(display: display)
        let rect = CGRect(x: 480, y: 480, width: 400, height: 64)
        let fixtures: [(ChromaAppearance.Geometry, CGSize, CGPoint, CGPoint)] = [
            (.bottom, CGSize(width: 800, height: GlowProfile.extent), CGPoint(x: 400, y: GlowProfile.extent), CGPoint(x: 0, y: -1)),
            (.notch(notch), notch.frame.size, CGPoint(x: notch.notch!.midX, y: 38), CGPoint(x: 0, y: 1)),
            (.input(rect, 32), CGSize(width: 1360, height: 1024), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: 0, y: -1))
        ]
        for (geometry, size, edge, direction) in fixtures {
            try autoreleasepool {
            guard let assets = ChromaAppearance.assets(geometry: geometry, size: size) else { throw failure("Missing assets") }
            var depths: [Double] = []
            var luminosity: [Double] = []
            for energy in [0.0, 0.5, 1.0] {
                let gain = GlowSpeechEnvelope.gain(energy: energy, selected: 1.3)
                guard let image = ChromaExpansion.image(assets.color, geometry: geometry, size: size, factor: gain),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("Expansion kernel failed") }
                let bitmap = NSBitmapImageRep(cgImage: cg)
                func alpha(_ distance: Double) -> Double {
                    let point = CGPoint(x: edge.x + direction.x * distance, y: edge.y + direction.y * distance)
                    let x = min(bitmap.pixelsWide - 1, max(0, Int(point.x / size.width * Double(bitmap.pixelsWide))))
                    let y = min(bitmap.pixelsHigh - 1, max(0, Int(point.y / size.height * Double(bitmap.pixelsHigh))))
                    return Double(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                }
                let peak = alpha(1)

                guard peak > 0.01 else { throw failure("Expanded field is empty or detached at \(geometry.preset.style): \(peak)") }
                let depth = (1...300).last(where: { alpha(Double($0)) > peak * 0.1 }) ?? 0
                depths.append(Double(depth))
                let renderer = ImageRenderer(content: Canvas { context, bounds in
                    ChromaAppearance.draw(context: &context, geometry: geometry, size: bounds,
                        brightness: gain, distortion: .identity, expansion: gain)
                }.frame(width: size.width, height: size.height))
                renderer.scale = 1
                guard let rendered = renderer.cgImage else { throw failure("Expanded Canvas failed") }
                let colors = NSBitmapImageRep(cgImage: rendered)
                var total = 0.0
                for y in stride(from: 0, to: colors.pixelsHigh, by: 4) {
                    for x in stride(from: 0, to: colors.pixelsWide, by: 4) {
                        if let c = colors.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                            total += c.alphaComponent * (c.redComponent + c.greenComponent + c.blueComponent)
                        }
                    }
                }
                luminosity.append(total)
            }
            guard depths[0] > 0, depths[1] > depths[0], depths[2] > depths[1],
                  luminosity[0] > 0, luminosity[1] > luminosity[0], luminosity[2] > luminosity[1] else {
                throw failure("Speech did not enlarge and brighten \(geometry.preset.style): depths \(depths), light \(luminosity)")
            }
            print("PASS: \(geometry.preset.style) silence/mid/loud generated depths \(depths), color totals \(luminosity.map { Int($0) }); fixed boundary and 30–200% response.")
            }
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SpeechEnvelopeProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
