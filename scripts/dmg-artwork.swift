import AppKit

let width = 660, height = 460
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current!.cgContext.scaleBy(x: 2, y: 2)
NSColor(calibratedRed: 0.96, green: 0.955, blue: 0.98, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
func text(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
let muted = NSColor(calibratedWhite: 0.40, alpha: 1)
text("Speak. Keep writing.", x: 44, y: 370, size: 32, weight: .semibold, color: ink)
text("Drag S2T into Applications to install.", x: 46, y: 337, size: 16, color: muted)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 293, y: 239)); arrow.line(to: NSPoint(x: 359, y: 239))
arrow.move(to: NSPoint(x: 348, y: 250)); arrow.line(to: NSPoint(x: 359, y: 239)); arrow.line(to: NSPoint(x: 348, y: 228))
arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.47, green: 0.40, blue: 0.73, alpha: 1).setStroke(); arrow.stroke()
text("Then open S2T from Applications.", x: 46, y: 131, size: 16, weight: .medium, color: ink)
text("Click its menu bar icon and choose Set up dictation.", x: 46, y: 105, size: 13, color: muted)
text("macOS 14+  ·  Apple silicon & Intel", x: 46, y: 28, size: 11, color: muted)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
