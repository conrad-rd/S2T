import AppKit

let width = 660, height = 750
let original = NSImage(contentsOfFile: "Resources/Appearance/DMG Installer Empty.png")!
let cleanup = NSImage(contentsOfFile: "Resources/Installer/caption-cleanup.png")!
let bitmaps = [1, 2].map { scale -> NSBitmapImageRep in
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    original.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    // Use only the caption repair from the edited image; preserve the supplied artwork elsewhere.
    let repair = NSRect(x: 300, y: 226, width: 47, height: 14)
    let source = NSRect(x: repair.minX / 660 * cleanup.size.width,
        y: repair.minY / 750 * cleanup.size.height,
        width: repair.width / 660 * cleanup.size.width, height: repair.height / 750 * cleanup.size.height)
    cleanup.draw(in: repair, from: source, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
try NSBitmapImageRep.representationOfImageReps(in: bitmaps, using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
