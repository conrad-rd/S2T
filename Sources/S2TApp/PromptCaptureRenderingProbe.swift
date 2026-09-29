import AppKit
import S2TCore

@MainActor enum PromptCaptureRenderingProbe {
    static func run() throws {
        let border = PromptCaptureBorder()
        border.prepare(for: NSScreen.main)
        defer { border.hide() }
        guard let panel = border.panels.first else { throw failure("No generated border panel") }
        _ = panel.windowNumber
        panel.displayIfNeeded(); CATransaction.flush()
        guard panel.backgroundColor?.alphaComponent == 0,
              panel.value(forKey: "hostsLayersInWindowServer") as? Bool == true,
              panel.value(forKey: "shouldAutoFlattenLayerTree") as? Bool == false,
              panel.contentView?.value(forKey: "_shouldAutoFlattenLayerTree") as? Bool == false else {
            throw failure("Capture layers were flattened instead of hosted in WindowServer")
        }
        let originalFrame = panel.frame
        for size in [CGSize(width: 2, height: 2), CGSize(width: 6, height: 100), CGSize(width: 100, height: 6),
                     CGSize(width: 50, height: 50), CGSize(width: 900, height: 600)] {
            for scale in [1.0, 2.0] {
                let rect = CGRect(x: originalFrame.minX + 100.25, y: originalFrame.minY + 100.5, width: size.width, height: size.height)
                border.show(rect, present: false)
                try checkRendering(of: panel, border: border, rect: rect, scale: scale, size: size)
                guard panel.frame == originalFrame, !panel.isVisible else { throw failure("Selection moved or showed its hidden window") }
            }
        }
        // A drag reported on another thread must draw exactly what the main thread would.
        let anchor = CGPoint(x: originalFrame.minX + 300, y: originalFrame.minY + 200)
        border.begin(at: anchor, present: false)
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? originalFrame.maxY
        let end = CGPoint(x: anchor.x - 180, y: anchor.y + 120)
        DispatchQueue.global(qos: .userInteractive).sync {
            border.move(toQuartz: CGPoint(x: anchor.x + 2, y: primaryHeight - anchor.y - 2))
            border.move(toQuartz: CGPoint(x: end.x, y: primaryHeight - end.y))
        }
        let dragged = CGRect(x: end.x, y: anchor.y, width: 180, height: 120)
        guard let tracked = border.rect, abs(tracked.minX - dragged.minX) < 0.01, abs(tracked.minY - dragged.minY) < 0.01,
              abs(tracked.width - 180) < 0.01, abs(tracked.height - 120) < 0.01 else {
            throw failure("Background drag drew \(String(describing: border.rect)), expected \(dragged)")
        }
        try checkRendering(of: panel, border: border, rect: dragged, scale: 2, size: dragged.size)
        // Every screen gets its own overlay window, and a drag cannot leave the screen it started on.
        for screen in NSScreen.screens {
            border.show(CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 120, height: 80), present: false)
            guard panel.frame == screen.frame else { throw failure("Selection overlay spans \(panel.frame), expected screen \(screen.frame)") }
            let start = CGPoint(x: screen.frame.maxX - 40, y: screen.frame.midY)
            border.begin(at: start, present: false)
            DispatchQueue.global().sync {
                border.move(toQuartz: CGPoint(x: screen.frame.maxX + 400, y: primaryHeight - screen.frame.midY + 90))
            }
            guard let clamped = border.rect, clamped.maxX <= screen.frame.maxX + 0.01, clamped.minX >= screen.frame.minX - 0.01,
                  panel.frame == screen.frame else { throw failure("A drag left the screen it started on: \(String(describing: border.rect))") }
        }
        border.prepare(for: NSScreen.main)
        border.show(CGRect(x: anchor.x, y: anchor.y, width: 40, height: 40), present: false)
        DispatchQueue.global().sync { border.move(toQuartz: .zero) }
        guard border.rect?.width == 40 else { throw failure("A late drag position overrode a finished selection") }
        border.flash()
        guard border.rect != nil, panel.contentView?.layer?.sublayers?.first?.opacity == 0 else {
            throw failure("The capture fade must end at zero opacity so the outline cannot reappear")
        }
        print("Capture rendering: direct WindowServer hosting, no automatic flattening, stationary hidden window, clear captured area with ring and dimmed surround at 1x/2x including tiny/fractional rectangles, one overlay per screen with drags kept on their screen, background-thread drag updates and a fade that ends hidden PASS. Generated pixels only.")
    }

    /// Renders the hidden overlay around `rect` and checks the captured area is untouched while
    /// the ring and dimmed surround are visible.
    private static func checkRendering(of panel: NSPanel, border: PromptCaptureBorder, rect: CGRect, scale: CGFloat, size: CGSize) throws {
        let outer = rect.insetBy(dx: -14, dy: -14).integral
        let width = Int(outer.width * scale), height = Int(outer.height * scale)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: panel.frame.minX - outer.minX, y: panel.frame.minY - outer.minY)
        panel.contentView!.layer!.render(in: context)
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> (r: Int, a: Int) {
            let offset = (height - 1 - y) * width * 4 + x * 4
            return (Int(bytes[offset]), Int(bytes[offset + 3]))
        }
        func at(_ point: CGPoint) -> (r: Int, a: Int) {
            pixel(Int((point.x - outer.minX) * scale), Int((point.y - outer.minY) * scale))
        }
        var drawnInside = 0
        for y in 0..<height {
            for x in 0..<width {
                let cell = CGRect(x: outer.minX + CGFloat(x) / scale, y: outer.minY + CGFloat(y) / scale, width: 1 / scale, height: 1 / scale)
                if rect.contains(cell), pixel(x, y).a != 0 { drawnInside += 1 }
            }
        }
        let ring = at(CGPoint(x: rect.minX - 3.25, y: rect.midY))
        let dim = at(CGPoint(x: rect.minX - 11, y: rect.midY))
        guard drawnInside == 0, ring.a > 110, ring.r > 100,
              abs(dim.a - Int(PromptCaptureBorder.dimOpacity * 255)) <= 3, dim.r == 0 else {
            throw failure("Selection \(size) at \(scale)x: \(drawnInside) drawn pixels inside the capture, ring \(ring), dim \(dim)")
        }
    }

    /// Drag latency while the main thread is busy drawing, as during a recording with the glow.
    static func benchmarkUnderLoad() async {
        let border = PromptCaptureBorder(); border.prepare()
        defer { border.hide() }
        guard let origin = border.panels.first?.frame.origin else { return }
        border.begin(at: CGPoint(x: origin.x + 40, y: origin.y + 40), present: false)
        let primary = NSScreen.screens.first?.frame.maxY ?? 0
        let samples = LatencySamples()
        // 12 ms of main-thread work every 16 ms, like a heavy animation frame.
        let load = Task { @MainActor in
            for _ in 0..<110 {
                let end = CACurrentMediaTime() + 0.012
                while CACurrentMediaTime() < end {}
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
        }
        await Task.detached(priority: .userInitiated) {
            for index in 0..<100 {
                let point = CGPoint(x: origin.x + 60 + CGFloat(index), y: primary - origin.y - 60 - CGFloat(index))
                let posted = CACurrentMediaTime()
                DispatchQueue.main.async { samples.add(main: CACurrentMediaTime() - posted) }
                let start = CACurrentMediaTime()
                border.move(toQuartz: point)
                samples.add(direct: CACurrentMediaTime() - start)
                try? await Task.sleep(nanoseconds: 8_333_333)
            }
        }.value
        await load.value
        try? await Task.sleep(nanoseconds: 50_000_000)
        let (main, direct) = samples.sorted
        guard !main.isEmpty, !direct.isEmpty else { return }
        print(String(format: "⌘-drag at 120 Hz with a busy main thread: former main-thread outline median %.1f ms, p95 %.1f ms behind the pointer; event-tap outline median %.2f ms, p95 %.2f ms. Hidden window, not displayed FPS.",
            main[main.count / 2] * 1000, main[main.count * 95 / 100] * 1000, direct[direct.count / 2] * 1000, direct[direct.count * 95 / 100] * 1000))
    }

    static func benchmark() {
        let border = PromptCaptureBorder(); border.prepare()
        defer { border.hide() }
        var times: [Double] = []
        for index in 0..<240 {
            let start = CACurrentMediaTime()
            border.show(CGRect(x: 100, y: 100, width: 100 + index * 3, height: 100 + index * 2), present: false)
            border.panels.forEach { $0.displayIfNeeded() }
            CATransaction.flush()
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        times.sort()
        print(String(format: "240 generated drag updates + native commits: median %.3f ms, p95 %.3f ms, max %.3f ms. Plain layer frames only, no path rasterization. Hidden windows, not displayed FPS.",
            times[120], times[228], times.max()!))
        if let panel = border.panels.first {
            let area = panel.frame.width * panel.frame.height * pow(panel.backingScaleFactor, 2)
            print(String(format: "Selector window %.0f pixels; backing alpha %.3f. Native geometry only, not GPU timings.",
                area, panel.backgroundColor?.alphaComponent ?? 0))
        }
    }

    private static func failure(_ text: String) -> Error { ServiceError.message(text) }
}

private final class LatencySamples: @unchecked Sendable {
    private let lock = NSLock()
    private var main: [Double] = [], direct: [Double] = []
    func add(main value: Double) { lock.lock(); main.append(value); lock.unlock() }
    func add(direct value: Double) { lock.lock(); direct.append(value); lock.unlock() }
    var sorted: ([Double], [Double]) { lock.lock(); defer { lock.unlock() }; return (main.sorted(), direct.sorted()) }
}
