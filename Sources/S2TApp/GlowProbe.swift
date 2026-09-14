import AppKit
import SwiftUI
import S2TCore

@MainActor enum GlowProbe {
    private static func backdrop(in view: NSView) -> ProgressiveBackdropView? {
        if let backdrop = view as? ProgressiveBackdropView { return backdrop }
        return view.subviews.lazy.compactMap { backdrop(in: $0) }.first
    }

    static func run(directory: URL) async throws {
        // The legacy directory argument is retained for CLI compatibility.
        // This check never takes screenshots or records the screen.
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try SpeechEnvelopeProbe.run()
        try ChromaProbe.run()
        try SpeechGlowProbe.run()
        try verifyColorContinuity()
        try FilterSubmissionProbe.run()
        try verifyRadiusMaps()
        try await verifyVisibility()
        for (index, screen) in NSScreen.screens.enumerated() {
            let fixture = Process()
            let pipe = Pipe()
            fixture.executableURL = Bundle.main.executableURL
            fixture.arguments = ["--backdrop-fixture", String(index), "--hidden"]
            fixture.standardOutput = pipe
            try fixture.run()
            defer { if fixture.isRunning { fixture.terminate() } }
            try await Task.sleep(nanoseconds: 400_000_000)
            guard fixture.isRunning else { throw failure("Separate fixture process did not start.") }
            let readiness = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            guard readiness.hasPrefix("READY \(fixture.processIdentifier) "), fixture.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                throw failure("Fixture did not confirm its independent window.")
            }
            let panel = BackdropWindowHosting.makePanel()
            panel.alphaValue = 0
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            defer { panel.orderOut(nil) }
            guard BackdropWindowHosting.isEnabled(in: panel), panel.contentView?.wantsLayer != true else { throw failure("Window must be configured before attaching its layer-backed content.") }
            panel.contentView = ProgressiveBackdropView.hosting(BottomGlow(level: 0.55, strength: 1, phase: .recording, timeOverride: 1.7, showsBackdrop: true))
            panel.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY + 80, width: screen.frame.width, height: 240), display: true)
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            CATransaction.flush()
            guard let initial = nativeBackdrop(in: panel.contentView?.layer),
                  initial.filters?.contains(where: { String(describing: $0) == "gaussianBlur" }) == false else {
                throw failure("First submitted frame contains an unconfigured rectangular material blur.")
            }
            panel.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let root = panel.contentView, let view = backdrop(in: root),
                  view === panel.contentView, view.isProgressiveBlurAvailable, view.isBackdropAttached,
                  BackdropWindowHosting.isEnabled(in: panel),
                  abs(view.bounds.width - screen.frame.width) < 1 else {
                throw failure("Backdrop is not the native window content view or did not attach to WindowServer.")
            }
            // Longer than the normal auto-flatten delay, without animating updates.
            try await Task.sleep(nanoseconds: 1_300_000_000)
            guard BackdropWindowHosting.isEnabled(in: panel), view.isBackdropAttached,
                  panel.ignoresMouseEvents, !panel.canBecomeKey, fixture.isRunning else {
                throw failure("Window hosting did not survive idle or the panel took focus.")
            }
            for level in [0.0, 0.3, 0.55, 1.0] {
                panel.contentView = ProgressiveBackdropView.hosting(BottomGlow(level: level, strength: 1, phase: .recording, timeOverride: 1.7, showsBackdrop: true))
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let root = panel.contentView, let current = backdrop(in: root) else {
                    throw failure("Backdrop missing at meter level \(level).")
                }
                try verifyFilter(in: current, scale: screen.backingScaleFactor, level: level)
            }
            guard let root = panel.contentView, let current = backdrop(in: root) else {
                throw failure("Backdrop missing before layer replacement check.")
            }
            panel.appearance = NSAppearance(named: .darkAqua)
            try await Task.sleep(nanoseconds: 150_000_000)
            try verifyFilter(in: current, scale: screen.backingScaleFactor, level: 1)
            panel.appearance = NSAppearance(named: .aqua)
            try await Task.sleep(nanoseconds: 150_000_000)
            try verifyFilter(in: current, scale: screen.backingScaleFactor, level: 1)
            current.layer = CALayer()
            current.needsLayout = true
            current.layoutSubtreeIfNeeded()
            try verifyFilter(in: current, scale: screen.backingScaleFactor, level: 1)
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 150_000_000)
            try verifyFilter(in: current, scale: screen.backingScaleFactor, level: 1)
            try await verifyPhasePersistence(in: panel)
            try await verifyTransparency(in: panel)
            print("Display \(index), \(screen.backingScaleFactor)x: independent fixture pid \(fixture.processIdentifier), native root Glur backdrop, early WindowServer configuration, live WindowServer host, auto-flatten disabled, full-width variable layer attached, meter 0/0.3/0.55/1, display sampling scale, light/dark appearance, idle, layer replacement and hide/show: PASS")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else {
            throw failure("Foreground application changed during check.")
        }
        print("Rendering configuration verified. No screenshots, screen recording, screen pixel readback, microphone capture, or provider calls. Visual cross-app blur is not asserted by this structural check.")
    }

    private static func nativeBackdrop(in layer: CALayer?) -> CALayer? {
        guard let layer else { return nil }
        if let type = NSClassFromString("CABackdropLayer"), layer.isKind(of: type) { return layer }
        return layer.sublayers?.lazy.compactMap { nativeBackdrop(in: $0) }.first
    }

    private static func verifyFilter(in view: ProgressiveBackdropView, scale: CGFloat, level: Double, smoothed: Bool = false) throws {
        let gain = smoothed ? view.profile?.speechGain ?? -1
            : GlowSpeechEnvelope.gain(energy: pow(max(0, (level - 0.06) / 0.94), 0.7), selected: 1)
        guard let window = view.window, BackdropWindowHosting.isEnabled(in: window),
              view === window.contentView, view.isProgressiveBlurAvailable, view.isBackdropAttached, !view.layerUsesCoreImageFilters,
              view.value(forKey: "_shouldAutoFlattenLayerTree") as? Bool == false,
              window.value(forKey: "hostsLayersInWindowServer") as? Bool == true,
              let layer = nativeBackdrop(in: view.layer),
              layer.frame == view.bounds, layer.opacity == 1, layer.mask == nil, layer.isHidden == (gain == 0),
              layer.value(forKey: "context") as? NSObject === window.value(forKey: "_windowLayerContext") as? NSObject,
              layer.value(forKey: "groupName") as? String != nil,
              layer.value(forKey: "windowServerAware") as? Bool == true,
              layer.value(forKey: "allowsGroupBlending") as? Bool == false,
              layer.value(forKey: "scale") as? CGFloat == scale,
              layer.filters?.count == 1,
              let filter = layer.filters?.first as? NSObject,
              let radius = filter.value(forKey: "inputRadius") as? Double,
              filter.value(forKey: "inputMaskImage") != nil,
              abs(radius - 12 * GlowSpeechEnvelope.blurGain(gain)) < 0.000001 else {
            throw failure("Live variable-radius filter configuration failed at meter \(level).")
        }
        guard let root = view.layer, root.sublayers?.first === layer,
              let glow = root.sublayers?.dropFirst().first, glow.name == "speechBackgroundGlow",
              glow.compositingFilter as? String == "plusL", glow.mask != nil,
              glow.isHidden, glow.opacity <= 0.45,
              let color = view.subviews.first, color.layer?.superlayer === root,
              root.sublayers?.last === color.layer else {
            throw failure("The additive background glow must stay between the native sampler and SwiftUI waveform.")
        }
    }

    private static func verifyColorContinuity() throws {
        // ImageRenderer draws a generated SwiftUI view without a window or screen readback.
        let width = 384, height = 240
        for level in [0.3, 0.55] {
            let renderer = ImageRenderer(content: BottomGlow(level: level, strength: 1, phase: .recording,
                timeOverride: 1.7, reduceMotionOverride: false, reduceTransparencyOverride: false)
                .frame(width: CGFloat(width), height: CGFloat(height)))
            renderer.scale = 1
            guard let image = renderer.cgImage else { throw failure("Cannot render the generated waveform fixture.") }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw failure("Cannot allocate the generated waveform fixture.")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            for x in [width / 4, width / 2, width * 3 / 4] {
                let alpha = (0..<80).map { Int(pixels[((height - 1 - $0) * width + x) * 4 + 3]) }
                var minimum = alpha[0]
                for value in alpha {
                    guard value <= minimum + 1 else {
                        throw failure("The sweep has a brightness dip at meter \(level), x \(x).")
                    }
                    minimum = min(minimum, value)
                }
                guard alpha[0] > alpha[10], alpha[10] > alpha[40] else {
                    throw failure("The bottom sweep does not fade into a visible gradient.")
                }
            }
        }
        try GlowFixture.write(BottomGlow(level: 0.55, strength: 1, phase: .recording,
            timeOverride: 1.7, reduceMotionOverride: true, reduceTransparencyOverride: true),
            size: CGSize(width: 760, height: 240), name: "bottom")
        print("Generated Canvas rendering: continuous sweep falloff at meter 0.3/0.55 across three positions: PASS")
    }

    private static func verifyRadiusMaps() throws {
        for level in [0.3, 0.55, 1.0] {
            let profile = GlowHistory().frame(level: level, time: 1.7, reducedMotion: false)
            for size in [NSSize(width: 1800, height: GlowProfile.extent), NSSize(width: 1920, height: GlowProfile.extent + 80)] {
                guard let image = GlowBackdrop.mask(profile: profile, size: size),
                      let bitmap = image.representations.first as? NSBitmapImageRep,
                      image.size == size, bitmap.size == size, let data = bitmap.bitmapData else {
                    throw failure("Waveform radius map dimensions do not match the view.")
                }
                let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
                func alpha(_ x: Int, aboveBottom: Double) -> Int {
                    let y = min(height - 1, max(0, Int((1 - aboveBottom / size.height) * Double(height - 1))))
                    return Int(data[y * bitmap.bytesPerRow + x * 4 + 3])
                }
                for x in 0..<width {
                    guard alpha(x, aboveBottom: min(size.height - 2, 260 * 0.6673913 * 2 * profile.speechExpansion + 4)) == 0 else {
                        throw failure("Blur extends beyond the feathered color contour.")
                    }
                    var previous = 0
                    for y in 0..<height {
                        let value = Int(data[y * bitmap.bytesPerRow + x * 4 + 3])
                        guard value + 1 >= previous else { throw failure("Blur density decreased toward the bottom at x=\(x), y=\(y): \(previous) -> \(value).") }
                        previous = value
                    }
                }
                let center = width / 2
                let sampleHeight = 50.0
                guard alpha(0, aboveBottom: 0) < alpha(center, aboveBottom: 0) / 4,
                      alpha(width - 1, aboveBottom: 0) < alpha(center, aboveBottom: 0) / 4,
                      alpha(center, aboveBottom: 0) > alpha(center, aboveBottom: sampleHeight),
                      alpha(center, aboveBottom: sampleHeight) > alpha(width / 8, aboveBottom: sampleHeight),
                      alpha(center, aboveBottom: 0) > 100 else {
                    throw failure("Blur must follow the Chroma field: edges \(alpha(0, aboveBottom: 0))/\(alpha(width - 1, aboveBottom: 0)), center \(alpha(center, aboveBottom: 0)), inner \(alpha(center, aboveBottom: sampleHeight)), side \(alpha(width / 8, aboveBottom: sampleHeight)).")
                }
            }
        }
        print("Sweep blur field: continuous edges, radial attenuation, clear above the speech-responsive band, monotonic depth, resized coordinates: PASS")
    }

    private static func verifyPhasePersistence(in panel: NSPanel) async throws {
        let state = AppState(preview: true)
        state.phase = .recording
        var meter = 0.0
        state.glowStrength = 1
        panel.contentView = ProgressiveBackdropView.hosting(OverlayContent(state: state, levelProvider: { meter }))
        try await Task.sleep(nanoseconds: 120_000_000)
        guard let root = panel.contentView, let original = backdrop(in: root),
              let context = panel.value(forKey: "_windowLayerContext") as? NSObject else {
            throw failure("Normal overlay did not create its native backdrop.")
        }
        for level in [0.3, 0.55, 0.0] {
            meter = level
            try await Task.sleep(nanoseconds: 160_000_000)
            try verifyFilter(in: original, scale: panel.backingScaleFactor, level: level, smoothed: true)
        }
        meter = 0.55
        for phase in [DictationPhase.transcribing, .processing, .complete, .idle, .recording] {
            state.phase = phase
            try await Task.sleep(nanoseconds: 160_000_000)
            guard backdrop(in: root) === original, original.isBackdropAttached,
                  panel.value(forKey: "_windowLayerContext") as? NSObject === context else {
                throw failure("Dictation phase change replaced the backdrop or WindowServer context.")
            }
            try verifyFilter(in: original, scale: panel.backingScaleFactor, level: phase.busy ? 0 : 0.55, smoothed: true)
        }
        print("Normal overlay: live meter 0/0.3/0.55, one backdrop and WindowServer context through recording, transcription, processing, completion and restart: PASS")
    }

    private static func verifyTransparency(in panel: NSPanel) async throws {
        let glow = BottomGlow(level: 0.55, strength: 1, phase: .recording, timeOverride: 1.7, reduceTransparencyOverride: false, showsBackdrop: true)
        let root = ProgressiveBackdropView.hosting(AnyView(glow))
        panel.contentView = root
        try await Task.sleep(nanoseconds: 150_000_000)
        try verifyFilter(in: root, scale: panel.backingScaleFactor, level: 0.55)
        guard let color = root.subviews.first as? NSHostingView<AnyView> else { throw failure("Color host missing.") }
        var reduced = glow
        reduced.reduceTransparencyOverride = true
        color.rootView = AnyView(reduced)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard nativeBackdrop(in: root.layer)?.isHidden == true, root.profile == nil,
              color.superview === root else { throw failure("Reduce Transparency left the native sampler active.") }
        color.rootView = AnyView(glow)
        try await Task.sleep(nanoseconds: 150_000_000)
        try verifyFilter(in: root, scale: panel.backingScaleFactor, level: 0.55)
        print("Reduce Transparency: remove and restore native blur while retaining color host: PASS")
    }

    private static func verifyVisibility() async throws {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        defer { panel.orderOut(nil) }
        let clock = GlowAnimationClock()
        let visibility = OverlayVisibility(panel: panel, animationClock: clock)
        visibility.setVisible(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard panel.isVisible, panel.alphaValue > 0.99 else { throw failure("Overlay did not finish fading in.") }
        visibility.setVisible(false)
        try await Task.sleep(nanoseconds: 60_000_000)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard panel.isVisible, panel.alphaValue > 0, panel.alphaValue < 1 else { throw failure("Overlay snapped off instead of fading.") }
        }
        visibility.setVisible(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard panel.isVisible, panel.alphaValue > 0.99, clock.running else { throw failure("A stale fade-out hid a restarted overlay.") }
        visibility.setVisible(false)
        try await Task.sleep(nanoseconds: 320_000_000)
        guard !panel.isVisible, !clock.running else { throw failure("Hidden overlay kept its animation clock running.") }
        visibility.setVisible(true)
        guard clock.running else { throw failure("Restart did not resume the animation clock.") }
        print("Empty transparent panel: fade-in, fade-out, reversal, final hide: PASS")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "GlowProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
