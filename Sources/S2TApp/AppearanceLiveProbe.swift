import AppKit
import S2TCore

@MainActor enum AppearanceLiveProbe {
    static func run() async throws {
        let state = AppState(preview: true)
        let controls = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controls.prepare()
        controls.show()
        defer { controls.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window)); window.close() }
        func pump(_ mode: RunLoop.Mode, until ready: () -> Bool) -> Double {
            let start = CACurrentMediaTime()
            while !ready(), CACurrentMediaTime() - start < 3 {
                RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: 0.005))
            }
            return (CACurrentMediaTime() - start) * 1000
        }
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput, .withinInput] {
            controls.selectPreview(mode)
            controls.selectSection(.glow)
            state.glowTuning.bodyOpacity = 1
            let renderer = controls.preview.renderer
            let deadline = CACurrentMediaTime() + 10
            while (renderer.frame?.request.geometry != AppearancePreviewScene.geometry(mode) || renderer.frame?.request.profile.response.tuning.bodyOpacity != 1), CACurrentMediaTime() < deadline {
                window.contentView?.layoutSubtreeIfNeeded()
                controls.previewHost?.displayIfNeeded()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard renderer.frame != nil else { throw failure("Preview did not start") }
            var expected: ChromaFrameRequest!
            func matches(_ request: ChromaFrameRequest?) -> Bool {
                request?.geometry == expected.geometry && request?.profile.response == expected.profile.response &&
                    request?.profile.sweepStrength == expected.profile.sweepStrength
            }
            func displayed(_ view: NSView) -> Bool {
                if let background = view as? AppearancePreviewBackdropView, matches(background.displayedRequest) { return true }
                return view.subviews.contains(where: displayed)
            }
            var delays: [Double] = []
            var actions: [Double] = []
            for control in AppearanceControl.allCases where control.isVisible(for: mode) {
                controls.reveal(control)
                for fraction in [0.37, 0.63] {
                    let slider = controls.sliders[control]!
                    guard slider.isContinuous else { throw failure("Slider stopped sending continuous actions") }
                    slider.doubleValue = slider.minValue + (slider.maxValue - slider.minValue) * fraction
                    let start = CACurrentMediaTime()
                    slider.sendAction(slider.action, to: slider.target)
                    actions.append((CACurrentMediaTime() - start) * 1000)
                    expected = AppearancePreviewScene.request(state: state, mode: controls.preview.mode, phase: controls.preview.phase,
                        time: Date.timeIntervalSinceReferenceDate,
                        reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                        backdrop: !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
                    let delay = pump(.eventTracking) { matches(renderer.frame?.request) && displayed(controls.previewHost!) }
                    guard matches(renderer.frame?.request), displayed(controls.previewHost!) else {
                        throw failure("\(mode.rawValue) \(control.title) stayed stale for \(Int(delay)) ms during slider tracking")
                    }
                    delays.append(delay)
                }
            }
            print(String(format: "%@ %d tracking updates: max action %.2f ms, median preview %.2f ms, max preview %.2f ms",
                mode.rawValue, delays.count, actions.max()!, delays.sorted()[delays.count / 2], delays.max()!))

        }
        print("PASS: native slider actions update preview frames during event tracking. Hidden windows, no screen capture.")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AppearanceLiveProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
