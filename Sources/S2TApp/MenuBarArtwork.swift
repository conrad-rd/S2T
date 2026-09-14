import AppKit
import SwiftUI

@MainActor enum MenuBarArtwork {
    // Proportions and continuous-corner radius measured from the supplied reference.
    static let scale = 28.0 / 625.0
    static let size = NSSize(width: 24, height: 370 * scale)

    static func image() -> NSImage? {
        guard let logo = NSImage(named: "MenuBar") ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "S2T") else { return nil }
        let logoHeight = 203 * scale
        let logoWidth = logoHeight * logo.size.width / max(logo.size.height, 1)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shape = RoundedRectangle(cornerRadius: 101 * scale, style: .continuous)
            context.setFillColor(NSColor.black.withAlphaComponent(25.0 / 245.0).cgColor)
            context.addPath(shape.path(in: bounds).cgPath)
            context.fillPath()
            logo.draw(in: NSRect(x: bounds.midX - logoWidth / 2, y: bounds.minY + 84 * scale, width: logoWidth, height: logoHeight))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "S2T"
        return image
    }
}
