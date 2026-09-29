import AppKit
import SwiftUI
import S2TCore

@MainActor enum AppearanceStartupProbe {
    static func run() async throws {
        for size in [CGSize(width: 1684, height: 1084), CGSize(width: 1900, height: 1800)] {
            let contour = InputContour(rect: CGRect(x: 474, y: 474, width: size.width - 948, height: 136), radius: 24)
            var profile = GlowProfile(energy: 0, heights: [])
            profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: 1.3, withinInput: true)
            profile.response = .init(minimum: 0.6255787, maximum: 1.4270833,
                tuning: .init(backgroundBlur: 0.2016767, softness: 12, falloff: 2,
                    edgeBrightness: 2, edgeBlur: 0.9764, edgeGlow: 2, edgeHeight: 0.0918))
            let request = ChromaFrameRequest(geometry: .withinInput(contour), size: size,
                profile: profile, brightness: profile.speechGain, backdrop: true)
            for cycle in 0..<3 {
                let start = CACurrentMediaTime()
                let assets = ChromaAppearance.assets(geometry: request.geometry, size: size, falloff: profile.response.tuning.falloff)!
                let prepared = CACurrentMediaTime()
                let images = ChromaAppearance.expandedImages(assets: assets, geometry: request.geometry,
                    size: size, expansion: profile.speechExpansion, edgeHeight: profile.response.tuning.edgeHeight,
                    softness: profile.response.tuning.softness)!
                let expanded = CACurrentMediaTime()
                let map = GlowBackdrop.mask(profile: profile, size: size)!
                let mapped = CACurrentMediaTime()
                let frame = ChromaFrame(request: request, images: images, radiusMap: map)
                let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame).frame(width: size.width, height: size.height))
                renderer.scale = 2
                guard let image = renderer.cgImage else { throw ServiceError.message("Missing composed first frame") }
                let composed = CACurrentMediaTime()
                guard image.width == Int(size.width * 2), map.size == size else { throw ServiceError.message("First-frame dimensions changed") }
                print(String(format: "Within Input %.0fx%.0f cycle %d: assets %.2f ms, expansion %.2f ms, map %.2f ms, composition %.2f ms, complete %.2f ms", size.width, size.height, cycle,
                    (prepared-start)*1000, (expanded-prepared)*1000, (mapped-expanded)*1000,
                    (composed-mapped)*1000, (composed-start)*1000))
            }
        }
        try await verifyPreparedPresentation()
        print("Generated full glow and native map through production rendering. Excludes Accessibility lookup and actual display presentation. No screen capture.")
    }

    private static func verifyPreparedPresentation() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        state.glowAppearance = .withinInput
        state.glowMinimum = 0.6255787
        state.glowMaximum = 1.4270833
        state.glowStrength = 1.3
        let controller = InputOutlineWindowController(state: state)
        let targets = [
            InputOutlineTarget(frame: CGRect(x: 500, y: 400, width: 736, height: 136), cornerRadius: 24),
            InputOutlineTarget(frame: CGRect(x: 500, y: 400, width: 920, height: 200), cornerRadius: 16),
            InputOutlineTarget(frame: CGRect(x: 500, y: 400, width: 736, height: 136), cornerRadius: 24),
            InputOutlineTarget(frame: CGRect(x: 500, y: 400, width: 736, height: 136), cornerRadius: 44)
        ]
        for (index, target) in targets.enumerated() {
            state.phase = .idle
            controller.prepareForActivation(target: target)
            guard let panel = controller.panel else { throw ServiceError.message("Missing prepared input window") }
            let expectedSize = panel.frame.size
            let placement = InputOutlineGeometry(field: target.frame)
            let expectedGeometry = ChromaAppearance.Geometry.withinInput(target.contour.offsetBy(
                dx: placement.outlineRect.minX, dy: placement.outlineRect.minY))
            let deadline = CACurrentMediaTime() + 3
            while controller.preparedFrame?.request.size != expectedSize || controller.preparedFrame?.request.geometry != expectedGeometry || controller.preparedFrame?.radiusMap == nil {
                guard CACurrentMediaTime() < deadline else { throw ServiceError.message("Hidden input did not prepare its complete frame") }
                try await Task.sleep(for: .milliseconds(5))
            }
            guard let frame = controller.preparedFrame, frame.images.count == 2, let radiusMap = frame.radiusMap,
                  let host = (panel.contentView as? ProgressiveBackdropView)?.subviews.first as? NSHostingView<InputOutline>,
                  host.rootView.layout.renderer.frame?.images.first === frame.images.first,
                  !host.rootView.animationClock.running,
                  !panel.isVisible, !panel.canBecomeKey, panel.ignoresMouseEvents else {
                throw ServiceError.message("Prewarming opened a window or omitted color/native blur")
            }
            state.phase = .preparing
            let start = CACurrentMediaTime()
            let ready = controller.prepare(target: target)
            guard let presented = controller.preparedFrame,
                  presented.images[0] === frame.images[0], presented.radiusMap === radiusMap,
                  ready === panel, !panel.isVisible else {
                throw ServiceError.message("Activation discarded its complete prepared glow")
            }
            let elapsed = (CACurrentMediaTime() - start) * 1000
            let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: presented)
                .frame(width: expectedSize.width, height: expectedSize.height))
            renderer.scale = 1
            guard let image = renderer.cgImage, case let .withinInput(contour) = presented.request.geometry else {
                throw ServiceError.message("Missing generated activation image")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let alpha = bitmap.colorAt(x: Int(contour.main.rect.midX), y: Int(contour.main.rect.maxY - 4))?.alphaComponent ?? 0
            guard alpha > 0.01 else { throw ServiceError.message("Prepared activation frame is blank") }
            guard elapsed < 20 else { throw ServiceError.message("Prepared activation blocked for \(elapsed) ms") }
            print(String(format: "PASS: prepared native input activation %d %.2f ms, complete color/map already present, generated glow alpha %.3f, no visible window.", index, elapsed, alpha))
            state.phase = .processing
            await Task.yield()
            state.phase = .idle
        }
    }

}
