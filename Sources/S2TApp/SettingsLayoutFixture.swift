import AppKit

@MainActor enum SettingsLayoutFixture {
    static func write(_ window: NSWindow, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"],
              !window.isVisible, let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name + ".png"))
    }
}
