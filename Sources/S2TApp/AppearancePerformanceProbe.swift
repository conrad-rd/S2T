import AppKit
import SwiftUI
import S2TCore

@MainActor enum AppearancePerformanceProbe {
    static func run() throws {
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 32,
            topLeft: CGRect(x: 0, y: 1137, width: 780, height: 32),
            topRight: CGRect(x: 1020, y: 1137, width: 780, height: 32))
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            var times: [Double] = []
            for maximum in [2.0, 2.15, 2.3, 2.45, 2.6] {
                try autoreleasepool {
                    let response = GlowResponseSettings(maximum: maximum)
                    let geometry: ChromaAppearance.Geometry
                    let size: CGSize
                    switch mode {
                    case .aroundNotch:
                        let layout = TopGlowLayout(display: display, paddingScale: response.paddingScale)
                        geometry = .notch(layout); size = layout.frame.size
                    case .aroundInput:
                        let layout = InputOutlineGeometry(field: CGRect(x: 700, y: 500, width: 400, height: 64),
                            paddingScale: response.paddingScale, displayFrame: display.frame)
                        geometry = .input(layout.outlineRect, 24); size = layout.windowFrame.size
                    default:
                        geometry = .bottom
                        size = CGSize(width: display.frame.width, height: min(display.frame.height, GlowProfile.extent * response.paddingScale))
                    }
                    let started = CACurrentMediaTime()
                    guard let assets = ChromaAppearance.assets(geometry: geometry, size: size),
                          ChromaExpansion.images([assets.color, assets.edge], geometry: geometry,
                            size: size, factor: maximum * 0.55) != nil else { throw failure() }
                    var exterior = Path(CGRect(origin: .zero, size: size))
                    if case let .input(rect, radius, cornerStyle) = geometry { exterior.addPath(InputOutlineBackdrop(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle).path) }
                    guard ChromaAppearance.radiusMap(geometry: geometry, size: size, distortion: .identity,
                        exterior: exterior, expansion: maximum * 0.55) != nil else { throw failure() }
                    times.append((CACurrentMediaTime() - started) * 1000)
                }
            }
            print("\(mode.rawValue) changing maximum, generated fields on calling thread, ms: " + times.map { String(format: "%.2f", $0) }.joined(separator: ", "))
        }
    }
    static func verify() async throws {
        let state = AppState(preview: true)
        let saved = (state.glowAppearance, state.glowMaximum, state.glowMinimum, state.glowStrength, state.glowWidth)
        defer {
            state.glowAppearance = saved.0; state.glowMaximum = saved.1; state.glowMinimum = saved.2
            state.glowStrength = saved.3; state.glowWidth = saved.4
        }
        state.glowMinimum = 0
        state.glowStrength = 1.3
        state.glowWidth = 1
        let menu = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        menu.menuNeedsUpdate(menu.menu)
        let appearance = menu.appearanceWindow
        appearance.prepare()
        appearance.selectSection(.speech)
        appearance.reveal(.maximum)
        defer { appearance.window?.close() }
        let slider = appearance.sliders[.maximum]!
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 32,
            topLeft: CGRect(x: 0, y: 1137, width: 780, height: 32),
            topRight: CGRect(x: 1020, y: 1137, width: 780, height: 32))
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            state.glowAppearance = mode
            let renderer = ChromaFrameRenderer()
            var latest: ChromaFrameRequest!
            var actionTimes: [Double] = []
            var ticks: [Double] = []
            var previous = CACurrentMediaTime()
            let timer = Timer(timeInterval: 0.005, repeats: true) { _ in
                let now = CACurrentMediaTime()
                ticks.append((now - previous) * 1000)
                previous = now
            }
            RunLoop.main.add(timer, forMode: .common)
            defer { timer.invalidate(); renderer.cancel() }
            let started = CACurrentMediaTime()
            for maximum in [2.0, 2.15, 2.3, 2.45, 2.6] {
                let before = CACurrentMediaTime()
                slider.doubleValue = maximum
                slider.sendAction(slider.action, to: slider.target)
                let response = state.glowResponseSettings
                let geometry: ChromaAppearance.Geometry
                let size: CGSize
                var profile = GlowProfile(energy: 0.55, heights: [3], sweepStrength: 1.3)
                profile.response = response
                switch mode {
                case .aroundNotch:
                    let layout = TopGlowLayout(display: display, paddingScale: response.paddingScale)
                    geometry = .notch(layout); size = layout.frame.size; profile.topLayout = layout
                case .aroundInput:
                    let layout = InputOutlineGeometry(field: CGRect(x: 700, y: 500, width: 400, height: 64),
                        paddingScale: response.paddingScale, displayFrame: display.frame)
                    geometry = .input(layout.outlineRect, 24); size = layout.windowFrame.size
                    profile.inputOutline = InputOutlineBackdrop(rect: layout.outlineRect, cornerRadius: 24, strength: 1.3)
                default:
                    geometry = .bottom
                    size = CGSize(width: display.frame.width, height: min(display.frame.height, GlowProfile.extent * response.paddingScale))
                }
                latest = ChromaFrameRequest(geometry: geometry, size: size, profile: profile,
                    brightness: profile.speechGain, backdrop: true)
                renderer.submit(latest)
                actionTimes.append((CACurrentMediaTime() - before) * 1000)
                try await Task.sleep(nanoseconds: 8_000_000)
            }
            let deadline = CACurrentMediaTime() + 10
            while renderer.frame?.request != latest && CACurrentMediaTime() < deadline {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            timer.invalidate()
            guard let final = renderer.frame, final.request == latest,
                  final.radiusMap?.size == latest.size,
                  state.glowMaximum == 2.6, AppState(preview: true).glowMaximum == 2.6 else { throw failure() }
            guard actionTimes.max()! < 16.7, ticks.max()! < 50 else {
                throw NSError(domain: "AppearancePerformance", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Main thread blocked: actions \(actionTimes), timer \(ticks.max()!) ms"])
            }
            print(String(format: "%@ 5 native slider changes: max main-thread action %.3f ms, max 5 ms timer interval %.2f ms, latest field ready %.0f ms, published frames %d",
                mode.rawValue, actionTimes.max()!, ticks.max()!, (CACurrentMediaTime() - started) * 1000, renderer.completedFrames))
            // Compare generated output with the unchanged synchronous field formulas.
            let reference = GlowBackdrop.mask(profile: latest.profile, size: latest.size)!
            guard bytes(reference) == bytes(final.radiusMap!) else { throw failure() }
            let root = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: latest.size))
            root.preparesFramesAsynchronously = true
            root.apply(profile: final.request.profile, radiusMap: final.radiusMap)
            guard let filter = root.layer?.sublayers?.first?.filters?.first as? NSObject,
                  let radius = filter.value(forKey: "inputRadius") as? Double,
                  abs(radius - latest.geometry.maximumBlurRadius * latest.profile.blurGain) < 0.00001 else { throw failure() }
            let comparison = ChromaFrameRequest(geometry: latest.geometry,
                size: CGSize(width: floor(latest.size.width), height: floor(latest.size.height)),
                profile: latest.profile, brightness: latest.brightness, backdrop: false)
            renderer.submit(comparison)
            let colorDeadline = CACurrentMediaTime() + 10
            while renderer.frame?.request != comparison && CACurrentMediaTime() < colorDeadline {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let colorFrame = renderer.frame, colorFrame.request == comparison else { throw failure() }
            let original: AnyView
            switch latest.geometry {
            case .bottom:
                original = AnyView(BottomGlow(level: 0.55, strength: 1.3, phase: .recording, timeOverride: 1,
                    renderedProfile: latest.profile, response: latest.profile.response))
            case let .notch(layout):
                original = AnyView(TopGlow(renderedProfile: latest.profile, showsBackdrop: false,
                    layout: layout, strength: 1.3, phase: .recording, levelProvider: { 0.55 },
                    timeOverride: 1, response: latest.profile.response))
            case let .input(rect, radius, cornerStyle):
                let layout = InputOutlineLayout()
                layout.outlineRect = rect; layout.cornerRadius = radius; layout.cornerStyle = cornerStyle
                state.phase = .recording
                original = AnyView(InputOutline(renderedProfile: latest.profile, showsBackdrop: false,
                    state: state, layout: layout, timeOverride: 1))
            }
            func render<V: View>(_ view: V) throws -> Data {
                let image = ImageRenderer(content: view.frame(width: comparison.size.width, height: comparison.size.height))
                image.scale = 1
                guard let result = image.cgImage, let data = result.dataProvider?.data else { throw failure() }
                return data as Data
            }
            let originalPixels = try render(original), preparedPixels = try render(ChromaFrameCanvas(frame: colorFrame))
            let differences = zip(originalPixels, preparedPixels).map { abs(Int($0) - Int($1)) }
            guard originalPixels.count == preparedPixels.count, differences.max() == 0 else {
                throw NSError(domain: "AppearancePerformance", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Prepared color differs from the original Canvas for \(mode.rawValue): bytes \(originalPixels.count)/\(preparedPixels.count), max \(differences.max() ?? -1), changed \(differences.filter { $0 > 0 }.count)"])
            }
            state.phase = .idle
            renderer.cancel()
            renderer.submit(latest)
            renderer.cancel()
            try await Task.sleep(nanoseconds: 100_000_000)
            guard renderer.frame == nil else { throw failure() }
            renderer.submit(latest)
            let restartDeadline = CACurrentMediaTime() + 10
            while renderer.frame == nil && CACurrentMediaTime() < restartDeadline { try await Task.sleep(nanoseconds: 5_000_000) }
            guard renderer.frame?.request == latest else { throw failure() }
            var silent = latest.profile
            silent.response = .init(minimum: 0, maximum: 0)
            let empty = ChromaFrameRequest(geometry: latest.geometry, size: latest.size, profile: silent, brightness: 0, backdrop: true)
            renderer.submit(empty)
            let silenceDeadline = CACurrentMediaTime() + 5
            while renderer.frame?.request != empty && CACurrentMediaTime() < silenceDeadline { try await Task.sleep(nanoseconds: 5_000_000) }
            guard renderer.frame?.request == empty else { throw failure() }
        }
        print("PASS: newest values persist, generated maps match, native filters receive matching frames, cancellation/restart and zero amount. No screen or microphone capture.")
    }
    private static func bytes(_ image: NSImage) -> Data {
        let bitmap = image.representations.first as! NSBitmapImageRep
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    private static func failure() -> NSError { NSError(domain: "AppearancePerformance", code: 1) }
}
