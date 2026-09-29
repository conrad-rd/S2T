import AppKit
import SwiftUI
import S2TCore
import os
import Metal

@MainActor enum InputResizePerformanceProbe {
    static func target(_ sample: Int, horizontal: Bool = false) -> InputOutlineTarget {
        let growth = CGFloat(sample % 12) * 4
        let width: CGFloat = 736 + (horizontal ? CGFloat(sample % 10) * 2 : 0)
        var contour = InputContour(rect: CGRect(x: 0, y: 38, width: width, height: 98 + growth), radius: 16, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 13, y: 0, width: width - 26, height: 42), radius: 16, style: .circular, corners: .top)]
        return InputOutlineTarget(frame: CGRect(x: 300 + CGFloat(sample), y: 300, width: width, height: 136 + growth), contour: contour)
    }

    static func run() async throws {
        setbuf(stdout, nil)
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
            reason: "Measure active input rendering in invisible fixture windows")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try await verifyGeometryOrdering()
        try verifyTextureConversion()
        let processing = InputProcessingController()
        let state = AppState(preview: true)
        state.glowAppearance = .aroundInput
        state.phase = .processing
        let outside = InputOutlineWindowController(state: state)
        var color = [Double](), maps = [Double](), placement = [Double](), outsidePlacement = [Double]()
        for sample in 0..<24 {
            let target = target(sample)
            let time = Double(sample) / 30
            let started = CACurrentMediaTime()
            guard WithinInputProcessing.loadingImage(size: target.contour.bounds.size, time: time,
                gradient: .init(), contour: target.contour) != nil else { throw failure("Missing processing color") }
            let colored = CACurrentMediaTime()
            guard WithinInputProcessing.radiusMap(size: target.frame.size, time: time, contour: target.contour) != nil else {
                throw failure("Missing processing map")
            }
            let mapped = CACurrentMediaTime()
            guard let panel = processing.prepare(target: target), !panel.isVisible else { throw failure("Processing panel became visible") }
            let placed = CACurrentMediaTime()
            let outsidePanel = outside.prepare(target: target)
            guard !outsidePanel.isVisible else { throw failure("Outside panel became visible") }
            let finished = CACurrentMediaTime()
            color.append((colored - started) * 1000)
            maps.append((mapped - colored) * 1000)
            placement.append((placed - mapped) * 1000)
            outsidePlacement.append((finished - placed) * 1000)
            await Task.yield()
        }
        for (name, values) in [("Processing color", color), ("Processing native map", maps),
                               ("Within processing placement", placement), ("Outside processing placement", outsidePlacement)] {
            print(String(format: "%@: mean %.2f ms, max %.2f ms across %d changing full-size inputs", name,
                values.reduce(0, +) / Double(values.count), values.max()!, values.count))
        }
        processing.hide(); outside.hide()
        try await Task.sleep(for: .milliseconds(150))
        let hiddenFrames = processing.completedFrames
        try await Task.sleep(for: .milliseconds(150))
        guard processing.completedFrames == hiddenFrames else {
            throw failure("Hidden processing continued submitting animation frames")
        }
        print("PASS: the hidden processing view performs no animation work after preparation settles.")
        for appearance in [GlowAppearance.aroundInput, .withinInput] {
            var times = [Double]()
            for sample in 0..<12 {
                let target = target(sample)
                let layout = InputOutlineGeometry(field: target.frame)
                let contour = target.contour.offsetBy(dx: layout.outlineRect.minX, dy: layout.outlineRect.minY)
                var profile = GlowProfile(energy: 0.3, heights: [], sweepStrength: 0.568)
                profile.inputOutline = .init(contour: contour, withinInput: appearance == .withinInput)
                let request = ChromaFrameRequest(geometry: profile.chromaGeometry, size: layout.windowFrame.size,
                    profile: profile, brightness: profile.speechGain, backdrop: true)
                let start = CACurrentMediaTime()
                guard ChromaFrame.render(request) != nil else { throw failure("Missing resized listening frame") }
                times.append((CACurrentMediaTime() - start) * 1000)
            }
            print(String(format: "%@ listening resize: cold %.2f ms, warm mean %.2f ms, warm max %.2f ms",
                appearance.rawValue, times[0], times.dropFirst().reduce(0, +) / Double(times.count - 1), times.dropFirst().max()!))
        }
        try verifyWithinAssets()
        try await verifyProcessingResize()
    }

    private static func verifyGeometryOrdering() async throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let old = target(0).contour, current = target(1, horizontal: true).contour
        let renderer = ChromaFrameRenderer { request in
            if request.geometry == .withinInput(old) { entered.signal(); release.wait() }
            return ChromaFrame(request: request, images: [], radiusMap: nil)
        }
        defer { release.signal(); renderer.cancel() }
        let first = ChromaFrameRequest(geometry: .withinInput(old), size: old.bounds.size,
            profile: .init(energy: 1, heights: []), brightness: 1, backdrop: false)
        let next = ChromaFrameRequest(geometry: .withinInput(current), size: current.bounds.size,
            profile: .init(energy: 1, heights: []), brightness: 1, backdrop: false)
        var published = [ChromaFrameRequest]()
        let observation = renderer.$frame.sink { if let frame = $0 { published.append(frame.request) } }
        defer { observation.cancel() }
        renderer.prepareGeometry(first.geometry, size: first.size)
        renderer.submit(first)
        let deadline = CACurrentMediaTime() + 2
        while entered.wait(timeout: .now()) != .success {
            guard CACurrentMediaTime() < deadline else { throw failure("Staged render never started") }
            try await Task.sleep(for: .milliseconds(1))
        }
        renderer.prepareGeometry(next.geometry, size: next.size)
        renderer.submit(next)
        renderer.submit(first)
        release.signal()
        while renderer.frame?.request != next, CACurrentMediaTime() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard published == [next] else { throw failure("An obsolete SwiftUI size replaced newer controller geometry") }
        print("PASS: a late old-size view update cannot replace or publish over the latest controller geometry.")
    }

    private static func verifyWithinAssets() throws {
        for style in [InputCornerStyle.circular, .continuous] {
            for height in [CGFloat(48), 140.25] {
                let contour = InputContour(rect: CGRect(x: 45.25, y: 160.5, width: 340.5, height: height), radius: 24, style: style)
                let size = CGSize(width: 432.5, height: 380.25)
                for falloff in [0.5, 1, 1.9144] {
                    guard let actual = ChromaExpansion.withinAssets(contour: contour, size: size, falloff: falloff, edgeExpansion: 1),
                          let expected = ChromaAppearance.assets(geometry: .withinInput(contour), size: size, falloff: falloff, useCache: false) else {
                        throw failure("Missing generated Within Input comparison")
                    }
                    for (a, b) in [(actual.color, expected.color), (actual.edge, expected.edge), (actual.radius, expected.radius)] {
                        guard let left = a.cgImage(forProposedRect: nil, context: nil, hints: nil),
                              let right = b.cgImage(forProposedRect: nil, context: nil, hints: nil),
                              left.width == right.width, left.height == right.height else { throw failure("Field resolution changed") }
                        let lhs = NSBitmapImageRep(cgImage: left), rhs = NSBitmapImageRep(cgImage: right)
                        var error = 0.0
                        for y in stride(from: 0, to: left.height, by: 3) { for x in stride(from: 0, to: left.width, by: 3) {
                            let p = lhs.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                            let q = rhs.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                            error = max(error, abs(p.alphaComponent - q.alphaComponent),
                                abs(p.redComponent * p.alphaComponent - q.redComponent * q.alphaComponent),
                                abs(p.greenComponent * p.alphaComponent - q.greenComponent * q.alphaComponent),
                                abs(p.blueComponent * p.alphaComponent - q.blueComponent * q.alphaComponent))
                        } }
                        guard error <= 0.009 else { throw failure("Within Input changed its color/map by \(error) at \(style), height \(height), falloff \(falloff)") }
                    }
                }
            }
        }
        print("PASS: accelerated color, full-resolution rim and native maps match the independent CPU formulas within 0.009 premultiplied coverage, including fractional bounds, capsules, both corner styles and falloff settings.")
    }

    private static func verifyTextureConversion() throws {
        let width = 620, height = 380
        for attempt in 0..<12 {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: [.alphaNonpremultiplied], bytesPerRow: width * 4, bitsPerPixel: 32),
                  let bytes = bitmap.bitmapData else { throw failure("Missing generated conversion fixture") }
            for index in 0..<(width * height * 4) { bytes[index] = UInt8((index + attempt) % 251) }
            let image = NSImage(size: CGSize(width: width, height: height))
            image.addRepresentation(bitmap)
            guard let texture = ChromaExpansion.prepareSource(image) else { throw failure("Texture upload failed") }
            var converted = [UInt16](repeating: 0, count: width * height * 4)
            converted.withUnsafeMutableBytes { values in
                texture.getBytes(values.baseAddress!, bytesPerRow: width * 8,
                    from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            for index in converted.indices {
                let alpha = Float(bytes[index / 4 * 4 + 3]) / 255
                let value = Float(bytes[index]) / 255 * (index % 4 == 3 ? 1 : alpha)
                let exponent = value == 0 ? -14 : max(-14, Int(floor(log2(Double(value)))))
                let significand = Int((Double(value) / pow(2, Double(exponent - 10))).rounded(.toNearestOrEven))
                let expected = UInt16((exponent + 14) * 1024 + significand)
                guard converted[index] == expected else { throw failure("Texture conversion overwrote unread source pixels") }
            }
        }
        print("PASS: twelve full-size texture uploads exactly match independent Float16 premultiplication without overlapping conversion buffers.")
    }

    private static func verifyProcessingResize() async throws {
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let renderTimes = OSAllocatedUnfairLock(initialState: [Double]())
        let controller = InputProcessingController(renderer: ChromaFrameRenderer { request in
            let start = CACurrentMediaTime()
            let result = ChromaFrame.render(request)
            renderTimes.withLock { $0.append((CACurrentMediaTime() - start) * 1000) }
            return result
        })
        guard let panel = controller.prepare(target: target(0)) else { throw failure("Missing hidden processing panel") }
        let root = panel.contentView
        let initial = CACurrentMediaTime()
        while controller.preparedFrame == nil, CACurrentMediaTime() - initial < 3 { try await Task.sleep(for: .milliseconds(5)) }
        guard controller.preparedFrame != nil else { throw failure("Processing preparation never completed") }
        guard let host = root?.subviews.first as? NSHostingView<InputProcessingGlow> else {
            throw failure("Missing actual processing animation view")
        }
        host.rootView.animationClock.running = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(150))
        var gaps = [Double](), actions = [Double](), lastTick = CACurrentMediaTime()
        let heartbeat = Timer(timeInterval: 0.005, repeats: true) { _ in
            let now = CACurrentMediaTime(); gaps.append((now - lastTick) * 1000); lastTick = now
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        defer {
            heartbeat.invalidate(); host.rootView.animationClock.running = false
            controller.hide(); panel.orderOut(nil)
        }
        var matched = 0
        let start = CACurrentMediaTime()
        for sample in 0..<120 {
            let value = target(sample, horizontal: true)
            let before = CACurrentMediaTime()
            _ = controller.prepare(target: value)
            actions.append((CACurrentMediaTime() - before) * 1000)
            guard panel.contentView === root, panel.alphaValue == 0, !panel.canBecomeKey, panel.ignoresMouseEvents,
                  panel.frame == value.frame.insetBy(dx: -WithinInputProcessing.haloPadding, dy: -WithinInputProcessing.haloPadding) else {
                throw failure("Resizing replaced the host, showed a panel or retained old geometry")
            }
            let remaining = start + Double(sample + 1) / 60 - CACurrentMediaTime()
            if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            if controller.preparedFrame?.request.profile.processingInput?.contour == value.contour.offsetBy(dx: 24, dy: 24) { matched += 1 }
        }
        let maxGap = gaps.max() ?? .infinity
        let times = renderTimes.withLock { $0 }
        print(String(format: "Background processing work: %d renders, mean %.2f ms, max %.2f ms",
            times.count, times.reduce(0, +) / Double(times.count), times.max() ?? 0))
        print(String(format: "Processing at 60 resize requests/s: %d/120 matching frames before next resize, %d total publications, max main action %.2f ms, max 5-ms heartbeat gap %.2f ms", matched, controller.completedFrames, actions.max()!, maxGap))
        guard matched >= 90, actions.max()! < 16.7, maxGap < 40 else {
            throw failure("Processing resize missed its frame/UI responsiveness budget")
        }
        try await Task.sleep(for: .milliseconds(100))
        guard let backdrop = root as? ProgressiveBackdropView,
              backdrop.profile?.processingInput?.contour == target(119, horizontal: true).contour.offsetBy(dx: 24, dy: 24),
              backdrop.isBackdropAttached, BackdropWindowHosting.isEnabled(in: panel),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground else {
            throw failure("Mounted processing lost its matching native map, hosting or foreground focus")
        }
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "InputResizePerformance", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
