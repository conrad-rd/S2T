import AppKit
import SwiftUI

/// Exports authored test views only; never samples a display or another app.
@MainActor enum GlowFixture {
    static func write<V: View>(_ view: V, size: CGSize, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"] else { return }
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.black))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "GlowFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated fixture failed to render."])
        }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try png.write(to: url.appendingPathComponent(name + ".png"))
    }
}
