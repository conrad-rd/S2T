import AppKit

// A second process provides an ordinary window behind the overlay. No display
// pixels are read back; the pipe reports only this fixture's window metadata.
@MainActor enum BackdropFixture {
    static func run(screenIndex: Int) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard NSScreen.screens.indices.contains(screenIndex) else { exit(1) }
        let screen = NSScreen.screens[screenIndex]
        let rect = NSRect(x: screen.frame.minX, y: screen.frame.minY + 80, width: screen.frame.width, height: 240)
        let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.hasShadow = false
        window.contentView = BackdropFixtureContent(frame: NSRect(origin: .zero, size: rect.size))
        if CommandLine.arguments.contains("--hidden") { window.alphaValue = 0 }
        window.orderFrontRegardless()
        print("READY \(ProcessInfo.processInfo.processIdentifier) \(window.windowNumber)")
        fflush(stdout)
        // Exits automatically if the parent check stops unexpectedly.
        let timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in NSApp.terminate(nil) }
        withExtendedLifetime((window, timer)) { app.run() }
    }
}

private final class BackdropFixtureContent: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.12, alpha: 1).setFill()
        bounds.fill()
        NSColor(white: 0.8, alpha: 1).setFill()
        for x in stride(from: 0, to: Int(bounds.width), by: 96) {
            NSRect(x: CGFloat(x), y: 0, width: 3, height: bounds.height).fill()
        }
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.white]
        for y in stride(from: 12, to: Int(bounds.height), by: 24) {
            "Separate app window · Native blur check".draw(at: NSPoint(x: 24, y: y), withAttributes: style)
        }
    }
}
