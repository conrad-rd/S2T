import AppKit
import ScreenCaptureKit
import S2TCore

/// Captures the target window alone, so S2T's own overlays and windows in front
/// of the field never reach the measurement. Requires existing Screen Recording access.
final class InputSurfaceCapture {
    struct Frame {
        let bitmap: InputSurfaceBitmap
        let region: CGRect
        let scale: CGFloat
    }
    private var windows = [SCWindow]()
    private var listedAt: TimeInterval = -.infinity

    static var available: Bool { CGPreflightScreenCaptureAccess() }

    func capture(pid: pid_t, window: CGRect, region: CGRect) async -> Frame? {
        guard Self.available else { return nil }
        let local = region.intersection(window).integral.offsetBy(dx: -window.minX, dy: -window.minY)
        guard local.width >= 8, local.height >= 8, let match = await sharedWindow(pid: pid, frame: window) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: match)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = local
        configuration.width = Int(local.width * scale)
        configuration.height = Int(local.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              let bitmap = Self.bitmap(image) else { return nil }
        // The capture may be delivered at a different backing scale than requested.
        return Frame(bitmap: bitmap, region: local.offsetBy(dx: window.minX, dy: window.minY),
                     scale: CGFloat(bitmap.width) / local.width)
    }

    private func sharedWindow(pid: pid_t, frame: CGRect) async -> SCWindow? {
        func find() -> SCWindow? {
            windows.first { window in
                window.owningApplication?.processID == pid && window.windowLayer == 0
                    && abs(window.frame.minX - frame.minX) <= 1 && abs(window.frame.minY - frame.minY) <= 1
                    && abs(window.frame.width - frame.width) <= 1 && abs(window.frame.height - frame.height) <= 1
            }
        }
        if let window = find() { return window }
        // Listing shareable content is comparatively slow. Refresh only for a new or moved window.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - listedAt > 0.15,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        listedAt = now
        windows = content.windows
        return find()
    }

    private static func bitmap(_ image: CGImage) -> InputSurfaceBitmap? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? InputSurfaceBitmap(width: width, height: height, pixels: pixels) : nil
    }
}
