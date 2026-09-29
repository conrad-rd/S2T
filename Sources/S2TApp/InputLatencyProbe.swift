import AppKit
import SwiftUI
import S2TCore
import Metal

@MainActor enum InputLatencyProbe {
    static func run() async throws {
        try measureExtendedPreparation()
        let size = CGSize(width: 840, height: 320)
        let rect = CGRect(x: 100, y: 100, width: 640, height: 90)
        for (name, radius, style) in [("rounded web", CGFloat(20), InputCornerStyle.circular),
                                       ("rounded native", 24, .continuous), ("capsule", 45, .circular)] {
            var profile = GlowProfile(energy: 0.3, heights: [], sweepStrength: 0.568)
            profile.inputOutline = .init(rect: rect, cornerRadius: radius, cornerStyle: style, strength: 0.568)
            profile.response = .init(minimum: 0.259, maximum: 2.219)
            let request = ChromaFrameRequest(geometry: .input(rect, radius, style), size: size,
                profile: profile, brightness: profile.speechGain, backdrop: true)
            let started = CACurrentMediaTime()
            let renderer = ImageRenderer(content: PreparedChromaGlow(request: request).frame(width: size.width, height: size.height))
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw failure("Missing initial \(name) frame") }
            let elapsed = (CACurrentMediaTime() - started) * 1000
            let bitmap = NSBitmapImageRep(cgImage: image)
            func alpha(_ point: CGPoint) -> CGFloat {
                bitmap.colorAt(x: Int(point.x * 2), y: Int(point.y * 2))?.alphaComponent ?? -1
            }
            let visible = [CGPoint(x: rect.midX, y: rect.minY - 0.5), CGPoint(x: rect.maxX, y: rect.midY),
                           CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX - 0.5, y: rect.midY)]
            guard visible.allSatisfy({ alpha($0) == 0 }) else { throw failure("\(name) flashes a temporary stroke before its completed glow") }
            guard alpha(CGPoint(x: rect.midX, y: rect.midY)) == 0,
                  alpha(CGPoint(x: rect.midX, y: rect.minY + 2)) == 0 else { throw failure("Initial edge enters the input") }
            guard elapsed < 100 else { throw failure("\(name) initial edge took \(elapsed) ms") }
            let preparationStarted = CACurrentMediaTime()
            guard ChromaFrame.render(request) != nil else { throw failure("Missing completed \(name) glow") }
            let preparation = (CACurrentMediaTime() - preparationStarted) * 1000
            print(String(format: "PASS: %@ waits for complete color/map: empty initial frame %.2f ms; full glow preparation %.2f ms.", name, elapsed, preparation))
        }
        guard !InputOutline.showsProcessing(.preparing), !InputOutline.showsProcessing(.recording),
              InputOutline.showsProcessing(.transcribing), InputOutline.showsProcessing(.processing) else {
            throw failure("Microphone preparation switches to a different stroke renderer")
        }
        try await measureSustainedFrames(name: "default", tuning: .init())
        try await measureSustainedFrames(name: "thin edge", tuning: .init(backgroundBlur: 0.145, softness: 10,
            falloff: 1.9144, edgeBrightness: 2, edgeBlur: 0, edgeGlow: 0.5, edgeHeight: 0.0536,
            edgeOpacity: 1, bodyOpacity: 0.615, gradientSpeed: 0.1988))
        try await measureResizingFrames()
        try verifyResizedFields()
        try await verifyMountedCodex()
        try await verifyVisibility()
    }

    private static func verifyMountedCodex() async throws {
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let state = AppState(preview: true)
        let saved = (state.glowMinimum, state.glowMaximum, state.glowWidth, state.glowStrength, state.glowTuning)
        defer {
            state.glowMinimum = saved.0; state.glowMaximum = saved.1; state.glowWidth = saved.2
            state.glowStrength = saved.3; state.glowTuning = saved.4
        }
        state.glowMinimum = 0.259; state.glowMaximum = 2.219; state.glowWidth = 1
        state.glowStrength = 0.568; state.glowTuning = .init()
        state.phase = .preparing
        var contour = InputContour(rect: CGRect(x: 0, y: 38, width: 736, height: 98), radius: 16, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 13, y: 0, width: 710, height: 42), radius: 16, style: .circular, corners: .top)]
        let target = InputOutlineTarget(frame: CGRect(x: 500, y: 400, width: 736, height: 136), contour: contour)
        let controller = InputOutlineWindowController(state: state)
        let panel = controller.prepare(target: target)
        guard let root = panel.contentView as? ProgressiveBackdropView,
              let host = root.subviews.first as? NSHostingView<InputOutline>,
              let sampler = root.layer?.sublayers?.first else { throw failure("Missing mounted Codex renderer") }
        var level = 0.0
        host.rootView.levelProvider = { level }
        host.rootView.reduceTransparencyOverride = false
        host.rootView.animationClock.running = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        defer { host.rootView.animationClock.running = false; panel.orderOut(nil) }
        for phase in [DictationPhase.preparing, .recording, .processing, .recording] {
            state.phase = phase
            level = phase == .recording ? 0.3 : 0
            let deadline = CACurrentMediaTime() + 3
            func ready() -> Bool {
                guard let profile = root.profile, profile.active == !InputOutline.showsProcessing(phase),
                      profile.inputOutline?.contour.bars.count == 1,
                      (sampler.filters?.first as? NSObject)?.value(forKey: "inputMaskImage") != nil else { return false }
                return phase != .recording || profile.energy > 0.15
            }
            while !ready(), CACurrentMediaTime() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
            guard ready(), panel.contentView === root, root.subviews.first === host,
                  root.isBackdropAttached, BackdropWindowHosting.isEnabled(in: panel),
                  panel.alphaValue == 0, !panel.canBecomeKey, panel.ignoresMouseEvents else {
                throw failure("Mounted Codex failed to publish or retain its compound glow during \(phase)")
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Mounted Codex changed focus") }
        print("PASS: full-size hidden Codex mounts its completed native map, retains its header and hosts through preparing, recording, processing and recording again; no capture or focus change.")
    }

    private static func measureSustainedFrames(name: String, tuning: GlowTuning) async throws {
        let layout = InputOutlineGeometry(field: CGRect(x: 0, y: 0, width: 736, height: 136))
        let padding = layout.outlineRect.origin
        var contour = InputContour(rect: CGRect(x: padding.x, y: padding.y + 38, width: 736, height: 98), radius: 16, style: .circular)
        contour.bars = [.init(rect: CGRect(x: padding.x + 13, y: padding.y, width: 710, height: 38), radius: 16, style: .circular, corners: .top)]
        let size = layout.windowFrame.size
        print("Production overlay canvas: \(size), padding \(InputOutlineGeometry.padding)")
        let renderer = ChromaFrameRenderer()
        var completions = [Double]()
        let observation = renderer.$frame.sink { frame in
            if frame != nil { completions.append(CACurrentMediaTime()) }
        }
        defer { observation.cancel(); renderer.cancel() }
        let start = CACurrentMediaTime()
        var submitted = 0
        while CACurrentMediaTime() - start < 4 {
            let time = CACurrentMediaTime() - start
            var profile = GlowProfile(energy: 0.3 + 0.2 * sin(time * 4), heights: [], sweepStrength: 0.568)
            profile.inputOutline = .init(contour: contour)
            profile.response = .init(minimum: 0.259, maximum: 2.219, tuning: tuning)
            renderer.submit(.init(geometry: .input(contour), size: size, profile: profile,
                brightness: profile.speechGain, backdrop: true))
            submitted += 1
            let remaining = start + Double(submitted) / 60 - CACurrentMediaTime()
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
        let gaps = zip(completions, completions.dropFirst()).map { $1 - $0 }
        guard completions.count >= 120, (gaps.max() ?? 1) < 0.1 else {
            throw failure("Sustained rendering stalled: \(completions.count) completions, longest gap \((gaps.max() ?? 1) * 1000) ms")
        }
        print(String(format: "Sustained Codex \(name): %d submitted, %d completed in %.2f s, %.2f completed FPS, max gap %.2f ms",
            submitted, completions.count, CACurrentMediaTime() - start,
            Double(completions.count) / (CACurrentMediaTime() - start), (gaps.max() ?? 0) * 1000))
    }

    private static func measureResizingFrames() async throws {
        let renderer = ChromaFrameRenderer()
        var completions = [Double]()
        let observation = renderer.$frame.sink { frame in
            if frame != nil { completions.append(CACurrentMediaTime()) }
        }
        defer { observation.cancel(); renderer.cancel() }
        var started = CACurrentMediaTime()
        var latest: ChromaFrameRequest?
        for sample in 0..<120 {
            let step = sample % 60
            let growth = CGFloat(min(step, 60 - step) * 3)
            let field = CGRect(x: 0, y: 0, width: 736, height: 136 + growth)
            let layout = InputOutlineGeometry(field: field)
            let padding = layout.outlineRect.origin
            var contour = InputContour(rect: CGRect(x: padding.x, y: padding.y + 38, width: 736, height: 98 + growth), radius: 16, style: .circular)
            contour.bars = [.init(rect: CGRect(x: padding.x + 13, y: padding.y, width: 710, height: 42), radius: 16, style: .circular, corners: .top)]
            var profile = GlowProfile(energy: 0.3, heights: [], sweepStrength: 0.568)
            profile.inputOutline = .init(contour: contour)
            profile.response = .init(minimum: 0.259, maximum: 2.219)
            let request = ChromaFrameRequest(geometry: .input(contour), size: layout.windowFrame.size,
                profile: profile, brightness: profile.speechGain, backdrop: true)
            latest = request
            renderer.submit(request)
            if sample == 0 {
                let deadline = CACurrentMediaTime() + 2
                while renderer.frame?.request != request, CACurrentMediaTime() < deadline {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                guard renderer.frame?.request == request else { throw failure("Initial resizing fixture never prepared") }
                print(String(format: "Resizing fixture cold preparation %.2f ms", (CACurrentMediaTime() - started) * 1000))
                completions.removeAll()
                started = CACurrentMediaTime()
            }
            let remaining = started + Double(sample + 1) / 30 - CACurrentMediaTime()
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
        let deadline = CACurrentMediaTime() + 1
        while renderer.frame?.request != latest, CACurrentMediaTime() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let gaps = zip([started] + completions, completions).map { $1 - $0 }
        print(String(format: "Growing full-size composer: %d complete matched color/map frames over %.2f s, max gap %.2f ms",
            completions.count, CACurrentMediaTime() - started, (gaps.max() ?? 0) * 1000))
        guard completions.count >= 80, (gaps.max() ?? 1) < 0.2, renderer.frame?.request == latest else {
            throw failure("Resizing starved the input renderer or retained an old contour")
        }
    }

    static func verifyResizedFields() throws {
        for style in [InputCornerStyle.circular, .continuous] {
            var seed = InputContour(rect: CGRect(x: 100, y: 140, width: 420, height: 100), radius: 16, style: style)
            seed.bars = [.init(rect: CGRect(x: 116, y: 112, width: 388, height: 32), radius: 14, style: .circular, corners: .top),
                         .init(rect: CGRect(x: 116, y: 236, width: 388, height: 32), radius: 14, style: .circular, corners: .bottom)]
            let size = CGSize(width: 620, height: 380)
            guard ChromaAppearance.assets(geometry: .input(seed), size: size) != nil,
                  ChromaExpansion.field(geometry: .input(seed), size: size) != nil else { throw failure("Missing resize seed") }
            for growth in [CGFloat(72), -20] {
                var contour = seed
                contour.main.rect.size.height += growth; contour.bars[1].rect.origin.y += growth
                let targetSize = CGSize(width: size.width, height: size.height + growth)
                let geometry = ChromaAppearance.Geometry.input(contour)
                guard let resized = ChromaAppearance.assets(geometry: geometry, size: targetSize),
                      let fresh = ChromaAppearance.assets(geometry: geometry, size: targetSize, useCache: false) else { throw failure("Missing resized assets") }
                for (name, actual, expected) in [("color", resized.color, fresh.color), ("edge", resized.edge, fresh.edge), ("blur", resized.radius, fresh.radius)] {
                    guard let a = actual.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let b = expected.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("Missing resize comparison image") }
                    let lhs = NSBitmapImageRep(cgImage: a), rhs = NSBitmapImageRep(cgImage: b)
                    var maximum = 0.0
                    var mismatch = ""
                    for y in stride(from: 0, to: lhs.pixelsHigh, by: 3) {
                        for x in stride(from: 0, to: lhs.pixelsWide, by: 3) {
                            let left = lhs.colorAt(x: x, y: y)!, right = rhs.colorAt(x: x, y: y)!
                            if abs(left.alphaComponent - right.alphaComponent) > maximum {
                                mismatch = "at \(x),\(y), alpha \(left.alphaComponent)/\(right.alphaComponent), growth \(growth)"
                            }
                            maximum = max(maximum, abs(left.alphaComponent - right.alphaComponent))
                            if left.alphaComponent > 0.1 && right.alphaComponent > 0.1 {
                                maximum = max(maximum, abs(left.redComponent - right.redComponent) * left.alphaComponent,
                                    abs(left.greenComponent - right.greenComponent) * left.alphaComponent,
                                    abs(left.blueComponent - right.blueComponent) * left.alphaComponent)
                            }
                        }
                    }
                    guard maximum <= 0.025 else { throw failure("Resized \(style) \(name) differs from freshly generated corners by \(maximum), \(mismatch), pixels \(a.width)x\(a.height)/\(b.width)x\(b.height)") }
                }
                guard let vectors = ChromaExpansion.field(geometry: geometry, size: targetSize) else { throw failure("Missing resized outward field") }
                var values = [SIMD2<Float>](repeating: .zero, count: vectors.width * vectors.height)
                values.withUnsafeMutableBytes { bytes in
                    vectors.getBytes(bytes.baseAddress!, bytesPerRow: vectors.width * MemoryLayout<SIMD2<Float>>.stride,
                        from: MTLRegionMake2D(0, 0, vectors.width, vectors.height), mipmapLevel: 0)
                }
                let boundary = ChromaInputBoundary(contour: contour)
                for y in stride(from: 0, to: vectors.height, by: 7) {
                    for x in stride(from: 0, to: vectors.width, by: 7) {
                        let point = CGPoint(x: (Double(x) + 0.5) / Double(vectors.width) * targetSize.width,
                            y: (Double(y) + 0.5) / Double(vectors.height) * targetSize.height)
                        let expected = boundary.outwardVector(point), actual = values[y * vectors.width + x]
                        guard hypot(Double(actual.x) - expected.x, Double(actual.y) - expected.y) < 0.15 else {
                            throw failure("Resizing moved the native field away from its true corner at \(point)")
                        }
                    }
                }
            }
        }
        print("PASS: growing/shrinking circular and continuous fields match fresh color, rim and blur assets; native expansion vectors match the exact compound boundary.")
    }

    private static func measureExtendedPreparation() throws {
        var contour = InputContour(rect: CGRect(x: 182, y: 220, width: 736, height: 98), radius: 16, style: .circular)
        contour.bars = [.init(rect: CGRect(x: 195, y: 182, width: 710, height: 38), radius: 16, style: .circular, corners: .top)]
        let size = CGSize(width: 1100, height: 500)
        var profile = GlowProfile(energy: 0.3, heights: [], sweepStrength: 0.568)
        profile.inputOutline = .init(contour: contour)
        profile.response = .init(minimum: 0.259, maximum: 2.219)
        let geometry = ChromaAppearance.Geometry.input(contour)
        let start = CACurrentMediaTime()
        guard let assets = ChromaAppearance.assets(geometry: geometry, size: size) else { throw failure("Extended assets missing") }
        let assetsDone = CACurrentMediaTime()
        guard ChromaAppearance.expandedImages(assets: assets, geometry: geometry, size: size,
            expansion: profile.speechExpansion, edgeHeight: profile.response.tuning.edgeHeight,
            softness: profile.response.tuning.softness) != nil else { throw failure("Extended color missing") }
        let colorDone = CACurrentMediaTime()
        guard GlowBackdrop.mask(profile: profile, size: size) != nil else { throw failure("Extended native map missing") }
        let mapDone = CACurrentMediaTime()
        print(String(format: "Extended startup: assets %.2f ms, color %.2f ms, map %.2f ms, total %.2f ms",
            (assetsDone-start)*1000, (colorDone-assetsDone)*1000, (mapDone-colorDone)*1000, (mapDone-start)*1000))
    }

    private final class HiddenPanel: NSPanel {
        var presentations = 0
        override func orderFrontRegardless() { presentations += 1 }
    }

    private static func verifyVisibility() async throws {
        let panel = HiddenPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let visibility = OverlayVisibility(panel: panel, appearanceDuration: 0)
        let started = CACurrentMediaTime()
        visibility.setVisible(true)
        guard panel.alphaValue == 1, !panel.isVisible, panel.presentations == 1 else {
            throw failure("Initial input presentation waited for a fade")
        }
        let elapsed = (CACurrentMediaTime() - started) * 1000
        visibility.setVisible(false)
        visibility.setVisible(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard panel.alphaValue == 1, !panel.isVisible, panel.presentations == 2 else {
            throw failure("A stale fade-out erased the restarted input")
        }
        visibility.setVisible(false)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard panel.alphaValue == 0, !panel.isVisible else { throw failure("Input cancellation did not finish hiding") }
        print(String(format: "PASS: immediate input opacity %.2f ms; hide/restart/hide retains the newest state, without presenting a window.", elapsed))
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "InputLatency", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
