import AppKit
import S2TCore

@MainActor enum BezelProbe {
    static func run() throws {
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try Microphone.verifySpectrumCapture()
        try verifyRadiusMaps()
        try verifyDrawnShadow()
        try verifyDragRendering()
        measureDragRendering()
        try verifyDockingContours()
        try BezelRenderingProbe.run()
        let spectrumView = BezelIndicatorView(frame: CGRect(origin: .zero, size: BezelGeometry.size))
        for index in 0...20 {
            spectrumView.update(form: .shown, symbol: .waveform, level: 0.5,
                spectrum: [0.9, 0.1, 0.65, 0, 0.4, 0.2, 0.75], time: Double(index) / 60, reducedMotion: false)
        }
        guard spectrumView.bands[0] > spectrumView.bands[1] + 0.6,
              spectrumView.bands[6] > spectrumView.bands[5] + 0.4 else { throw failure("The native bars lost their independent frequency levels.") }
        for side in BezelSide.allCases {
            spectrumView.side = side
            let shape = spectrumView.displayedShape
            let edgeX = side == .left ? 2.0 : BezelGeometry.size.width - 2
            for offset in [-66.0, 66] {
                guard !shape.path.contains(CGPoint(x: edgeX, y: BezelGeometry.size.height / 2 + offset)) else {
                    throw failure("The rendered shape still has a protruding tab beyond its connector.")
                }
            }
            guard shape.path.contains(shape.symbolCenter) else { throw failure("The waveform moved outside the attached body.") }
        }
        let state = AppState(preview: true)
        let appearance = state.glowAppearance
        let side = state.bezelSide
        defer { state.glowAppearance = appearance; state.bezelSide = side }
        let menu = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        menu.menuNeedsUpdate(menu.menu)
        try AppearanceWindowProbe.verifyModeControls(state: state, menu: menu)
        state.glowAppearance = .bezel
        let controls = menu.appearanceWindow
        controls.prepare()
        for (index, side) in BezelSide.allCases.enumerated() {
            controls.sidePicker.selectedSegment = index
            controls.sidePicker.sendAction(controls.sidePicker.action, to: controls.sidePicker.target)
            guard state.bezelSide == side, AppState(preview: true).bezelSide == side else { throw failure("Bezel side persistence failed") }
        }
        controls.window?.close()
        for (phase, waiting, hint, symbol) in [
            (DictationPhase.recording, false, nil as String?, BezelSymbol.waveform),
            (.monitoring, false, nil, .waveform), (.preparing, false, nil, .waveform),
            (.transcribing, false, nil, .spinner), (.processing, false, nil, .spinner),
            (.complete, true, nil, .spinner), (.complete, false, nil, .checkmark),
            (.complete, false, "Allow Accessibility", .failure), (.failed, false, nil, .failure)
        ] {
            guard BezelSymbol.resolve(phase: phase, waiting: waiting, deliveryHint: hint) == symbol else { throw failure("Incorrect phase symbol.") }
        }
        let controller = BezelWindowController(state: state, presentsWindows: false)
        state.phase = .recording
        if let screen = NSScreen.screens.first {
            let animated = BezelWindowController(state: state, presentsWindows: false)
            animated.show(screens: [screen], pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
            let started = ProcessInfo.processInfo.systemUptime
            animated.tick(at: started + 0.14)
            guard let view = animated.indicator else { throw failure("Missing animated indicator.") }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                guard view.form == .shown else { throw failure("Reduce Motion did not skip deformation.") }
            } else {
                guard view.form.depth > view.form.body + 0.1, view.form != .shown else { throw failure("Entry does not deform the native view.") }
                animated.tick(at: started + 0.35)
                guard view.form.body > 1 else { throw failure("Entry does not stretch before settling.") }
            }
            animated.hide()
            animated.tick(at: ProcessInfo.processInfo.systemUptime + 1)
            guard view.form == .hidden, animated.panel?.isVisible == false else { throw failure("Animated fixture did not retract.") }
        }
        for screen in NSScreen.screens {
            for side in BezelSide.allCases {
                state.bezelSide = side
                guard let panel = controller.prepareWindow(screens: [screen], pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY)),
                      panel.frame == BezelGeometry.frame(screen: screen.frame, side: side),
                      panel.ignoresMouseEvents, !panel.canBecomeKey, !panel.canBecomeMain,
                      !panel.isVisible, let view = controller.indicator, view.window === panel else {
                    throw failure("Hidden panel contract failed: frame=\(String(describing: controller.panel?.frame)), expected=\(BezelGeometry.frame(screen: screen.frame, side: side)), visible=\(String(describing: controller.panel?.isVisible)), key=\(String(describing: controller.panel?.canBecomeKey)), main=\(String(describing: controller.panel?.canBecomeMain)), attached=\(controller.indicator?.window === controller.panel).")
                }
                for phase in [DictationPhase.recording, .processing, .complete, .failed] {
                    state.phase = phase
                    controller.show(screens: [screen], pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
                    controller.tick(at: ProcessInfo.processInfo.systemUptime + 1)
                    panel.contentView?.layoutSubtreeIfNeeded()
                    panel.displayIfNeeded()
                    guard view.symbol == BezelSymbol.resolve(phase: phase, waiting: false, deliveryHint: nil),
                          view.form == .shown, !panel.isVisible else { throw failure("Hidden phase rendering failed.") }
                    let shape = view.displayedShape
                    let bodyOnScreen = panel.convertToScreen(view.convert(shape.path.boundingBoxOfPath, to: nil))
                    let symbolInWindow = view.convert(shape.symbolCenter, to: nil)
                    let symbolOnScreen = panel.convertPoint(toScreen: symbolInWindow)
                    guard abs(symbolOnScreen.x - bodyOnScreen.midX) < 0.001,
                          abs((side == .left ? bodyOnScreen.minX : bodyOnScreen.maxX) -
                              (side == .left ? screen.frame.minX : screen.frame.maxX)) < 0.001 else {
                        throw failure("The packaged body has a screen-edge gap or unequal symbol padding.")
                    }
                    try verifyBackdrop(controller, panel: panel)
                }
                controller.hide()
                controller.show(screens: [screen], pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
                controller.tick(at: ProcessInfo.processInfo.systemUptime + 1)
                guard view.form == .shown else { throw failure("Restart lost the indicator.") }
                controller.hide()
                controller.tick(at: ProcessInfo.processInfo.systemUptime + 1)
                guard view.form == .hidden, !panel.isVisible else { throw failure("Retraction did not finish.") }
                guard controller.backdrop?.profile == nil else { throw failure("Retraction left blur behind.") }
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Foreground application changed.") }
        print("Bezel: connector merging into the screen edge without tabs, body-aligned spectrum, menu actions, side persistence, phase symbols, intermediate liquid deformation, hidden windows on all displays, retraction/restart, and focus preservation PASS.")
        print("Bezel backdrop: progressive contour radius maps, bounded exterior fade, WindowServer hosting, phase persistence and Reduce Transparency PASS.")
        print("No screen capture, real microphone, credentials, or text insertion used. Visible animation has not been visually verified.")
    }

    private static func verifyRadiusMaps() throws {
        for side in BezelSide.allCases {
            let shape = BezelGeometry.shape(form: .shown, side: side, tilt: 1)
            let profile = GlowProfile(energy: 1, heights: [], bezel: BezelBackdrop(path: shape.path))
            guard let image = GlowBackdrop.mask(profile: profile, size: BezelGeometry.size),
                  image.size == BezelGeometry.size,
                  let bitmap = image.representations.first as? NSBitmapImageRep,
                  bitmap.size == image.size else { throw failure("Bezel radius map has incorrect logical dimensions.") }
            let front = side == .left ? shape.path.boundingBoxOfPath.maxX : shape.path.boundingBoxOfPath.minX
            let direction = side == .left ? 1.0 : -1.0
            func alpha(_ distance: Double) -> Double {
                Double(bitmap.colorAt(x: Int(front + direction * distance), y: Int(shape.symbolCenter.y))?.alphaComponent ?? -1)
            }
            let values = [-6.0, 1, 30, 60, 125].map(alpha)
            guard values[0] > 0.98, values[1] > 0.98,
                  values[1] >= values[2], values[2] > values[3], values[3] > 0, values[4] == 0,
                  BezelBackdrop.opacity == 1,
                  BezelBackdrop.extent / shape.path.boundingBoxOfPath.width >= 2,
                  BezelBackdrop.extent / shape.path.boundingBoxOfPath.width <= 3 else {
                throw failure("Bezel blur must have a broad, extremely faint falloff with no tight blur rim: \(values).")
            }
            let samples = (1...125).map { alpha(Double($0)) }
            guard zip(samples, samples.dropFirst()).allSatisfy({ $1 <= $0 && $0 - $1 <= 5.1 / 255 }) else {
                throw failure("The exterior falloff has an abrupt change or a secondary ring.")
            }
            var motion = BezelMotion()
            motion.setVisible(true, at: 0)
            for step in 1...60 {
                let bounds = BezelGeometry.shape(form: motion.form(at: Double(step) / 60), side: side).path.boundingBoxOfPath
                let clearance = side == .left ? BezelGeometry.size.width - bounds.maxX : bounds.minX
                guard clearance >= BezelBackdrop.extent else { throw failure("Elastic motion clips the blur fade.") }
                guard min(bounds.minY, BezelGeometry.size.height - bounds.maxY) >= BezelBackdrop.extent else {
                    throw failure("Elastic motion clips the broad blur above or below the bezel.")
                }
            }
        }
    }

    private static func measureDragRendering() {
        let size = BezelGeometry.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 760,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 1600, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        let view = BezelIndicatorView(frame: CGRect(origin: .zero, size: size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.translateBy(x: 0, y: 760)
        graphics.cgContext.scaleBy(x: 2, y: -2)
        defer { NSGraphicsContext.restoreGraphicsState() }
        for moving in [false, true] {
            var times: [Double] = []
            for index in 0..<90 {
                let t = Double(index) / 60
                let velocity = moving ? CGVector(dx: 850 * cos(t), dy: 850 * sin(t)) : .zero
                view.dragVelocity = velocity
                view.previewShape = BezelDragShape.make(velocity: velocity)
                view.update(form: .shown, symbol: .waveform, level: 0.6,
                    spectrum: (0..<7).map { 0.5 + 0.3 * sin(t * 4 + Double($0)) }, time: t, reducedMotion: false)
                let start = CACurrentMediaTime()
                view.draw(view.bounds)
                times.append((CACurrentMediaTime() - start) * 1000)
            }
            times.sort()
            print("Drag render \(moving ? "moving" : "still") ms: median \(times[45]), p95 \(times[85]), max \(times.last!)")
        }
    }

    private static func verifyDockingContours() throws {
        for side in BezelSide.allCases {
            for distance in [32.0, 55, 78] {
                let source = BezelDragShape.make(velocity: .zero, side: side, distance: distance)
                let attached = BezelGeometry.shape(form: .shown, side: side)
                let edge = 100 + (side == .left ? -distance : distance)
                let shift = edge - (side == .left ? 0 : BezelGeometry.size.width)
                var transform = CGAffineTransform(translationX: shift, y: 0)
                let target = BezelShape(path: attached.path.copy(using: &transform)!,
                    symbolCenter: attached.symbolCenter.applying(transform))
                for step in 0...24 {
                    let t = Double(step) / 24
                    let shape = BezelDragShape.morph(source, into: target, amount: t)
                    let bounds = shape.path.boundingBoxOfPath
                    let expectedWidth = source.path.boundingBoxOfPath.width * (1 - t) + target.path.boundingBoxOfPath.width * t
                    guard abs((side == .left ? bounds.minX : bounds.maxX) - edge) < 0.01,
                          abs(bounds.width - expectedWidth) < 0.01,
                          shape.path.contains(shape.symbolCenter) else { throw failure("Docking contour twisted, collapsed or detached from its edge") }
                }
                guard BezelDragShape.morph(source, into: target, amount: 0).path == source.path,
                      BezelDragShape.morph(source, into: target, amount: 1).path == target.path else { throw failure("Docking endpoints changed") }
            }
        }
        print("PASS: 150 generated docking contours retain edge contact, continuous width and enclosed symbols with exact endpoints.")
    }

    private static func verifyDragRendering() throws {
        for side in BezelSide.allCases {
            for distance in [32.0, 55, 78, 93] {
                let shape = BezelDragShape.make(velocity: .zero, side: side, distance: distance)
                let edge = 100 + (side == .left ? -distance : distance)
                let box = shape.path.boundingBoxOfPath
                guard abs((side == .left ? box.minX : box.maxX) - edge) < 0.001,
                      shape.path.contains(shape.symbolCenter) else { throw failure("Drag neck lost flush edge contact") }
                if distance == 55 {
                    let x = edge + (side == .left ? 1 : -1) * 12
                    guard shape.path.contains(CGPoint(x: x, y: 190)),
                          !shape.path.contains(CGPoint(x: x, y: 210)) else { throw failure("Drag connector lacks a narrow waist") }
                }
            }
        }
        func draw(_ velocity: CGVector, reduced: Bool = false) throws -> NSBitmapImageRep {
            let size = BezelGeometry.size
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width) * 4, bitsPerPixel: 32)!
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
            let view = BezelIndicatorView(frame: CGRect(origin: .zero, size: size))
            view.previewShape = BezelDragShape.make(velocity: .zero)
            view.dragVelocity = velocity
            view.update(form: .shown, symbol: .checkmark, level: 0, spectrum: Array(repeating: 0, count: 7), time: 0, reducedMotion: reduced)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.translateBy(x: 0, y: size.height)
            graphics.cgContext.scaleBy(x: 1, y: -1)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }
        let still = try draw(.zero), moving = try draw(CGVector(dx: 1000, dy: 0))
        let reduced = try draw(CGVector(dx: 1000, dy: 0), reduced: true)
        var spread = 0.0
        for y in 150..<230 { for x in 55..<145 {
            let a = still.colorAt(x: x, y: y)!, b = moving.colorAt(x: x, y: y)!
            let c = reduced.colorAt(x: x, y: y)!
            guard abs(a.alphaComponent - b.alphaComponent) < 0.01,
                  abs(a.redComponent - c.redComponent) < 0.01 else { throw failure("Motion blur changed the silhouette or ignored Reduce Motion") }
            if abs(x - 100) > 12 { spread += b.redComponent - a.redComponent }
        } }
        guard spread > 3 else { throw failure("Fast drag did not spread the symbol along its motion") }
        print("PASS: flush pinched drag neck, generated content motion blur, unchanged silhouette and Reduce Motion.")
    }

    private static func verifyDrawnShadow() throws {
        for side in BezelSide.allCases {
            let size = BezelGeometry.size
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: Int(size.width * 2) * 4, bitsPerPixel: 32),
                  let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Cannot draw the isolated shadow fixture.") }
            let view = BezelIndicatorView(frame: CGRect(origin: .zero, size: size))
            view.side = side
            view.update(form: .shown, symbol: .waveform, level: 0,
                spectrum: Array(repeating: 0, count: AudioSpectrum.bandCount), time: 0, reducedMotion: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            graphics.cgContext.translateBy(x: 0, y: size.height * 2)
            graphics.cgContext.scaleBy(x: 2, y: -2)
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            let bounds = view.displayedShape.path.boundingBoxOfPath
            let front = side == .left ? bounds.maxX : bounds.minX
            let direction = side == .left ? 1.0 : -1.0
            func alpha(_ distance: Double) -> CGFloat {
                bitmap.colorAt(x: Int((front + direction * distance) * 2), y: Int(size.height))?.alphaComponent ?? -1
            }
            guard alpha(-3) == 1, alpha(1) > 0.015, alpha(1) < 0.14,
                  alpha(3) < alpha(1), alpha(8) < 0.005 else {
                throw failure("The generated bezel must draw a faint, narrow shadow: \([-3.0, 1, 3, 8].map(alpha)).")
            }
        }
        print("Generated bezel drawing: visible low-opacity shadow, soft outward falloff and no broad painted stroke PASS.")
    }

    private static func verifyBackdrop(_ controller: BezelWindowController, panel: NSPanel) throws {
        guard let root = controller.backdrop, panel.contentView === root,
              let sampler = root.layer?.sublayers?.first,
              String(describing: type(of: sampler)) == "CABackdropLayer" else { throw failure("Missing native bezel sampler.") }
        controller.updateBackdrop(reduceTransparency: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        panel.displayIfNeeded()
        CATransaction.flush()
        guard BackdropWindowHosting.isEnabled(in: panel), root.isBackdropAttached,
              panel.value(forKey: "hostsLayersInWindowServer") as? Bool == true,
              sampler.value(forKey: "windowServerAware") as? Bool == true,
              sampler.value(forKey: "allowsGroupBlending") as? Bool == false,
              sampler.value(forKey: "context") as? NSObject === panel.value(forKey: "_windowLayerContext") as? NSObject,
              !sampler.isHidden, sampler.mask == nil, sampler.opacity == 1,
              let filter = sampler.filters?.first as? NSObject,
              filter.value(forKey: "inputRadius") as? Double == 1.5,
              filter.value(forKey: "inputMaskImage") != nil,
              controller.indicator?.layer?.superlayer === root.layer,
              root.layer?.sublayers?.last === controller.indicator?.layer else {
            throw failure("Bezel native blur was not submitted with the color layer above it.")
        }
        controller.updateBackdrop(reduceTransparency: true)
        guard sampler.isHidden, root.profile == nil else { throw failure("Reduce Transparency left the bezel sampler active.") }
        controller.updateBackdrop(reduceTransparency: false)
        guard !sampler.isHidden, root.layer?.sublayers?.first === sampler else { throw failure("Restoring bezel blur replaced or lost the sampler.") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BezelProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
