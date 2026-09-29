import AppKit
import S2TCore

@MainActor enum GlassWaveformProbe {
    static func run() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "GlassWaveform", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try verifyArtwork()
        if CommandLine.arguments.contains("--export-glass-fixture") { try exportGradientFixture() }
        let state = AppState(preview: true)
        let saved = state.glowAppearance
        let savedAnchor = state.classicAnchor
        state.classicAnchor = nil
        defer { state.glowAppearance = saved; state.classicAnchor = savedAnchor }
        try check(GlowAppearance.allCases.count == 6 && GlowAppearance.allCases.last == .liquidGlass, "Liquid Glass must be sixth")
        state.glowAppearance = .liquidGlass
        try check(AppState(preview: true).glowAppearance == .liquidGlass, "Appearance must persist")
        let settings = AppearanceWindowController(state: state, presentsWindows: false)
        _ = settings.prepare()
        defer { settings.window?.close() }
        settings.selectPreview(.bottom)
        settings.selectPreview(.liquidGlass)
        settings.refresh()
        try check(state.glowAppearance == .liquidGlass && !settings.controlsPanel.isHidden && settings.adjustments.isHidden,
            "Preview action must select glass without irrelevant glow sliders")
        try check(settings.sidebar.backgroundMode == .liquidGlass && settings.sidebar.backdrop.wallpaperLayer.contents != nil,
            "Classic must retain the Bezel background")
        let controller = GlassWaveformController(state: state, presentsWindows: false)
        for screen in NSScreen.screens {
            guard let panel = controller.prepareWindow(screens: [screen], pointer: screen.frame.origin),
                  let view = controller.indicator else { throw NSError(domain: "GlassWaveform", code: 2) }
            try check(!panel.isVisible && panel.ignoresMouseEvents && panel.styleMask.contains(.nonactivatingPanel),
                "Panel must remain hidden, click-through and nonactivating")
            try check(BackdropWindowHosting.isEnabled(in: panel), "Native composition configuration lost")
            try check(abs(panel.frame.midX - screen.frame.midX) <= 0.5 && screen.frame.contains(view.bodyRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)),
                "Glass must be centered on the selected display: \(panel.frame), \(screen.visibleFrame)")
            try check(abs(panel.frame.minY + view.bodyRect.minY - screen.visibleFrame.minY - 32) < 0.5,
                "Capsule must sit 32 points above the Dock while remaining horizontally centered")
            view.update(spectrum: [1, 0, 0, 0, 0, 0, 0], symbol: .waveform, time: 1,
                reducedMotion: true, reducedTransparency: false)
            try check(view.bands == [1, 0, 0, 0, 0, 0, 0], "Low frequencies must drive their own bar")
            if #available(macOS 26.0, *) {
                try check(view.glass is NSGlassEffectView, "Glass must use the native refraction effect")
                let effect = view.glass as! NSGlassEffectView
                panel.contentView?.layoutSubtreeIfNeeded()
                try check(effect.contentView === view.materialContent,
                    "Black artwork and waveform must be inside the native glass content view")
                try check(effect.cornerRadius == 18 && effect.frame.size == CGSize(width: 112, height: 36),
                    "Reference capsule changed: radius \(effect.cornerRadius), frame \(effect.frame)")
            }
            try check(view.bodyRect.size == CGSize(width: 112, height: 36), "Capsule must stay compact")
            try check(view.dropShadow.shadowRadius == 4 && abs(view.dropShadow.shadowOpacity - 0.14) < 0.001,
                "Drop shadow must stay subtle and outside the clipped capsule")
            try check(view.cancelButton.frame == CGRect(x: 6, y: 6, width: 24, height: 24),
                "Cancel circle must be concentric with the left capsule end")
            try check(view.animation.scaleX == 1 && view.animation.scaleY == 1,
                "Reduce Motion must stop all capsule deformation")
            try check(view.animation.offsetY == 0, "Reduce Motion must stop entrance travel")
            try check(view.waveformView.contentFilters.isEmpty, "Waveform must stay sharp")
            try check(view.waveformView.bounds.size == CGSize(width: 44, height: 24),
                "Waveform must fit the smaller capsule")
            view.update(spectrum: [0, 0, 0, 0, 0, 0, 1], symbol: .waveform, time: 2,
                reducedMotion: true, reducedTransparency: false)
            try check(view.bands == [0, 0, 0, 0, 0, 0, 1], "Equal-volume pitch changes must change the waveform")
            for symbol in [BezelSymbol.spinner, .checkmark, .failure] {
                view.update(spectrum: [], symbol: symbol, time: 3, reducedMotion: true, reducedTransparency: true)
                try check(view.bands.allSatisfy { $0 == 0 }, "Silence must clear bands")
                if #available(macOS 26.0, *) { try check(!(view.glass is NSGlassEffectView), "Reduce Transparency must remove native glass") }
            }
            view.update(spectrum: [.nan, .infinity, -1, 2], symbol: .waveform, time: 4,
                reducedMotion: false, reducedTransparency: false)
            try check(view.bands.allSatisfy { $0.isFinite && (0...1).contains($0) }, "Invalid meter data must not escape bounds")
            view.restart()
            for frame in 0...48 {
                view.update(spectrum: [], symbol: .waveform, time: 100 + Double(frame) / 60,
                    reducedMotion: false, reducedTransparency: false)
                let position = view.glass?.superview?.layer?.position
                try check(position?.y == view.bodyRect.midY + view.animation.offsetY
                    && view.dropShadow.position == position, "Native glass and shadow must rise together")
                try check(view.bounds.contains(view.animatedBodyRect.insetBy(dx: -5, dy: -5)),
                    "Entrance and overshoot must fit inside the transparent window padding")
            }
            controller.show(screens: [screen], pointer: screen.frame.origin)
            controller.hide()
            controller.show(screens: [screen], pointer: screen.frame.origin)
            controller.hide()
            try check(!panel.isVisible && controller.interactionPanel?.isVisible == false,
                "Verification must never present either window")
            guard let control = controller.interactionPanel else { throw NSError(domain: "GlassWaveform", code: 3) }
            try check(!control.canBecomeKey && !control.canBecomeMain,
                "Capsule interactions must not activate the app")
            for waiting in [false, true] {
                state.phase = waiting ? .complete : .recording
                state.isWaitingToPaste = waiting
                state.overlayVisible = true
                controller.tick(at: 10)
                let expected = view.animatedBodyRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
                try check(abs(control.frame.midX - expected.midX) <= 1 && abs(control.frame.midY - expected.midY) <= 1
                    && abs(control.frame.width - expected.width) <= 1 && abs(control.frame.height - expected.height) <= 1
                    && control.button.isEnabled,
                    "Interaction target must follow the animated capsule during recording and pending delivery: \(control.frame), expected \(expected), enabled \(control.button.isEnabled)")
                control.button.performClick(nil)
                try check(state.phase == .idle && !state.isWaitingToPaste && !state.overlayVisible,
                    "Cancel button must stop recording and cancel pending insertion")
            }
            state.phase = .complete
            controller.tick(at: 12)
            try check(view.processingGradient == (state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init()),
                "Live capsule must use the saved Within Input gradient")
            try check(!control.button.isEnabled && !control.isVisible,
                "Success must remove the cancel target")
        }
        try verifyDragging()
        try check(BezelSymbol.resolve(phase: .complete, waiting: true, deliveryHint: nil) == .spinner,
            "Pending insertion must not report success")
        print("Liquid Glass passed: native glass, restrained entrance, custom capsule-bar loading, center snap and release, saved position, cancel action, accessibility and hidden-window restart. No screen or microphone capture.")
    }
    private static func exportGradientFixture() throws {
        let context = CGContext(data: nil, width: 1200, height: 328, bitsPerComponent: 8, bytesPerRow: 1200 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        for row in 0..<2 {
            context.setFillColor(CGColor(gray: row == 0 ? 0.16 : 0.78, alpha: 1))
            context.fill(CGRect(x: 0, y: row * 82, width: 600, height: 82))
            for column in 0..<4 {
                let rect = CGRect(x: 19 + column * 150, y: 23 + row * 82, width: 112, height: 36)
                GlassCapsuleArtwork.drawOverlay(in: rect, context: context)
                GlassCapsuleArtwork.drawProcessing(in: rect, time: Double(column) * 0.45, context: context)
                GlassCapsuleArtwork.drawCancel(in: CGRect(x: rect.minX + 6, y: rect.minY + 6, width: 24, height: 24),
                    pressed: false, context: context)
            }
        }
        let image = NSBitmapImageRep(cgImage: context.makeImage()!)
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/s2t-glass-gradient.png"))
        print("Authored gradient fixture: /tmp/s2t-glass-gradient.png. No screen content sampled.")
    }

    private static func verifyDragging() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "GlassDragging", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        guard let screen = NSScreen.screens.first else { return }
        var saved: Data?
        let store = GlassCapsulePlacementStore(read: { saved }, write: { saved = $0 })
        let state = AppState(preview: true)
        state.phase = .recording
        let controller = GlassWaveformController(state: state, presentsWindows: false, placement: store)
        guard let panel = controller.prepareWindow(screens: [screen], pointer: screen.frame.origin),
              let view = controller.indicator, let controls = controller.interactionPanel else { return }
        controller.tick(at: 1)
        controller.tick(at: 2)
        func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: controls.convertPoint(fromScreen: point), modifierFlags: [],
                timestamp: 2, windowNumber: controls.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let start = CGPoint(x: controls.frame.midX + 10, y: controls.frame.midY)
        controls.updateHitTesting(pointer: CGPoint(x: controls.frame.minX, y: controls.frame.minY))
        try require(controls.ignoresMouseEvents, "Transparent capsule corners must pass clicks through")
        controls.updateHitTesting(pointer: start)
        try require(!controls.ignoresMouseEvents && controls.interaction.acceptsFirstMouse(for: nil),
            "The capsule must accept a drag without taking focus")
        controls.interaction.mouseDown(with: event(.leftMouseDown, at: start))
        let near = CGPoint(x: start.x + 20, y: start.y + 80)
        controls.interaction.mouseDragged(with: event(.leftMouseDragged, at: near))
        try require(abs(panel.frame.midX - screen.frame.midX) <= 1, "Centered capsule must resist a small sideways drag")
        let away = CGPoint(x: start.x + 60, y: start.y + 80)
        controls.interaction.mouseDragged(with: event(.leftMouseDragged, at: away))
        try require(abs(panel.frame.midX - screen.frame.midX - 60) <= 1, "Deliberate pull must release center snapping")
        controls.interaction.mouseUp(with: event(.leftMouseUp, at: away))
        try require(saved != nil && !controls.interaction.tracking, "Dropping must save the position")
        let pinnedFrame = panel.frame
        controller.hide()
        let restored = GlassWaveformController(state: state, presentsWindows: false,
            placement: GlassCapsulePlacementStore(read: { saved }, write: { saved = $0 }))
        let restoredPanel = restored.prepareWindow(screens: NSScreen.screens, pointer: screen.frame.origin)
        try require(restoredPanel?.frame == pinnedFrame, "A new controller must restore the saved screen and position")
        try require(!panel.isVisible && !controls.isVisible && restoredPanel?.isVisible == false,
            "Drag verification must never show windows")
        let buttonCenter = CGPoint(x: controls.button.frame.midX, y: controls.button.frame.midY)
        try require(controls.interaction.hitTest(buttonCenter) === controls.button,
            "Cancel button must retain its own hit target inside the draggable capsule")
        try require(view.bodyRect.size == CGSize(width: 112, height: 36), "Dragging must not resize the settled capsule")
    }

    private static func verifyArtwork() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "GlassArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let size = CGSize(width: 112, height: 36)
        let rect = CGRect(origin: .zero, size: size)
        let path = GlassCapsuleArtwork.path(in: rect)
        try require(path.contains(CGPoint(x: 0.1, y: 18)) && !path.contains(CGPoint(x: 4, y: 4)),
            "Capsule ends must be circular, not rounded rectangle corners")
        func fixture(_ background: CGColor) -> CGContext {
            let context = CGContext(data: nil, width: 112, height: 36, bitsPerComponent: 8, bytesPerRow: 112 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(background)
            context.fill(rect)
            GlassCapsuleArtwork.drawOverlay(in: rect, context: context)
            return context
        }
        func rgb(_ context: CGContext, x: Int, y: Int) -> [Int] {
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            return (0..<3).map { Int(data[(context.height - 1 - y) * context.bytesPerRow + x * 4 + $0]) }
        }
        let light = fixture(CGColor(red: 1, green: 0.7, blue: 0.4, alpha: 1))
        let dark = fixture(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
        for y in 20..<34 {
            try require(rgb(light, x: 56, y: y).max()! <= 1, "Upper half must paint opaque black")
            try require(rgb(light, x: 56, y: y) == rgb(dark, x: 56, y: y), "Upper black must not depend on the backdrop")
        }
        let lowerLight = rgb(light, x: 56, y: 3), lowerDark = rgb(dark, x: 56, y: 3)
        try require(abs(lowerLight[0] - lowerDark[0]) > 80, "Lower glass must reveal its backdrop")
        let sideLight = rgb(light, x: 2, y: 18), sideDark = rgb(dark, x: 2, y: 18)
        let sideDifference = abs(sideLight[0] - sideDark[0])
        try require((8...40).contains(sideDifference),
            "Side reflection must remain restrained, without a bright U-shaped rim")
        try require(rgb(light, x: 56, y: 18).max()! <= 1,
            "The center must remain black at the same height as the side reflection")
        // Independent samples from the supplied reference at 23 percent of its width,
        // away from the waveform. Allow up to ten additional channel levels for the
        // requested increase in lower transparency, beyond the original 12-level tolerance.
        let blue = fixture(CGColor(red: 85.0 / 255, green: 115.0 / 255, blue: 155.0 / 255, alpha: 1))
        let reference: [(Double, [Int])] = [(0.6, [2, 1, 3]), (0.7, [3, 5, 10]),
            (0.8, [10, 19, 27]), (0.9, [32, 45, 62]), (0.94, [42, 59, 80])]
        for (depth, expected) in reference {
            let actual = rgb(blue, x: 26, y: Int((1 - depth) * 36))
            try require(zip(actual, expected).allSatisfy { (-12...22).contains($0 - $1) },
                "Lower falloff no longer agrees with the supplied reference at \(depth): \(actual)")
        }
        func animationFixture(time: Double, success: Bool = false, reducedMotion: Bool = false,
                              opacity: Double = 1) -> [UInt8] {
            let context = CGContext(data: nil, width: 112, height: 36, bitsPerComponent: 8, bytesPerRow: 112 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setAlpha(opacity)
            if success {
                GlassCapsuleArtwork.drawSuccess(center: CGPoint(x: 56, y: 18), elapsed: time,
                    reducedMotion: reducedMotion, context: context)
            } else {
                GlassCapsuleArtwork.drawProcessing(in: rect, time: time,
                    reducedMotion: reducedMotion, context: context)
            }
            return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 112 * 36 * 4))
        }
        let first = animationFixture(time: 0), second = animationFixture(time: 0.35)
        let half = animationFixture(time: 0, opacity: 0.5)
        let fullAlpha = stride(from: 3, to: first.count, by: 4).reduce(0) { $0 + Int(first[$1]) }
        let halfAlpha = stride(from: 3, to: half.count, by: 4).reduce(0) { $0 + Int(half[$1]) }
        try require(halfAlpha > 0 && halfAlpha < fullAlpha && zip(first, half).allSatisfy { abs(Int($0) - 2 * Int($1)) <= 2 },
            "The capsule bars must preserve the capsule phase crossfade: \(halfAlpha)/\(fullAlpha)")
        try require(first != second, "The loading bars must animate")
        for time in stride(from: 0.0, through: 1.8, by: 0.3) {
            let pixels = animationFixture(time: time)
            var groups = 0
            var previousLit = false
            for x in 0..<112 {
                let lit = (0..<36).contains { pixels[($0 * 112 + x) * 4 + 3] > 8 }
                if lit && !previousLit { groups += 1 }
                previousLit = lit
            }
            try require(groups == 5, "Processing must show five separate rounded waveform-like bars")
            for y in 0..<36 { for x in 0..<112 where x < 50 || x > 85 || y < 9 || y > 26 {
                try require(pixels[(y * 112 + x) * 4 + 3] == 0,
                    "Processing must stay in the waveform area and clear the cancel button and rim")
            } }
            for y in 0..<36 { for x in 0..<112 where pixels[(y * 112 + x) * 4 + 3] > 8 {
                let offset = (y * 112 + x) * 4
                try require(path.contains(CGPoint(x: Double(x) + 0.5, y: 35.5 - Double(y))),
                    "Loading gradient must stay inside the capsule")
            } }
        }
        let wrapped = animationFixture(time: GlassCapsuleArtwork.processingCycle)
        try require(zip(first, wrapped).allSatisfy { abs(Int($0) - Int($1)) <= 1 },
            "Loading gradient loop must close without a jump")
        try require(zip(animationFixture(time: 0, reducedMotion: true), animationFixture(time: 0.7, reducedMotion: true))
            .allSatisfy { abs(Int($0) - Int($1)) <= 1 },
            "Reduce Motion must freeze the loader")
        try require(animationFixture(time: 0.1, success: true) != animationFixture(time: 0.7, success: true),
            "Success must draw into its final checkmark")
        try require(animationFixture(time: 0, success: true, reducedMotion: true)
            == animationFixture(time: 0.7, success: true, reducedMotion: true), "Reduce Motion must show a stable completed checkmark")

    }

}
