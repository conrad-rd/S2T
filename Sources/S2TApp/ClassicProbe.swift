import AppKit
import S2TCore

@MainActor enum ClassicProbe {
    static func run() throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "Classic", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        guard let screen = NSScreen.screens.first else { throw NSError(domain: "Classic", code: 2) }
        let state = AppState(preview: true)
        state.glowAppearance = .liquidGlass
        state.classicAnchor = nil
        state.phase = .recording
        var data: Data?
        let store = GlassCapsulePlacementStore(read: { data }, write: { data = $0 })
        let live = GlassWaveformController(state: state, presentsWindows: false, placement: store)
        live.show(screens: [screen], pointer: screen.frame.origin)
        defer { live.hide() }
        guard let target = live.interactionPanel else { throw NSError(domain: "Classic", code: 3) }
        func dragLive(to destination: CGPoint) {
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: target.convertPoint(fromScreen: point), modifierFlags: [], timestamp: 1,
                    windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            target.interaction.mouseDown(with: event(.leftMouseDown, CGPoint(x: target.frame.midX, y: target.frame.midY)))
            target.interaction.mouseDragged(with: event(.leftMouseDragged, destination))
            target.interaction.mouseUp(with: event(.leftMouseUp, destination))
        }
        if ProcessInfo.processInfo.environment["S2T_CLASSIC_BENCHMARK"] == "1" {
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: target.convertPoint(fromScreen: point), modifierFlags: [], timestamp: 1,
                    windowNumber: target.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            target.interaction.mouseDown(with: event(.leftMouseDown, CGPoint(x: target.frame.midX, y: target.frame.midY)))
            var frames: [Double] = [], masks: [Double] = []
            let epoch = ProcessInfo.processInfo.systemUptime
            for index in 0..<60 {
                let pointer = CGPoint(x: screen.frame.minX + (index < 30 ? 8 : 8 + Double(index - 30) * 15), y: screen.frame.midY)
                let start = CACurrentMediaTime()
                target.interaction.mouseDragged(with: event(.leftMouseDragged, pointer))
                live.tick(at: epoch + Double(index) / 60)
                frames.append((CACurrentMediaTime() - start) * 1000)
                if let view = live.classicIndicator, index % 5 == 0 {
                    let start = CACurrentMediaTime()
                    _ = BezelBackdrop(path: view.shape.path).mask(size: view.bounds.size)
                    masks.append((CACurrentMediaTime() - start) * 1000)
                }
            }
            func report(_ name: String, _ values: [Double]) {
                let sorted = values.sorted()
                print("Classic benchmark \(name): median \(sorted[sorted.count / 2]) ms, p95 \(sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]) ms, max \(sorted.last!) ms")
            }
            report("desktop drag plus tick", frames)
            report("native radius map", masks)
            return
        }
        let originalPanel = live.panel
        let originalTarget = target
        func settleLive() {
            let now = ProcessInfo.processInfo.systemUptime
            for frame in 1...90 { live.tick(at: now + Double(frame) / 60) }
        }
        for side in BezelSide.allCases {
            dragLive(to: CGPoint(x: side == .left ? screen.frame.minX + 8 : screen.frame.maxX - 8, y: screen.frame.midY))
            settleLive()
            try require(live.panel === originalPanel && live.interactionPanel === originalTarget,
                "Desktop docking must keep the same display and interaction windows")
            try require(live.classicIndicator?.amount == 1, "Live docking must finish its continuous shape transition")
            let hit = CGPoint(x: target.frame.midX, y: target.frame.midY)
            target.updateHitTesting(pointer: hit)
            try require(!target.ignoresMouseEvents && target.interaction.hitTest(CGPoint(x: target.frame.width / 2, y: target.frame.height / 2)) != nil,
                "The desktop Bezel must accept the next drag through its actual hit target")
            try require(live.dockedSide == side && store.anchor?.side == side, "Live drag must attach and save either edge")
            try require(!target.button.isEnabled, "Docked hit target must not hide a cancel action")
            let restored = GlassWaveformController(state: state, presentsWindows: false,
                placement: GlassCapsulePlacementStore(read: { data }, write: { data = $0 }))
            restored.show(screens: [screen], pointer: screen.frame.origin)
            try require(restored.dockedSide == side, "Restart must restore attachment")
            restored.hide()
            dragLive(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY))
            settleLive()
            try require(live.classicIndicator?.amount == 0, "Desktop detachment must finish in floating glass")
            try require(live.dockedSide == nil && store.anchor?.side == nil, "Dragging away must restore glass and persist floating placement")
        }
        try require(live.panel?.isVisible == false && !target.isVisible, "Live verification windows must stay hidden")
        let settings = AppearanceWindowController(state: state, presentsWindows: false)
        let window = settings.prepare()
        defer { window.close() }
        settings.setModelsVisible(false)
        settings.selectPreview(.liquidGlass)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        func find(_ view: NSView) -> ClassicPreviewView? {
            if let result = view as? ClassicPreviewView { return result }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let root = window.contentView, let preview = find(root) else { throw NSError(domain: "Classic", code: 4) }
        let bar = settings.controlsPanel.frame
        func background(_ view: NSView) -> AppearancePreviewBackdropView? {
            (view as? AppearancePreviewBackdropView) ?? view.subviews.lazy.compactMap(background).first
        }
        guard let image = background(root), let contents = image.layer?.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID,
              let expected = AppearancePreviewScene.background(.bezel).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "ClassicBackground", code: 1)
        }
        let pixels = contents as! CGImage
        try require(pixels.width == expected.width && pixels.height == expected.height &&
            CFEqual(pixels.dataProvider?.data, expected.dataProvider?.data), "Classic must use the original Bezel background pixels")
        let previewScale = preview.convert(preview.bounds, to: root).width / preview.bounds.width
        let glassScale = preview.glass.convert(preview.glass.bounds, to: root).width / preview.glass.bounds.width
        let bezelScale = preview.bezel.convert(preview.bezel.bounds, to: root).width / preview.bezel.bounds.width
        try require(abs(previewScale - glassScale) < 0.001 && abs(glassScale - bezelScale) < 0.001,
            "Glass and Bezel must have the same scene scale, without extra enlargement")
        try verifyDistanceMask()
        try verifyTransition()
        func settlePreview() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.1)) }

        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: preview.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        for side in BezelSide.allCases {
            let start = preview.center
            preview.mouseDown(with: event(.leftMouseDown, start))
            let edge = CGPoint(x: side == .left ? 5 : preview.bounds.maxX - 5, y: preview.bounds.midY)
            preview.mouseDragged(with: event(.leftMouseDragged, edge))
            preview.mouseUp(with: event(.leftMouseUp, edge))
            try require(preview.side == side && state.classicAnchor?.side == side, "Mounted settings preview must attach and persist")
            settlePreview()
            try require(preview.glass.isHidden && !preview.bezel.isHidden, "Preview must display Bezel: side \(String(describing: preview.side)), amount \(preview.indicator.amount), glass hidden \(preview.glass.isHidden), bezel hidden \(preview.bezel.isHidden)")
            preview.mouseDown(with: event(.leftMouseDown, edge))
            let floating = CGPoint(x: preview.bounds.midX, y: preview.bounds.maxY - 100)
            preview.mouseDragged(with: event(.leftMouseDragged, floating))
            preview.mouseUp(with: event(.leftMouseUp, floating))
            settlePreview()
            try require(preview.side == nil && state.classicAnchor?.side == nil && !preview.glass.isHidden && preview.bezel.isHidden,
                "Mounted preview must switch back to glass")
            try require(settings.controlsPanel.frame == bar, "Clearing the original bar area must return the controls home")
        }
        guard let avoidance = settings.classicBarAvoidance, let container = settings.controlsPanel.superview else {
            throw NSError(domain: "ClassicBar", code: 1)
        }
        let home = settings.controlsPanel.frame
        let destination = preview.convert(CGPoint(x: home.midX, y: home.midY - 12), from: container)
        preview.mouseDown(with: event(.leftMouseDown, preview.center))
        preview.mouseDragged(with: event(.leftMouseDragged, destination))
        preview.mouseUp(with: event(.leftMouseUp, destination))
        let dropped = preview.center
        settlePreview()
        try require(avoidance.target.x == 0 && avoidance.target.y != 0, "Floating overlap must move the controls vertically")
        try require(preview.center == dropped, "Releasing glass over the bar must not teleport the indicator")
        let obstruction = container.convert(preview.indicator.hitPath.boundingBoxOfPath, from: preview.indicator)
        try require(!settings.controlsPanel.frame.intersects(obstruction), "Settled controls must clear the floating indicator")
        try require(abs(settings.controlsPanel.frame.minY - home.minY - avoidance.target.y) < 1,
            "Vertical avoidance must move the actual native bar in the requested direction")
        preview.mouseDown(with: event(.leftMouseDown, preview.center))
        let clear = CGPoint(x: preview.bounds.midX, y: preview.bounds.maxY - 100)
        preview.mouseDragged(with: event(.leftMouseDragged, clear))
        preview.mouseUp(with: event(.leftMouseUp, clear))
        settlePreview()
        try require(settings.controlsPanel.frame == home, "Moving glass away must restore the exact original bar position")
        settings.preview.onClassicPlacement = nil
        preview.onPlacement = nil
        for side in BezelSide.allCases {
            let obstacle = CGRect(x: side == .left ? home.minX - 20 : home.maxX - 20,
                y: home.midY - 20, width: 40, height: 40)
            avoidance.update(obstacle: obstacle, in: container, side: side)
            let target = avoidance.target
            try require(target.y == 0 && (side == .left ? target.x > 0 : target.x < 0),
                "Either attached edge must move the controls in the opposite horizontal direction")
            for _ in 0..<200 { avoidance.update(obstacle: obstacle, in: container, side: side) }
            try require(avoidance.target == target, "Repeated overlap must not accumulate displacement")
            settlePreview()
            try require(abs(settings.controlsPanel.frame.minX - home.minX - target.x) < 1,
                "The native bar must reach the horizontal avoidance position")
        }
        avoidance.update(obstacle: .zero, in: container, side: nil)
        settlePreview()
        try require(settings.controlsPanel.frame == home, "Clearing attachment must return the controls home")
        try require(AppState(preview: true).classicAnchor == state.classicAnchor, "Preview placement must survive restart")
        try require(AppearanceModeBar.modes.count == 5 && AppearanceModeBar.modes.last?.title == "Classic", "Expose exactly one Classic mode")
        avoidance.update(obstacle: CGRect(x: home.minX - 20, y: home.midY - 20, width: 40, height: 40), in: container, side: .left)
        settlePreview()
        let displaced = settings.controlsPanel.frame
        settings.selectPreview(.bottom)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require(settings.controlsPanel.frame == displaced, "Changing appearance must begin at the current panel frame")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            let intermediate = settings.controlsPanel.frame
            try require(intermediate.height > 60 && intermediate.height < 340 && intermediate.minX < displaced.minX && intermediate.minX > home.minX,
                "Appearance changes must animate position and panel expansion together")
            settings.selectPreview(.liquidGlass)
            try require(settings.controlsPanel.frame == intermediate, "Reversing an appearance transition must not snap")
            settlePreview()
            try require(settings.controlsPanel.frame.height == 60, "Reversed transition must settle to the compact Classic panel")
            settings.selectPreview(.bottom)
        }
        settlePreview()
        try require(settings.controlsPanel.frame.height == 340 && settings.controlsPanel.frame.minX == home.minX,
            "Changing away from Classic must finish at the expanded panel's home position")
        try require(!window.isVisible, "Settings verification must remain hidden")
        print("Classic passed: single mode, native preview and live drags, both edges, floating restoration, persistence, reversible controls avoidance and hidden windows. No capture.")
    }
    private static func verifyDistanceMask() throws {
        let size = NSSize(width: 440, height: 440)
        let path = CGPath(rect: CGRect(x: 180, y: 180, width: 80, height: 80), transform: nil)
        guard let image = BezelBackdrop(path: path).mask(size: size),
              let bitmap = image.representations.first as? NSBitmapImageRep else { throw NSError(domain: "ClassicMask", code: 1) }
        for distance in [0, 5, 30, 60, 90, 119, 130] {
            let t = max(0, 1 - Double(distance) / 120)
            let expected = t * t * t * (t * (t * 6 - 15) + 10)
            for point in [CGPoint(x: 260 + distance, y: 220), CGPoint(x: 179 - distance, y: 220),
                          CGPoint(x: 220, y: 260 + distance), CGPoint(x: 220, y: 179 - distance)] {
                let alpha = bitmap.colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? -1
                guard abs(alpha - expected) < 0.025 else {
                    throw NSError(domain: "ClassicMask", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Distance falloff at \(point): \(alpha), expected \(expected)"])
                }
            }
        }
        guard bitmap.colorAt(x: 220, y: 220)?.alphaComponent == 1,
              bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0 else { throw NSError(domain: "ClassicMask", code: 3) }
    }
    private static func verifyTransition() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "ClassicTransition", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        for side in BezelSide.allCases {
            let view = ClassicIndicatorView()
            let screen = CGRect(x: 0, y: 0, width: 200, height: 380)
            let center = CGPoint(x: side == .left ? 66 : 134, y: 190)
            func frame(_ time: Double, _ attached: Bool, _ reduced: Bool = false) {
                view.update(center: center, screen: screen, side: attached ? side : nil, symbol: .waveform,
                    spectrum: Array(repeating: 0, count: 7), level: 0, time: time,
                    reducedMotion: reduced, reducedTransparency: false, gradient: .init())
            }
            frame(0, false)
            frame(1, false)
            try require(abs(view.shape.path.boundingBoxOfPath.width - 112) < 0.01, "Floating glass must retain its native 112-point width")
            var previous = view.shape.path.boundingBoxOfPath
            for index in 1...120 {
                frame(1 + Double(index) / 60, index <= 60)
                let rect = view.shape.path.boundingBoxOfPath
                try require(abs(rect.width - previous.width) < 8 && abs(rect.height - previous.height) < 8 &&
                    abs(rect.midX - previous.midX) < 8, "Docking jumped at frame \(index): \(previous) to \(rect), amount \(view.amount)")
                try require(view.shape.path.contains(view.shape.symbolCenter), "Symbols must stay inside the moving contour")
                if index == 8 || index == 68 {
                    try require(view.amount > 0 && view.amount < 1 && !view.glass.isHidden,
                        "The glass must carry an intermediate contour, rather than swap endpoint views")
                }
                if index == 60 {
                    try require(view.amount == 1 && abs((side == .left ? rect.minX : rect.maxX) - (side == .left ? 0 : 200)) < 0.01,
                        "Attached shape must finish flush against either edge")
                }
                previous = rect
            }
            try require(view.amount == 0, "Detachment must settle back to glass")
            frame(4, true, true)
            try require(view.amount == 1, "Reduce Motion must resolve docking without animation")
            frame(5, false, true)
            for index in 1...20 {
                view.update(center: CGPoint(x: center.x + Double(index) * 8, y: center.y),
                    screen: screen, side: nil, symbol: .waveform, spectrum: Array(repeating: 0, count: 7), level: 0,
                    time: 5 + Double(index) / 60, reducedMotion: false,
                    reducedTransparency: false, gradient: .init())
            }
            try require(view.shape.path.boundingBoxOfPath.width > 114,
                "Dragging must gently stretch the actual shared contour")
            try require(view.shape.path.contains(view.shape.symbolCenter),
                "Drag deformation must retain the content inside the contour")
            for index in 21...110 {
                view.update(center: CGPoint(x: center.x + 160, y: center.y),
                    screen: screen, side: nil, symbol: .waveform, spectrum: Array(repeating: 0, count: 7), level: 0,
                    time: 5 + Double(index) / 60, reducedMotion: false,
                    reducedTransparency: false, gradient: .init())
            }
            try require(abs(view.shape.path.boundingBoxOfPath.width - 112) < 0.02,
                "Released glass must recover its original proportions")
        }
    }

}
