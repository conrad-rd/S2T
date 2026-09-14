import AppKit
import SwiftUI
import S2TCore

@MainActor enum NotchProbe {
    static func run() async throws {
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try NotchFitProbe.run()
        try verifyFrameHandoff()
        let state = AppState(preview: true)
        let savedAppearance = state.glowAppearance
        defer { state.glowAppearance = savedAppearance }
        let menu = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        menu.menuNeedsUpdate(menu.menu)
        try AppearanceWindowProbe.verifyModeControls(state: state, menu: menu)

        let synthetic = GlowDisplay(frame: CGRect(x: -1512, y: 200, width: 1512, height: 982), safeTop: 32,
            topLeft: CGRect(x: -1512, y: 1150, width: 660, height: 32),
            topRight: CGRect(x: -660, y: 1150, width: 660, height: 32))
        let layouts = [TopGlowLayout(display: synthetic), TopGlowLayout(display: GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)))]
        for layout in layouts {
            try verifyMask(layout)
            try verifyQuietStrip(layout)
            try verifyGeneratedStrip(layout)
        }
        try await verifyControllerDisplays(state: state)
        for (index, screen) in NSScreen.screens.enumerated() {
            let detected = TopGlowLayout(display: GlowDisplay(screen: screen))
            for layout in layouts + [detected] { try await verifyHiddenOverlay(layout: layout, screen: screen, state: state) }
            print("Display \(index): \(screen.backingScaleFactor)x, detected \(detected.notch == nil ? "top fallback" : "notch"), hidden notch/fallback hosts and mode changes: PASS")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Foreground application changed.") }
        print("No menus opened or screen pixels captured. Physical notch fit and visible cross-app blur require user observation.")
    }

    private static func verifyMask(_ layout: TopGlowLayout) throws {
        for level in [0.3, 0.55] {
            var profile = GlowHistory().frame(level: level, time: 1.7, reducedMotion: false)
            profile.topLayout = layout
            guard let image = GlowBackdrop.mask(profile: profile, size: layout.frame.size),
                  let bitmap = image.representations.first as? NSBitmapImageRep, let pixels = bitmap.bitmapData,
                  image.size == layout.frame.size, bitmap.size == image.size else { throw failure("Top radius-map dimensions differ from the view.") }
            func alpha(x: CGFloat, y: CGFloat) -> UInt8 {
                let column = min(bitmap.pixelsWide - 1, max(0, Int(x)))
                let row = min(bitmap.pixelsHigh - 1, max(0, Int(y)))
                return pixels[row * bitmap.bytesPerRow + column * 4 + 3]
            }
            let depth = layout.notch?.height ?? 0
            let center = layout.frame.width / 2
            guard alpha(x: center, y: depth + 2) > alpha(x: center, y: depth + 9),
                  alpha(x: center, y: depth + 24) > 0,
                  alpha(x: center, y: depth + 64) <= alpha(x: center, y: depth + 24),
                  alpha(x: center, y: depth + 120) == 0,
                  alpha(x: 0, y: 2) == 0, alpha(x: layout.frame.width - 1, y: 2) == 0 else {
                throw failure("Top blur must fade away from the strip and both wings.")
            }
            if let notch = layout.notch {
                guard alpha(x: notch.midX, y: 10) == 0,
                      alpha(x: notch.minX - 1, y: 1) <= 1,
                      alpha(x: notch.maxX + 1, y: 1) <= 1,
                      alpha(x: notch.minX - 2, y: 12) > 0,
                      alpha(x: notch.maxX + 2, y: 12) > 0 else { throw failure("Blur crosses the housing or misses its sides: \([alpha(x: notch.midX, y: 10), alpha(x: notch.minX - 1, y: 1), alpha(x: notch.maxX + 1, y: 1), alpha(x: notch.minX - 2, y: 12), alpha(x: notch.maxX + 2, y: 12)]).") }
            }
        }
    }

    private static func verifyQuietStrip(_ layout: TopGlowLayout) throws {
        let renderer = ImageRenderer(content: TopGlow(layout: layout, strength: 1.3, phase: .recording,
            levelProvider: { 0 }, timeOverride: 1.7, reduceTransparencyOverride: true)
            .frame(width: layout.frame.width, height: layout.frame.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw failure("Quiet notch fixture could not render.") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var maximumAlpha = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                maximumAlpha = max(maximumAlpha, color.alphaComponent)

            }
        }
        guard maximumAlpha > 0, maximumAlpha < 0.65 else {
            throw failure("The quiet notch edge must remain faint.")
        }
        print("Generated quiet notch: thirty-percent colored glow: PASS")
    }

    private static func verifyGeneratedStrip(_ layout: TopGlowLayout) throws {
        let width = Int(layout.frame.width), height = Int(layout.frame.height)
        for level in [0.3, 0.55] {
            for phase in [DictationPhase.recording, .processing] {
                let renderer = ImageRenderer(content: TopGlow(layout: layout, strength: 1, phase: phase,
                    levelProvider: { level }, timeOverride: 1.7, reduceTransparencyOverride: true)
                    .frame(width: layout.frame.width, height: layout.frame.height))
                renderer.scale = 1
                guard let image = renderer.cgImage else { throw failure("Generated strip could not render.") }
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Generated fixture allocation failed.") }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                func alpha(_ x: CGFloat, _ y: CGFloat) -> Int {
                    Int(pixels[(Int(y) * width + Int(x)) * 4 + 3])
                }
                let depth = layout.notch?.height ?? 0
                let center = layout.frame.width / 2
                guard alpha(center, depth + 1) > 40,
                      alpha(center, depth + 1) > alpha(center, depth + 12),
                      (phase.busy || alpha(center, depth + 80) < alpha(center, depth + 24)),
                      alpha(1, 1) < 4, alpha(layout.frame.width - 2, 1) < 4 else {
                    throw failure("Generated color strip failed at meter \(level), alpha at 1/12/24/80 points: \([1, 12, 24, 80].map { alpha(center, depth + CGFloat($0)) }).")
                }
                if !phase.busy {
                    guard alpha(center, depth + 3) > alpha(center, depth + 18),
                          alpha(center, depth + 18) >= alpha(center, depth + 36) else {
                        throw failure("The notch color must fade continuously away from the rim.")
                    }
                    // The shared Bottom rim is brighter than the diffuse exterior field.
                    guard alpha(center, depth + 1) > alpha(center, depth + 5) else {
                        throw failure("The Bottom-style edge must remain brighter than its outer halo.")
                    }
                    guard alpha(center, depth + 24) <= alpha(center, depth + 12),
                          alpha(center, depth + 48) <= alpha(center, depth + 24),
                          alpha(center, layout.frame.height - 1) == 0 else {
                        throw failure("Chroma notch falloff must reach transparency inside its reserved field.")
                    }
                    let bounds = NotchAura.paletteBounds(layout: layout)
                    let row = Int(depth + 8)
                    for x in (Int(bounds.lowerBound) + 1)..<Int(bounds.upperBound) {
                        for channel in 0..<4 {
                            let a = Int(pixels[(row * width + x - 1) * 4 + channel])
                            let b = Int(pixels[(row * width + x) * 4 + channel])
                            guard abs(a - b) <= 8 else {
                                throw failure("Generated notch palette has an abrupt color seam.")
                            }
                        }
                    }
                    func channel(_ position: CGFloat, _ component: Int) -> Double {
                        let x = Int(bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * position)
                        let offset = (row * width + x) * 4
                        return Double(pixels[offset + component]) / Double(max(1, pixels[offset + 3]))
                    }
                    guard channel(0.33, 2) > channel(0.33, 0) + 0.25,
                          channel(0, 0) > channel(0.33, 0) + 0.15,
                          channel(0.83, 0) > channel(0.33, 0) + 0.35 else {
                        throw failure("The complete Bottom palette must fit beneath the notch or within the centered top strip.")
                    }

                }
                if let notch = layout.notch {
                    guard alpha(notch.midX, 10) == 0,
                          alpha(notch.minX - 1, 0) < 3,
                          alpha(notch.maxX, 0) < 3,
                          alpha(notch.minX - 3, 1) > 10,
                          alpha(notch.maxX + 2, 1) > 10,
                          alpha(notch.minX - 1, 12) > 30,
                          alpha(notch.maxX, 12) > 30,
                          alpha(notch.minX + 2, notch.maxY - 2) > 10,
                          alpha(notch.maxX - 3, notch.maxY - 2) > 10 else {
                        throw failure("Generated strip does not follow both rounded top joins, sides, and lower corners.")
                    }
                }
                if phase == .recording, level == 0.55,
                   let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_NOTCH_FIXTURE_DIR"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    for light in [false, true] {
                        context.setFillColor(CGColor(gray: light ? 1 : 0.10, alpha: 1))
                        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                        if light {
                            context.setFillColor(CGColor(gray: 0, alpha: 1))
                            context.fill(CGRect(x: 0, y: CGFloat(height) - depth - 8, width: CGFloat(width), height: depth + 8))
                        }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                        if let composed = context.makeImage(),
                           let png = NSBitmapImageRep(cgImage: composed).representation(using: .png, properties: [:]) {
                            let name = layout.notch == nil ? "generated-top-aura" : "generated-notch-aura"
                            try png.write(to: url.appendingPathComponent(name + (light ? "-light.png" : ".png")))
                        }
                    }
                }
            }
        }
        print("Generated \(layout.notch == nil ? "top" : "notch") Canvas: blue/violet/pink rim, broader eased color falloff with the native blur preserved, rounded joins, housing exclusion, fading wings, meter 0.3/0.55 and processing line: PASS")
    }

    private static func verifyHiddenOverlay(layout: TopGlowLayout, screen: NSScreen, state: AppState) async throws {
        let panel = BackdropWindowHosting.makePanel()
        panel.alphaValue = 0
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        defer { panel.orderOut(nil) }
        let placement = GlowOverlayPlacement()
        placement.top = layout
        var meter = 0.3
        state.phase = .recording
        state.glowStrength = 1
        let root = ProgressiveBackdropView.hosting(AnyView(OverlayContent(state: state, placement: placement, levelProvider: { meter })))
        panel.contentView = root
        panel.setFrame(CGRect(x: screen.frame.midX - layout.frame.width / 2, y: screen.frame.maxY - layout.frame.height,
                              width: layout.frame.width, height: layout.frame.height), display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        guard abs(panel.frame.maxY - screen.frame.maxY) < 0.5,
              panel.contentView?.bounds.size == layout.frame.size else { throw failure("AppKit moved or resized the top strip away from the screen edge.") }
        panel.orderFrontRegardless()
        try await Task.sleep(nanoseconds: 160_000_000)
        let sampler = root.layer?.sublayers?.first
        let context = panel.value(forKey: "_windowLayerContext") as? NSObject
        for phase in [DictationPhase.recording, .transcribing, .processing, .complete, .recording] {
            for level in [0.3, 0.55] {
                state.phase = phase
                meter = level
                try await Task.sleep(nanoseconds: 200_000_000)
                guard root === panel.contentView, root.isBackdropAttached,
                      root.layer?.sublayers?.first === sampler,
                      panel.value(forKey: "_windowLayerContext") as? NSObject === context,
                      panel.value(forKey: "hostsLayersInWindowServer") as? Bool == true,
                      BackdropWindowHosting.isEnabled(in: panel), panel.alphaValue == 0,
                      !panel.canBecomeKey, panel.ignoresMouseEvents else { throw failure("Top overlay lost its native host or click-through behavior.") }
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    guard root.profile?.topLayout == layout,
                          let filter = sampler?.filters?.first as? NSObject,
                          abs((filter.value(forKey: "inputRadius") as? Double ?? -1) - (phase.busy ? 0 : (root.profile?.chromaGeometry.maximumBlurRadius ?? -1) * (root.profile?.blurGain ?? -1))) < 0.000001,
                          sampler?.isHidden == phase.busy else { throw failure("Top overlay did not forward its live frame or processing state.") }
                }
            }
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            meter = 0
            try await Task.sleep(nanoseconds: 25_000_000)
            guard (root.profile?.energy ?? 0) > 0, sampler?.isHidden == false,
                  root.layer?.sublayers?.first === sampler else {
                throw failure("A brief microphone gap blanked the notch or replaced its sampler.")
            }
            meter = 0.55
            try await Task.sleep(nanoseconds: 120_000_000)
            meter = 0
            try await Task.sleep(nanoseconds: 520_000_000)
            guard root.profile?.energy == 0, sampler?.isHidden == false,
                  root.layer?.sublayers?.first === sampler else {
                throw failure("Sustained silence failed to retain the quiet notch while retaining its sampler.")
            }
            meter = 0.55
            state.phase = .processing
            try await Task.sleep(nanoseconds: 90_000_000)
            guard root.profile?.energy == 0, sampler?.isHidden == true else {
                throw failure("Processing retained smoothed microphone energy.")
            }
            state.phase = .recording
        }
        placement.top = nil
        panel.setContentSize(CGSize(width: screen.frame.width, height: 240))
        try await Task.sleep(nanoseconds: 160_000_000)
        guard root.profile?.topLayout == nil, root.layer?.sublayers?.first === sampler else { throw failure("Switching to Bottom replaced the sampler.") }
        placement.top = layout
        panel.setContentSize(layout.frame.size)
        try await Task.sleep(nanoseconds: 160_000_000)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            guard root.profile?.topLayout == layout else { throw failure("Switching back did not restore notch geometry.") }
        }
        let color = root.subviews.first as! NSHostingView<AnyView>
        var top = TopGlow(layout: layout, strength: 1, phase: .recording,
            levelProvider: { 0.55 }, timeOverride: 1.7, reduceTransparencyOverride: false)
        color.rootView = AnyView(top)
        try await Task.sleep(nanoseconds: 160_000_000)
        guard sampler?.isHidden == false else { throw failure("Top sampler failed before transparency check.") }
        top.reduceTransparencyOverride = true
        color.rootView = AnyView(top)
        try await Task.sleep(nanoseconds: 160_000_000)
        guard sampler?.isHidden == true, root.profile == nil else { throw failure("Reduced transparency left a native blur active.") }

    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NotchProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func verifyFrameHandoff() throws {
        let panel = BackdropWindowHosting.makePanel()
        panel.setFrame(CGRect(x: 0, y: 0, width: 336, height: 96), display: false)
        let root = ProgressiveBackdropView(frame: panel.contentLayoutRect)
        panel.contentView = root
        let old = GlowBackdropBridge()
        let current = GlowBackdropBridge()
        root.addSubview(old)
        root.addSubview(current)
        let first = GlowHistory().frame(level: 0.55, time: 1.7, reducedMotion: false)
        let second = GlowHistory().frame(level: 0.3, time: 1.7, reducedMotion: false)
        old.apply(profile: first, radiusMap: nil)
        current.apply(profile: second, radiusMap: nil)
        old.clear()
        guard root.profile?.energy == second.energy, root.isBackdropAttached else {
            throw failure("A departing glow view cleared the replacement's frame, causing a blank frame.")
        }
        old.viewDidMoveToWindow()
        guard root.profile?.energy == second.energy else { throw failure("A cleared glow view resubmitted its stale frame.") }
        current.clear()
        guard root.profile == nil else { throw failure("The current glow view did not disable the sampler when cleared.") }
        print("Frame handoff: stale teardown cannot blank or replace the new frame, current teardown still clears: PASS")
    }

    private static func verifyControllerDisplays(state: AppState) async throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw failure("No displays available for placement verification.") }
        state.glowAppearance = .aroundNotch
        state.phase = .recording
        let controller = GlowWindowController(state: state)
        var originalPanel: NSPanel?
        var originalRoot: ProgressiveBackdropView?
        var originalSampler: CALayer?
        defer { originalPanel?.orderOut(nil) }
        for screen in screens + screens.reversed() {
            let pointer = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
            let expected = TopGlowLayout(display: GlowDisplay(screen: screen))
            guard let panel = controller.prepareWindow(screens: screens, pointer: pointer),
                  let root = panel.contentView as? ProgressiveBackdropView,
                  let host = root.subviews.first as? NSHostingView<OverlayContent>,
                  host.rootView.placement.top == expected,
                  panel.frame == expected.frame else { throw failure("Controller did not start at the selected display's top edge.") }
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 160_000_000)
            if originalPanel == nil {
                originalPanel = panel
                originalRoot = root
                originalSampler = root.layer?.sublayers?.first
            }
            guard panel === originalPanel, root === originalRoot,
                  root.layer?.sublayers?.first === originalSampler,
                  root.isBackdropAttached, BackdropWindowHosting.isEnabled(in: panel),
                  panel.value(forKey: "hostsLayersInWindowServer") as? Bool == true else {
                throw failure("Moving displays replaced the overlay or lost its native sampler.")
            }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                guard root.profile?.topLayout == expected else { throw failure("Displayed glow used stale geometry from the previous screen.") }
            }
            var publications = 0
            let observation = host.rootView.placement.objectWillChange.sink { publications += 1 }
            for _ in 0..<20 { _ = controller.prepareWindow(screens: screens, pointer: pointer) }
            observation.cancel()
            guard publications == 0 else { throw failure("Unchanged display polling redrew the placement.") }
        }
        let screen = screens[0]
        let pointer = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        state.glowAppearance = .bottom
        guard let bottom = controller.prepareWindow(screens: screens, pointer: pointer),
              bottom.frame.minY == screen.frame.minY,
              bottom.frame.width == screen.frame.width else { throw failure("Bottom mode changed placement.") }
        state.glowAppearance = .aroundNotch
        _ = controller.prepareWindow(screens: screens, pointer: pointer)
        try await Task.sleep(nanoseconds: 160_000_000)
        guard originalPanel?.contentView === originalRoot else { throw failure("Mode change replaced the native content view.") }
        print("Production controller: per-display top placement, notch/external round trips, configured initial view, stable sampler, unchanged polling and Bottom mode: PASS")
    }
}
