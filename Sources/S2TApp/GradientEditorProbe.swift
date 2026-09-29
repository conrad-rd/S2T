import AppKit
import SwiftUI
import S2TCore

@MainActor enum GradientEditorProbe {
    static func run() throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        state.glowTuning.gradients = [:]
        let controls = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controls.prepare()
        defer { window.close() }
        let editor = controls.gradientEditor
        guard editor.addButton.title == "Add point", editor.removeButton.title == "Remove point" else {
            throw failure("Point actions must have visible text labels")
        }
        if #available(macOS 26, *) {
            let buttons: [NSButton] = [editor.addButton, editor.removeButton, editor.evenButton, editor.resetButton]
            for button in buttons {
                guard button.bezelStyle == .glass, button.borderShape == .capsule,
                      button.controlSize == .regular else {
                    throw failure("All gradient actions must use the same native glass button style and size")
                }
            }
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard !editor.presentsColorPanel,
              !descendants(editor).contains(where: { $0 is NSSwitch || $0 is NSColorWell || $0 is NSSlider || ($0 as? NSTextField)?.isEditable == true }) else {
            throw failure("Gradient editing must be direct, without a switch or a separate editing list")
        }
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput, .withinInput] {
            state.glowAppearance = mode
            controls.selectPreview(mode)
            controls.refresh()
            guard editor.gradient.isDefault, editor.track.handles.count == 4, editor.selectedID == nil,
                  editor.track.handles.allSatisfy({ $0.isEnabled && $0.focusRingType == .none }), !editor.resetButton.isEnabled else {
                throw failure("The app's default gradient must be editable immediately")
            }
            for section in AppearanceSection.allCases {
                controls.selectSection(section)
                guard editor.isHidden == (section != .gradient), editor.isDescendant(of: controls.controlsScroll.documentView!) else {
                    throw failure("Gradient editor must appear only in the Gradient tab")
                }
            }
            window.contentView?.layoutSubtreeIfNeeded()
            editor.scrollToVisible(editor.bounds)
            window.contentView?.layoutSubtreeIfNeeded()
            let actions = [editor.removeButton, editor.addButton, editor.evenButton, editor.resetButton]
            guard let row = editor.removeButton.superview as? NSStackView,
                  editor.arrangedSubviews.last === row,
                  actions.allSatisfy({ $0.superview === row && row.bounds.contains($0.frame) }),
                  actions.allSatisfy({ abs($0.frame.midY - editor.removeButton.frame.midY) < 1 }) else {
                throw failure("All gradient actions must fit in one row below the track")
            }
            guard actions.allSatisfy({ abs($0.frame.height - editor.evenButton.frame.height) < 1 &&
                $0.frame.width >= $0.intrinsicContentSize.width - 1 && $0.cell?.wraps == false }) else {
                throw failure("Gradient action labels must fit without wrapping and all capsules must have equal height: \(actions.map { "\($0.title): frame=\($0.frame), intrinsic=\($0.intrinsicContentSize), wraps=\($0.cell?.wraps ?? true)" })")
            }
            guard editor.bounds.width > 350, editor.track.lineRect.height == 4,
                  editor.track.handles.allSatisfy({ $0.bounds.size == CGSize(width: 32, height: 32) }),
                  editor.track.tickPositions.count == 21, !window.isVisible else {
                throw failure("Gradient editor controls are clipped or a verification window was opened")
            }
            try verifyTrack(editor, window: window, mode: mode)
            guard AppState(preview: true).glowTuning.gradients[mode.rawValue] == editor.gradient else { throw failure("Direct edits did not persist") }
            let neighbors = state.glowTuning.gradients.filter { $0.key != mode.rawValue }
            let tuning = state.glowTuning
            editor.resetButton.performClick(nil)
            guard editor.gradient.isDefault, state.glowTuning.gradients[mode.rawValue]?.isDefault == true,
                  AppState(preview: true).glowTuning.gradients[mode.rawValue]?.isDefault == true,
                  state.glowTuning.gradients.filter({ $0.key != mode.rawValue }) == neighbors,
                  state.glowTuning.gradientSpeed == tuning.gradientSpeed,
                  state.glowTuning.backgroundBlur == tuning.backgroundBlur else {
                throw failure("Reset must restore only this appearance's gradient")
            }
            print("PASS: \(mode) always-editable defaults, single-click color selection, free dragging, direct add/remove, persistence and Reset.")
        }
        state.glowAppearance = .bezel
        controls.selectPreview(.bezel)
        controls.refresh()
        guard editor.isHidden, editor.colorEditingID == nil,
              state.glowTuning.gradients[GlowAppearance.bezel.rawValue] == nil else { throw failure("Bezel must not offer a gradient editor") }
        try verifyRendering()
        try verifySelectionGlow()
    }

    private static func verifyTrack(_ editor: GradientEditor, window: NSWindow, mode: GlowAppearance) throws {
        let track = editor.track
        let handle = track.handles[1]
        let id = handle.stopID
        func event(_ type: NSEvent.EventType, at position: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: track.convert(track.point(at: position), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
        }
        handle.mouseDown(with: event(.leftMouseDown, at: 0.25))
        handle.mouseUp(with: event(.leftMouseUp, at: 0.25))
        guard editor.colorEditingID == id, editor.selectedID == id else { throw failure("A single click must request the native color picker") }
        guard !handle.selectionGlow.layer.isHidden, handle.selectionGlow.layer.superlayer === handle.layer else {
            throw failure("Selected points must mount their glow")
        }
        try verifyHandleFill(handle, expected: handle.color)
        try verifyHandleFill(track.handles[0], expected: .controlBackgroundColor)
        editor.applyColor(NSColor(srgbRed: 0.1, green: 0.9, blue: 0.2, alpha: 1))
        let picked = editor.gradient.stops.first { $0.id == id }!.color
        try verifyHandleFill(handle, expected: handle.color)
        guard abs(picked.y - 0.9) < 0.0001 else { throw failure("The picker did not update the clicked color") }
        editor.endColorEditing()
        guard editor.selectedID == nil, !editor.removeButton.isEnabled,
              track.handles.allSatisfy({ $0.state == .off && $0.selectionGlow.layer.isHidden && $0.selectionGlow.shimmer.animationKeys()?.isEmpty != false }) else {
            throw failure("Ending color editing must clear selection")
        }
        editor.selectStop(id)
        for button in [editor.addButton, editor.removeButton] {
            let click = NSEvent.mouseEvent(with: .leftMouseDown,
                location: button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)!
            editor.handleMouseDown(click, in: window)
            guard editor.selectedID == id else { throw failure("Point action clicks must retain their target") }
        }
        let blank = NSEvent.mouseEvent(with: .leftMouseDown,
            location: track.convert(CGPoint(x: track.bounds.midX, y: 5), to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        editor.handleMouseDown(blank, in: window)
        editor.refresh(editor.gradient, mode: mode)
        guard editor.selectedID == nil, track.handles.allSatisfy({ $0.state == .off }) else {
            throw failure("Clicking away must clear selection and refresh must preserve it")
        }
        try verifyHandleFill(handle, expected: .controlBackgroundColor)
        let unselectedGradient = editor.gradient
        editor.addButton.performClick(nil)
        guard editor.selectedID != nil, editor.gradient.stops.count == unselectedGradient.stops.count + 1 else {
            throw failure("Add point must work without a selection")
        }
        editor.removeButton.performClick(nil)
        guard editor.gradient == unselectedGradient else { throw failure("Remove must delete the newly selected point") }
        editor.endColorEditing()
        handle.mouseDown(with: event(.leftMouseDown, at: 0.25))
        handle.mouseDragged(with: event(.leftMouseDragged, at: 0.9))
        handle.mouseUp(with: event(.leftMouseUp, at: 0.9))
        guard editor.gradient.stops.last?.id == id, editor.gradient.stops.last?.color == picked,
              abs(editor.gradient.stops.last!.position - 0.9) < 0.0001,
              track.handles.last === handle, editor.colorEditingID == nil else {
            throw failure("Dragging must pass other colors without changing identity or opening the picker")
        }
        handle.keyDown(with: key(124))
        guard abs(editor.gradient.stops.last!.position - 0.91) < 0.0001,
              handle.accessibilityPerformDecrement(), abs(editor.gradient.stops.last!.position - 0.9) < 0.0001 else {
            throw failure("Keyboard and accessibility position changes failed")
        }
        let before = editor.gradient
        handle.mouseDown(with: event(.leftMouseDown, at: 0.9))
        handle.mouseDragged(with: event(.leftMouseDragged, at: 0.1))
        handle.keyDown(with: key(53))
        handle.mouseUp(with: event(.leftMouseUp, at: 0.1))
        guard editor.gradient == before, handle.dragStart == nil, editor.colorEditingID == nil else { throw failure("Escape did not undo a drag across other stops") }
        handle.mouseDown(with: event(.leftMouseDown, at: 0.9))
        handle.mouseUp(with: event(.leftMouseUp, at: 1))
        guard editor.gradient.stops.last?.position == 1 else { throw failure("The right endpoint must be reachable") }
        window.contentView?.layoutSubtreeIfNeeded()
        track.mouseDown(with: event(.leftMouseDown, at: 0.625))
        guard editor.gradient.stops.count == 5,
              editor.gradient.stops.first(where: { $0.id == editor.selectedID })?.position == 0.625,
              editor.colorEditingID == editor.selectedID else { throw failure("Clicking the line must add an editable color there") }
        let added = track.handles.first { $0.stopID == editor.selectedID }!
        added.keyDown(with: key(51))
        guard editor.gradient.stops.count == 4, editor.gradient.index(of: added.stopID) == nil else { throw failure("Delete must remove the selected color") }
        editor.selectStop(editor.gradient.stops[1].id)
        editor.addButton.performClick(nil)
        guard let insertedID = editor.selectedID else { throw failure("Adding must select the new point") }
        guard editor.gradient.stops.first(where: { $0.id == insertedID })?.position == 0.625 else {
            throw failure("Add point must insert beside the selected point")
        }
        editor.selectStop(id)
        editor.removeButton.performClick(nil)
        guard editor.gradient.index(of: id) == nil, editor.gradient.index(of: insertedID) != nil else {
            throw failure("Remove point must target the selection, not the last added point")
        }
        for _ in 0..<8 { editor.addButton.performClick(nil) }
        guard editor.gradient.stops.count == 12 else { throw failure("The eight-color limit must be removed") }
        editor.evenButton.performClick(nil)
        guard editor.gradient.stops.map(\.position) == (0..<12).map({ Double($0) / 12 }) else { throw failure("Space evenly failed") }
        while editor.gradient.stops.count > 1 { editor.removeButton.performClick(nil) }
        guard !editor.removeButton.isEnabled, editor.track.handles.count == 1 else { throw failure("A single solid color must be supported") }
    }

    private static func verifyHandleFill(_ handle: GradientStopHandle, expected: NSColor) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Missing handle fixture") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        handle.draw(handle.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let actual = bitmap.colorAt(x: 16, y: 16)?.usingColorSpace(.sRGB),
              let expected = expected.usingColorSpace(.sRGB),
              abs(actual.redComponent - expected.redComponent) < 0.02,
              abs(actual.greenComponent - expected.greenComponent) < 0.02,
              abs(actual.blueComponent - expected.blueComponent) < 0.02 else {
            throw failure("Selected points must fill with their color; unselected points must stay hollow")
        }
    }

    private static func verifySelectionGlow() throws {
        let glow = GradientStopGlow()
        let color = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.9, alpha: 1)
        glow.layout(in: CGRect(x: 0, y: 0, width: 32, height: 32), scale: 2)
        glow.update(color: color, selected: true, reducedMotion: false, visible: true)
        guard let sweep = glow.shimmer.animation(forKey: "sweep") as? CAKeyframeAnimation,
              sweep.duration >= 4, sweep.repeatCount == .infinity, !glow.layer.isHidden else {
            throw failure("Selected points must have a slow native shimmer")
        }
        glow.update(color: color, selected: true, reducedMotion: true, visible: true)
        guard glow.shimmer.animationKeys()?.isEmpty != false, !glow.layer.isHidden else {
            throw failure("Reduce Motion must retain the glow without animation")
        }
        let fixture = CALayer()
        fixture.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        fixture.addSublayer(glow.layer)
        glow.layer.position = CGPoint(x: 32, y: 32)
        func render() throws -> NSBitmapImageRep {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Missing glow fixture") }
            fixture.render(in: context.cgContext)
            return bitmap
        }
        let selected = try render()
        guard let bloom = selected.colorAt(x: 44, y: 32)?.usingColorSpace(.sRGB),
              bloom.alphaComponent > 0.01, bloom.redComponent > bloom.greenComponent,
              (selected.colorAt(x: 62, y: 32)?.alphaComponent ?? 1) < 0.01 else {
            throw failure("Selected glow must be colored, softly blurred and bounded")
        }
        let start = selected.tiffRepresentation
        glow.shimmer.position.x = 24
        guard try render().tiffRepresentation != start else { throw failure("Shimmer must change the generated point highlight") }
        glow.update(color: color, selected: true, reducedMotion: false, visible: false)
        guard glow.shimmer.animationKeys()?.isEmpty != false else { throw failure("Hidden glow must not animate") }
        glow.update(color: color, selected: false, reducedMotion: false, visible: true)
        guard glow.layer.isHidden, glow.shimmer.animationKeys()?.isEmpty != false,
              (try render().colorAt(x: 44, y: 32)?.alphaComponent ?? 1) == 0 else {
            throw failure("Deselecting must remove the glow and shimmer")
        }
        print("PASS: generated colored selection bloom, slow native shimmer, Reduce Motion and hidden/deselected cleanup.")
    }

    private static func verifyRendering() throws {
        let layout = TopGlowLayout(display: GlowDisplay(frame: CGRect(x: 0, y: 0, width: 300, height: 500)), paddingScale: 0.25)
        let geometries: [ChromaAppearance.Geometry] = [.bottom, .input(CGRect(x: 50, y: 70, width: 200, height: 60), 30), .notch(layout)]
        for geometry in geometries {
            let size = geometry.appearance == .aroundNotch ? layout.frame.size : CGSize(width: 300, height: 200)
            let request = ChromaFrameRequest(geometry: geometry, size: size,
                profile: GlowProfile(energy: 0.55, heights: [3]), brightness: 1, backdrop: false)
            guard let frame = ChromaFrame.render(request) else { throw failure("Missing custom gradient fixture") }
            func pixels(_ rgb: SIMD3<Double>?, time: Double? = nil, reset: Bool = false) throws -> [UInt8] {
                var profile = request.profile
                if let rgb {
                    profile.response.tuning.gradients[geometry.appearance.rawValue] = GlowGradient(stops: [
                        .init(position: 0, color: rgb), .init(position: 0.5, color: rgb)
                    ])
                }
                if reset { profile.response.tuning.gradients[geometry.appearance.rawValue] = .init() }
                let renderFrame = ChromaFrame(request: .init(geometry: geometry, size: size, profile: profile, brightness: 1, backdrop: false), images: frame.images, radiusMap: nil)
                let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: renderFrame, cycleTime: time).frame(width: size.width, height: size.height))
                renderer.scale = 1
                guard let image = renderer.cgImage else { throw failure("Missing custom Canvas render") }
                var bytes = [UInt8](repeating: 0, count: Int(size.width * size.height) * 4)
                try bytes.withUnsafeMutableBytes { buffer in
                    guard let context = CGContext(data: buffer.baseAddress, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                        bytesPerRow: Int(size.width) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Missing bitmap context") }
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                }
                return bytes
            }
            let red = try pixels(SIMD3(1, 0, 0)), green = try pixels(SIMD3(0, 1, 0))
            let original = try pixels(nil), moving = try pixels(SIMD3(1, 0, 0), time: 2)
            func delta(_ first: [UInt8], _ second: [UInt8]) -> Int {
                zip(first, second).map { abs(Int($0) - Int($1)) }.max() ?? 0
            }
            let resetStill = try pixels(nil, reset: true)
            let resetMoving = try pixels(nil, time: 2, reset: true)
            let defaultMoving = try pixels(nil, time: 2)
            let staticDifference = delta(resetStill, original)
            let movingDifference = delta(resetMoving, defaultMoving)
            guard staticDifference <= 1, movingDifference <= 1 else {
                let control = delta(try pixels(nil), original)
                throw failure("Reset rendering \(geometry.appearance): static difference \(staticDifference), moving difference \(movingDifference), repeated-original difference \(control)")
            }
            var visible = 0
            for i in stride(from: 0, to: red.count, by: 4) {
                // Use the same one-level 8-bit rounding allowance for every reference comparison.
                guard [red[i + 3], green[i + 3], moving[i + 3]].allSatisfy({
                    abs(Int($0) - Int(original[i + 3])) <= 1
                }) else {
                    throw failure("Custom gradient changed \(geometry.appearance) alpha at pixel \(i / 4): original \(original[i + 3]), red \(red[i + 3]), green \(green[i + 3]), moving \(moving[i + 3])")
                }
                if red[i + 3] > 20 {
                    visible += 1
                    guard red[i] > red[i + 1], green[i + 1] > green[i] else { throw failure("Custom color did not reach actual renderer") }
                }
            }
            guard visible > 10 else { throw failure("Empty custom gradient fixture") }
            print("PASS: \(geometry.appearance) custom colors reach static and animated Canvas rendering with unchanged opacity.")
        }
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "GradientEditorProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
