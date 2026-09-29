import AppKit
import SwiftUI
import S2TCore

@MainActor enum AppearanceWindowProbe {
    static func verifyModeControls(state: AppState, menu: MenuBarController) throws {
        guard AppearancePreviewScene.inputGreeting(fullName: "Alex Example", accountName: "alex") == "How can I help you, Alex?",
              AppearancePreviewScene.inputGreeting(fullName: "  ", accountName: "sam") == "How can I help you, sam?",
              AppearancePreviewScene.inputGreeting(fullName: "", accountName: "") == "How can I help you?" else {
            throw failure("ChatGPT greeting does not use the Mac user's name")
        }
        let saved = state.glowAppearance
        defer { state.glowAppearance = saved; menu.appearanceWindow.window?.close() }
        guard let entry = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance" }),
              entry.submenu == nil, entry is ActionMenuItem, entry.action != nil,
              entry.attributedTitle?.string.contains("Settings…") == true, entry.keyEquivalent == "," else { throw failure("Appearance must be a native window action") }
        let savedAnchor = state.classicAnchor
        state.classicAnchor = GlassCapsuleAnchor(center: CGPoint(x: 400, y: 650),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 720), displayID: "layout-fixture")
        defer { state.classicAnchor = savedAnchor }
        let controls = menu.appearanceWindow
        let window = controls.prepare()
        controls.setModelsVisible(false)
        guard window.contentView?.bounds.size == NSSize(width: 780, height: 720),
              window.contentMinSize == NSSize(width: 780, height: 720),
              window.styleMask.contains(.resizable), window.collectionBehavior.contains(.fullScreenNone) else {
            throw failure("Settings must retain its initial preview dimensions and support native resizing")
        }
        controls.selectSection(.edge)
        defer { controls.selectSection(.glow) }
        guard controls.splitController.splitViewItems.first?.behavior == .default,
              controls.sidebar.table.style == .plain,
              controls.sidebar.table.selectionHighlightStyle == .none,
              controls.sidebar.table.numberOfRows == 7,
              !controls.sidebar.tableView(controls.sidebar.table, isGroupRow: 2),
              controls.sidebar.tableView(controls.sidebar.table, shouldSelectRow: 2) else { throw failure("Inset sidebar lost its native table behavior or full-width titlebar container") }
        window.contentView?.layoutSubtreeIfNeeded()
        guard let settingsWindow = window as? SettingsEditorWindow else { throw failure("Missing settings window") }
        for _ in 0..<3 {
            settingsWindow.update()
            window.contentView?.layoutSubtreeIfNeeded()
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            let frames = buttons.map { $0.convert($0.bounds, to: nil) }
            let group = frames.reduce(NSRect.null) { $0.union($1) }
            guard buttons.count == 3, !group.isEmpty,
                  buttons.allSatisfy({ $0.superview!.bounds.contains($0.frame) }),
                  frames[0].maxX < frames[1].minX, frames[1].maxX < frames[2].minX else {
                throw failure("Native traffic-light targets overlap or clip")
            }
        }
        let logo = controls.sidebar.logo
        let logoFrame = logo.convert(logo.bounds, to: controls.sidebar.view)
        let navigationFrame = controls.sidebar.table.enclosingScrollView!.convert(controls.sidebar.table.enclosingScrollView!.bounds, to: controls.sidebar.view)
        guard logo.image != nil, logo.bounds.width > 0, logo.bounds.height > 0,
              controls.sidebar.view.bounds.contains(logoFrame), !logoFrame.intersects(navigationFrame),
              controls.sidebar.view.bounds.width == AppearanceSidebarController.containerWidth else { throw failure("The compact sidebar logo or navigation is clipped") }
        let theme = state.menuAppearance, phase = state.phase
        for mode in GlowAppearance.selectableCases {
            let index = controls.sidebar.appearanceRow
            controls.selectPreview(mode)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.9))
            guard controls.sidebar.backgroundMode == mode, controls.sidebar.backdrop.wallpaperLayer.contents != nil,
                  controls.sidebar.table.backgroundColor == .clear,
                  controls.preview.mode == mode, state.glowAppearance == saved,
                  controls.sidebar.table.selectedRow == index, state.menuAppearance == theme,
                  state.phase == phase, !window.isVisible else { throw failure("Mode selection changed theme, dictation, or window visibility") }
            controls.selectSection(.speech)
            guard let content = window.contentView else { throw failure("No Appearance content") }
            content.layoutSubtreeIfNeeded()
            func findPreview(_ view: NSView) -> NSView? {
                if view.identifier?.rawValue == "appearance.preview" { return view }
                return view.subviews.lazy.compactMap { findPreview($0) }.first
            }
            guard let host = findPreview(content) else { throw failure("Missing mounted preview") }
            let previewFrame = host.convert(host.bounds, to: content)
            let backdrop = controls.sidebar.backdrop
            backdrop.layoutSubtreeIfNeeded()
            let viewport = backdrop.convert(host.bounds, from: host)
            let wallpaper = backdrop.wallpaperLayer
            let placement = AppearancePreviewScene.placement(for: mode, viewport: viewport.size,
                topInset: AppearancePreviewScene.topInset(of: host))
            guard wallpaper.frame.minX <= backdrop.bounds.minX,
                  wallpaper.frame.intersects(backdrop.bounds),
                  abs(wallpaper.frame.maxY - (viewport.maxY - placement.origin.y)) < 0.5,
                  wallpaper.frame.width > viewport.width,
                  wallpaper.contentsRect == CGRect(x: 0, y: 0, width: 1, height: 1),
                  abs(viewport.maxY - backdrop.bounds.maxY) < 0.5,
                  wallpaper.affineTransform().isIdentity,
                  controls.splitController.splitView.dividerThickness == 0 else {
                throw failure("Appearance wallpaper must continue through the full sidebar margin: mode \(mode), image \(wallpaper.frame), sidebar \(backdrop.bounds), preview \(viewport)")
            }
            guard let detail = host.superview,
                  abs(host.frame.width - detail.bounds.width) < 0.5,
                  previewFrame.width >= 540, abs(previewFrame.height - detail.bounds.height) < 0.5,
                  !detail.subviews.contains(where: { $0.identifier?.rawValue == "settings.theme" }),
                  detail.subviews.filter({ !$0.isHidden }).allSatisfy({ $0 === host || $0 === controls.controlsPanel || $0 === controls.modeBar }) else {
                throw failure("The preview must fill the entire appearance pane without headings or theme controls")
            }
            let fixed = mode == .bezel || mode == .liquidGlass
            guard !controls.controlsPanel.isHidden, controls.adjustments.isHidden == fixed,
                  controls.sectionBar.isHidden == fixed else {
                throw failure("Fixed styles must hide glow sections from the preview header")
            }
            let panel = controls.controlsPanel!
            let panelFrame = panel.convert(panel.bounds, to: content)
            guard previewFrame.contains(panelFrame), content.bounds.contains(panelFrame),
                  panelFrame.size == NSSize(width: 500, height: fixed ? 60 : 340),
                  abs(panelFrame.midX - previewFrame.midX) < 0.5,
                  abs(previewFrame.maxY - panelFrame.maxY - 356) < 0.5,
                  controls.controlsScroll.isDescendant(of: panel),
                  controls.sectionBar.isDescendant(of: panel) else {
                throw failure("The controls must settle below the unobstructed preview subject: mode \(mode), panel \(panelFrame), preview \(previewFrame)")
            }
            let bar = controls.sectionBar
            let barFrame = bar.convert(bar.bounds, to: content)
            guard bar.isHidden == fixed,
                  fixed || (panelFrame.contains(barFrame) && abs(bar.bounds.width - 195) < 0.5 && bar.bounds.height == 42 &&
                            (8...10).contains(panelFrame.maxX - barFrame.maxX)) else {
                throw failure("The four settings tabs must fit inside the glass panel: bar \(bar.bounds), frame \(barFrame), panel \(panelFrame)")
            }
            if #available(macOS 26, *) {
                guard let glass = panel as? NSGlassEffectView, glass.contentView != nil,
                      glass.style == .regular, glass.cornerRadius == 30 else { throw failure("Missing native Liquid Glass control panel") }
                guard !glass.contentView!.subviews.contains(where: { $0 is NSGlassEffectView }) else {
                    throw failure("The controls must not stack glass layers inside glass")
                }
            }
            if #available(macOS 26, *), let glass = panel as? NSGlassEffectView {
                guard let reset = controls.adjustments.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "appearance.reset" }),
                      reset.bezelStyle == .glass, reset.borderShape == .capsule, reset.tintProminence == .primary,
                      reset.bezelColor == NSColor.systemBlue, reset.action != nil,
                      reset.title == "Reset",
                      reset.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .white,
                      reset.bounds.height == 32, reset.isHidden == (mode == .bezel || mode == .liquidGlass) else {
                    throw failure("Reset must be a blue native glass capsule")
                }
            }
            if mode == .aroundNotch {
                try NotchFitProbe.verifyPreviewArtwork()
                guard AppearancePreviewScene.notchWallpaper?.size == CGSize(width: 675, height: 720) else {
                    throw failure("The preview glow must align with the supplied Mac notch")
                }
            }
            for control in AppearanceControl.allCases {
                guard let slider = controls.sliders[control],
                      slider.superview?.isHidden == !control.isVisible(for: mode) else { throw failure("Control visibility differs from the mode") }
                if control.isVisible(for: mode) {
                    guard slider.superview?.subviews.contains(where: { ($0 as? NSImageView)?.image != nil }) == true else { throw failure("A setting row is missing its icon") }
                    controls.reveal(control)
                    let frame = slider.convert(slider.bounds, to: content)
                    guard frame.width >= 120, content.bounds.insetBy(dx: -1, dy: -1).contains(frame) else {
                        throw failure("\(control.title) is compressed or clipped: \(frame), content \(content.bounds)")
                    }
                    guard host.convert(host.bounds, to: content) == previewFrame else { throw failure("The preview scrolled away with the settings") }
                }
            }
        }
        print("PASS: native split-view sidebar, independent preview selections, mounted preview at full width, fitting controls and isolated dictation phase.")
    }

    private static func verifyChatGPTCornerAlignment() throws {
        guard let image = AppearancePreviewScene.inputWallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              case let .withinInput(contour) = AppearancePreviewScene.geometry(.withinInput) else {
            throw failure("Missing ChatGPT corner fixture")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let field = WithinInputField(contour: contour)
        let scale = 1120.0 / 969
        var maximumError = 0.0
        for x in Array(213...255) + Array(865...906) {
            let sceneX = (Double(x) + 0.5) / scale + AppearancePreviewScene.inputPadding
            let expected = field.lowerEdge(at: sceneX) * scale
            let filledRows = (396...470).filter { y in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return color.redComponent > 0.16
            }
            guard let last = filledRows.last else { throw failure("Missing ChatGPT composer corner") }
            maximumError = max(maximumError, abs(Double(last + 1) - expected))
        }
        guard maximumError < 1.5 else {
            throw failure("ChatGPT glow and composer corners differ by \(maximumError) source pixels")
        }
        print("PASS: both ChatGPT lower corners match the live Within Input boundary within \(maximumError) source pixels.")
    }

    private static func verifyCancelledReplacement() async throws {
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let request = ChromaFrameRequest(geometry: .bottom, size: CGSize(width: 20, height: 20),
            profile: GlowProfile(energy: 0, heights: []), brightness: 0, backdrop: false)
        let renderer = ChromaFrameRenderer { request in
            started.signal()
            release.wait()
            return ChromaFrame(request: request, images: [], radiusMap: nil)
        }
        renderer.submit(request)
        let didStart = await Task.detached { started.wait(timeout: .now() + 5) == .success }.value
        guard didStart else { release.signal(); throw failure("Preview renderer did not start") }
        renderer.cancel()
        renderer.submit(request)
        release.signal()
        release.signal()
        let finishDeadline = CACurrentMediaTime() + 5
        while renderer.frame == nil && CACurrentMediaTime() < finishDeadline { try await Task.sleep(nanoseconds: 1_000_000) }
        guard renderer.frame?.request == request else { throw failure("Cancelled preview lost an identical replacement request") }
        renderer.cancel()
        print("PASS: cancelled preview restarts an identical in-flight request.")
    }

    static func run() async throws {
        try await verifyCancelledReplacement()
        try verifyChatGPTCornerAlignment()
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let state = AppState(preview: true)
        state.bezelVerticalPosition = 0.15
        let menu = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem); menu.appearanceWindow.window?.close() }
        menu.menuNeedsUpdate(menu.menu)
        try verifyModeControls(state: state, menu: menu)
        try AppearanceSelectionProbe.verify(state: state, menu: menu)
        guard let action = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance" }) as? ActionMenuItem else { throw failure("Missing Appearance action") }
        action.invoke()
        let controls = menu.appearanceWindow
        guard controls.preview.running, let window = controls.window, !window.isVisible else { throw failure("Appearance action did not prepare its local preview") }
        try await verifyPreviewProportions()
        try verifySpeechPreviewIsolation(controls)
        controls.selectPreview(.bottom)
        for control in AppearanceControl.allCases {
            guard let slider = controls.sliders[control] else { throw failure("Missing slider") }
            let value = control.range.lowerBound + (control.range.upperBound - control.range.lowerBound) * 0.7
            slider.doubleValue = value
            slider.sendAction(slider.action, to: slider.target)
            guard abs(control.value(in: state) - value) < 0.000001,
                  abs(control.value(in: AppState(preview: true)) - value) < 0.000001 else { throw failure("\(control.title) did not persist") }
        }
        for (index, side) in BezelSide.allCases.enumerated() {
            controls.sidePicker.selectedSegment = index
            controls.sidePicker.sendAction(controls.sidePicker.action, to: controls.sidePicker.target)
            guard (0..<controls.sidePicker.segmentCount).filter({ controls.sidePicker.isSelected(forSegment: $0) }) == [index] else { throw failure("Placement switch lost exclusive selection") }
            guard state.bezelSide == side, AppState(preview: true).bezelSide == side else { throw failure("Bezel placement did not persist") }
        }
        controls.selectSection(.speech)
        guard let wallpaper = AppearancePreviewScene.wallpaper, wallpaper.size.width >= 1000 else { throw failure("Sequoia wallpaper is missing or only a thumbnail") }
        guard let bottomImage = AppearancePreviewScene.bottomWallpaper,
              bottomImage.size == NSSize(width: 675, height: 720),
              abs(AppearancePreviewScene.renderSize(for: .bottom).height - 289.31761729717255) < 0.01,
              AppearancePreviewScene.bottomDisplayBackground.size == AppearancePreviewScene.renderSize(for: .bottom) else {
            throw failure("Bottom preview must end at the supplied wallpaper's display edge")
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let bottomURL = Bundle.main.resourceURL?.appendingPathComponent("Appearance/Bottom_Mac.png"),
                  FileManager.default.fileExists(atPath: bottomURL.path) else { throw failure("Missing Bottom Mac background") }
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Appearance/SequoiaSunrise.png"),
                  FileManager.default.fileExists(atPath: url.path) else { throw failure("The packaged app is missing the wallpaper") }
        }
        for section in AppearanceSection.allCases {
            try pressSection(section, in: controls.sectionBar)
            guard controls.selectedSection == section, controls.sectionBar.selection.section == section else { throw failure("Settings tab did not switch") }
            for control in AppearanceControl.allCases {
                guard let slider = controls.sliders[control],
                      slider.isHiddenOrHasHiddenAncestor == (control.section != section || !control.isVisible(for: controls.preview.mode)) else {
                    throw failure("Settings tab mixes unrelated controls")
                }
            }
        }
        controls.selectSection(.glow)
        controls.preview.phase = 1
        state.glowStrength = 1.3; state.glowWidth = 1; state.glowMinimum = 0.3; state.glowMaximum = 2
        state.glowTuning = .init()
        state.menuAppearance = "light"
        for mode in GlowAppearance.selectableCases {
            controls.selectPreview(mode)
            controls.refresh()
            try await verifyMountedPreview(controls, mode: mode)
            if mode == .aroundInput {
                try verifySampleField(controls)
                controls.preview.phase = 0
                try await verifyMountedPreview(controls, mode: mode, fixtureSuffix: "-idle")
                controls.preview.phase = 1
            }
            if mode == .bezel { try await verifyBezelDrag(controls) }
            if mode == .withinInput {
                controls.preview.phase = 2
                try await verifyMountedPreview(controls, mode: mode, fixtureSuffix: "-processing")
                controls.preview.phase = 1
            }
        }
        controls.selectPreview(.aroundInput)
        state.menuAppearance = "dark"
        controls.selectSection(.edge)
        controls.reveal(.maximum)
        try await verifyMountedPreview(controls, mode: .aroundInput)
        controls.selectSection(.glow)
        state.menuAppearance = "light"
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            state.glowAppearance = mode
            controls.selectPreview(mode)
            let original = AppearancePreviewScene.request(state: state, phase: 1, time: 0, reducedMotion: true, backdrop: true)
            guard let base = ChromaFrame.render(original), let baseMap = base.radiusMap else { throw failure("Missing production preview fields") }
            try EdgeAppearanceProbe.verify(base)
            try await EdgeAppearanceProbe.verifySlider(state: state, controls: controls)
            if ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"] != nil {
                controls.selectSection(.edge)
                controls.reveal(.edgeOpacity)
                try await verifyMountedPreview(controls, mode: mode, fixtureSuffix: "-edge")
                controls.selectSection(.glow)
            }
            let color = try rendered(base)
            try AppearancePreviewRenderingProbe.verify(frame: base, mode: mode)
            for (name, tuning) in [("background blur", GlowTuning(backgroundBlur: 0)),
                ("softness", GlowTuning(softness: 8)), ("falloff", GlowTuning(falloff: 1.8)), ("edge", GlowTuning(edgeBrightness: 0))] {
                state.glowTuning = tuning
                let request = AppearancePreviewScene.request(state: state, phase: 1, time: 0, reducedMotion: true, backdrop: true)
                guard let frame = ChromaFrame.render(request), let map = frame.radiusMap else { throw failure("Missing adjusted preview") }
                let adjusted = try rendered(frame)
                let sameMap = bytes(baseMap) == bytes(map)
                let differences = zip(adjusted, color).map { abs(Int($0) - Int($1)) }
                let maximumDifference = differences.max() ?? 0
                let sameFields = zip(frame.images, base.images).allSatisfy { bytes($0) == bytes($1) }
                // The two native renderers can round their final channels differently; source fields must be exact.
                guard name == "falloff" ? !sameMap : sameMap,
                      name == "background blur" ? sameFields && maximumDifference <= 2 : maximumDifference > 2 else {
                    throw failure("\(mode.rawValue) \(name) changed the wrong field: same map \(sameMap), color bytes \(adjusted.count)/\(color.count), max difference \(differences.max() ?? -1), changed \(differences.filter { $0 > 0 }.count)")
                }
                let background = AppearancePreviewBackdropView(frame: CGRect(origin: .zero, size: AppearancePreviewScene.size))
                background.update(image: AppearancePreviewScene.background(mode), frame: frame)
                guard let filter = background.layer?.filters?.first as? NSObject,
                      abs((filter.value(forKey: "inputRadius") as? Double ?? -1) - request.geometry.maximumBlurRadius * request.profile.blurGain) < 0.000001 else { throw failure("Preview background blur differs from the live filter") }
            }
            state.glowTuning = .init()
            let busy = AppearancePreviewScene.request(state: state, phase: 2, time: 0, reducedMotion: false, backdrop: true)
            guard busy.profile.blurGain == 0, busy.brightness == 0 else { throw failure("Processing preview retains listening blur") }
            let reduced = AppearancePreviewScene.request(state: state, phase: 1, time: 0, reducedMotion: true, backdrop: false)
            guard ChromaFrame.render(reduced)?.radiusMap == nil, reduced.profile.distortion == .identity else { throw failure("Preview ignores accessibility settings") }
            print("PASS: \(mode.rawValue) preview shares live fields; independent background blur, softness, falloff and edge controls; processing and accessibility.")
        }
        controls.preview.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        let closingRenderer = controls.preview.renderer
        let closingRequest = AppearancePreviewScene.request(state: state, phase: 1, time: 0, reducedMotion: true, backdrop: true)
        closingRenderer.submit(closingRequest)
        let deadline = CACurrentMediaTime() + 10
        while closingRenderer.frame?.request != closingRequest, CACurrentMediaTime() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard closingRenderer.frame != nil else { throw failure("Live preview did not publish") }
        // A never-shown window has no AppKit close notification; deliver that lifecycle event explicitly.
        controls.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        window.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard closingRenderer.frame == nil, !controls.preview.running, state.phase == .idle,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Closing preview: framePresent=\(closingRenderer.frame != nil), running=\(controls.preview.running), phase=\(state.phase), initialPID=\(String(describing: initialPID)), finalPID=\(String(describing: NSWorkspace.shared.frontmostApplication?.processIdentifier))") }
        print("PASS: saved native controls, menu action dispatch, preview completion and close cancellation. No screen, microphone, clipboard or focused-field access.")
    }

    private static func pressSection(_ section: AppearanceSection, in bar: AppearanceSectionBar) throws {
        bar.layoutSubtreeIfNeeded()
        let picker = bar.picker
        guard picker.segmentCount == 4, (0..<picker.segmentCount).allSatisfy({ picker.image(forSegment: $0) != nil }), picker.action != nil else {
            throw failure("The glass capsule must mount four native segments")
        }
        let renderedBounds = picker.convert(picker.bounds, to: bar)
        guard abs(renderedBounds.height - 42) < 1,
              bar.bounds.insetBy(dx: -1, dy: -1).contains(renderedBounds) else {
            throw failure("Native picker must fit its restored header: \(renderedBounds)")
        }
        picker.selectedSegment = section.rawValue
        picker.sendAction(picker.action, to: picker.target)
        guard bar.selection.section == section else {
            throw failure("Native segment did not update the section selection")
        }
    }


    private static func verifySpeechPreviewIsolation(_ controls: AppearanceWindowController) throws {
        let savedMaximum = controls.state.glowMaximum
        let savedAppearance = controls.preview.mode
        defer {
            controls.state.glowMaximum = savedMaximum
            controls.selectPreview(savedAppearance)
        }
        controls.selectPreview(.bottom)
        controls.state.glowMaximum = 4.5
        for section in AppearanceSection.allCases {
            try pressSection(section, in: controls.sectionBar)
            let expectedPhase = section == .speech ? 1 : 0
            let request = AppearancePreviewScene.request(state: controls.state, mode: controls.preview.mode, phase: controls.preview.phase,
                time: 0.7, reducedMotion: false, backdrop: true)
            guard controls.preview.phase == expectedPhase,
                  controls.gradientEditor.isHidden == (section != .gradient),
                  controls.sliders[.gradientSpeed]!.isHiddenOrHasHiddenAncestor == (section != .gradient),
                  controls.state.phase == .idle else { throw failure("Settings tab did not select its automatic preview or gradient controls") }
            if section != .speech {
                guard request.profile.distortion == .identity,
                      abs(request.brightness - controls.state.glowStrength / 1.3) < 0.000001 else {
                    throw failure("Stiff tabs must use base intensity independently of speech amounts")
                }
            } else {
                guard request.profile.energy > 0.65 else { throw failure("Speech must preview speaking automatically") }
            }
        }
        guard AppearancePreviewScene.cycleTime(phase: 0, time: 9, reducedMotion: false) == 9,
              AppearancePreviewScene.cycleTime(phase: 0, time: 9, reducedMotion: true) == nil else {
            throw failure("Stiff preview must cycle the gradient unless Reduce Motion is enabled")
        }
        controls.selectSection(.glow)
        print("PASS: four settings tabs isolate gradient controls and automatically select Speaking or Stiff with gradient cycling.")
    }

    private static func verifyMountedPreview(_ controls: AppearanceWindowController, mode: GlowAppearance, fixtureSuffix: String = "") async throws {
        guard let host = controls.previewHost, let content = controls.window?.contentView else { throw failure("Missing preview host") }
        if mode == .liquidGlass {
            func glass(_ view: NSView) -> GlassWaveformView? {
                (view as? GlassWaveformView) ?? view.subviews.lazy.compactMap { glass($0) }.first
            }
            let deadline = CACurrentMediaTime() + 2
            while glass(host) == nil && CACurrentMediaTime() < deadline {
                content.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let view = glass(host), view.glass != nil else { throw failure("Mounted glass preview is absent") }
            return
        }
        func background(_ view: NSView) -> AppearancePreviewBackdropView? {
            if let backdrop = view as? AppearancePreviewBackdropView,
               (mode != .bottom && mode != .aroundNotch) || backdrop.bounds.height < AppearancePreviewScene.size(for: mode).height - 1 { return backdrop }
            return view.subviews.lazy.compactMap { background($0) }.first
        }
        let deadline = CACurrentMediaTime() + 10
        while CACurrentMediaTime() < deadline {
            content.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if let view = background(host), view.layer?.contents != nil,
               mode == .bezel || (view.displayedRequest?.geometry == AppearancePreviewScene.geometry(mode) &&
               (controls.preview.phase != 0 || view.displayedRequest?.profile.energy == 0.65)) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let view = background(host), view.bounds.width >= AppearancePreviewScene.renderSize(for: mode).width - 1, view.bounds.height >= AppearancePreviewScene.renderSize(for: mode).height - 1,
              view.layer?.contents != nil else { throw failure("Mounted preview background is absent or compressed") }
        let subject: CGRect?
        switch mode {
        case .bottom: subject = CGRect(x: 4, y: view.bounds.height - 60, width: view.bounds.width - 8, height: 60)
        case .aroundNotch: subject = AppearancePreviewScene.notch.notch.map { CGRect(x: $0.minX - 52, y: 0, width: $0.width + 104, height: 160) }
        case .aroundInput, .withinInput: subject = AppearancePreviewScene.input.offsetBy(dx: AppearancePreviewScene.inputPadding, dy: 0).insetBy(dx: -20, dy: -20)
        default: subject = nil
        }
        if var subject {
            if !view.isFlipped { subject.origin.y = view.bounds.maxY - subject.maxY }
            let displayed = view.convert(subject, to: host)
            let panel = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)
            guard host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(displayed), !displayed.intersects(panel) else {
                throw failure("The \(mode.rawValue) effect is cropped or covered by the controls: \(displayed), panel \(panel)")
            }
        }
        if mode == .aroundInput {
            guard let image = view.layer?.contents, CFGetTypeID(image as CFTypeRef) == CGImage.typeID else {
                throw failure("Missing Around Input background image")
            }
            guard let expected = AppearancePreviewScene.inputWallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  abs(AppearancePreviewScene.input.minX - 182.55) < 0.1,
                  abs(AppearancePreviewScene.input.maxX - 786.45) < 0.1,
                  abs(AppearancePreviewScene.input.maxY - 406.63) < 0.1,
                  AppearancePreviewScene.inputRadius == 40 else { throw failure("ChatGPT preview input geometry is misaligned") }
            var composerSource = AppearancePreviewScene.input.offsetBy(dx: AppearancePreviewScene.inputPadding, dy: 0)
            if !view.isFlipped { composerSource.origin.y = view.bounds.maxY - composerSource.maxY }
            let composer = view.convert(composerSource, to: host)
            guard host.bounds.contains(composer), composer.width >= 350,
                  abs(composer.midX - host.bounds.midX) < 0.5 else {
                throw failure("The enlarged ChatGPT composer must fit and stay centered above the controls: \(composer)")
            }
            try verifyInputPreviewEdges(controls.state)
            let actual = NSBitmapImageRep(cgImage: image as! CGImage)
            let reference = NSBitmapImageRep(cgImage: expected)
            guard actual.pixelsWide == 1888, actual.pixelsHigh == 1404,
                  actual.pixelsWide == reference.pixelsWide + 2 * AppearancePreviewScene.inputPaddingPixels,
                  actual.pixelsHigh == reference.pixelsHigh,
                  abs((view.layer?.contentsScale ?? 0) - 1120.0 / 969) < 0.001 else {
                throw failure("ChatGPT preview discarded the restored image resolution")
            }
            for point in [CGPoint(x: 550, y: 110), CGPoint(x: 1008, y: 337), CGPoint(x: 1018, y: 342), CGPoint(x: 550, y: 690)] {
                guard let a = actual.colorAt(x: Int(point.x) + AppearancePreviewScene.inputPaddingPixels, y: Int(point.y))?.usingColorSpace(.deviceRGB),
                      let b = reference.colorAt(x: Int(point.x), y: Int(point.y))?.usingColorSpace(.deviceRGB),
                      abs(a.redComponent - b.redComponent) < 0.03,
                      abs(a.greenComponent - b.greenComponent) < 0.03,
                      abs(a.blueComponent - b.blueComponent) < 0.03 else { throw failure("Mounted ChatGPT background differs from the supplied asset") }
            }
        }
        if mode != .bezel {
            guard view.displayedRequest?.geometry == AppearancePreviewScene.geometry(mode),
                  view.layer?.filters?.isEmpty == false else { throw failure("Mounted \(mode.rawValue) preview did not receive glow/blur, phase \(controls.preview.phase), running \(controls.preview.running), received \(String(describing: view.displayedRequest?.geometry)), filters \(view.layer?.filters?.count ?? 0)") }
        }
        // AppKit draws only our never-shown, authored view hierarchy into this bitmap.
        // This does not read a window image or any display pixels.
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw failure("Cannot draw the mounted preview") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var glowPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if mode == .withinInput && controls.preview.phase == 2 {
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    if channels.max()! - channels.min()! > 0.02 { glowPixels += 1 }
                } else if color.redComponent > color.greenComponent + 0.06,
                          color.blueComponent > color.greenComponent + 0.09 { glowPixels += 1 }
            }
        }
        guard mode == .bezel || glowPixels > 50 else { throw failure("The actual mounted preview draws no visible glow: \(mode.rawValue), \(glowPixels) samples") }
        if let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"] {
            guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw failure("Cannot draw the authored Appearance layout") }
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let suffix = (controls.state.menuAppearance == "dark" ? "-dark" : "") + fixtureSuffix
            try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("appearance-window-\(mode.rawValue)\(suffix).png"))
        }
        print("PASS: \(mode.rawValue) actual mounted preview is \(host.bounds.size), with its authored background and current render frame.")
    }

    private static func descendant<T: NSView>(_ type: T.Type, in root: NSView) -> T? {
        if let match = root as? T { return match }
        return root.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    private static func verifyInputPreviewEdges(_ state: AppState) throws {
        let request = AppearancePreviewScene.request(state: state, mode: .aroundInput, phase: 0, time: 0, reducedMotion: false, backdrop: true)
        guard case let .input(contour) = request.geometry,
              abs(contour.bounds.minX - AppearancePreviewScene.inputPadding - AppearancePreviewScene.input.minX) < 0.001,
              request.size.width > 1600 else { throw failure("Input preview has no room beyond its visible sides") }
        guard let fixture = ContourMask.render(size: request.size, draw: { context in
            context.setFillColor(CGColor(gray: 1, alpha: 0.5))
            context.fill(CGRect(origin: .zero, size: request.size))
        }), let contracted = ChromaExpansion.image(fixture, geometry: request.geometry, size: request.size, factor: 0.65),
              let pixels = contracted.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("Cannot render input edge fixture") }
        let bitmap = NSBitmapImageRep(cgImage: pixels)
        for boundary in [AppearancePreviewScene.inputPadding, AppearancePreviewScene.inputPadding + 969] {
            for offset in -24...24 {
                let x = Int((boundary + CGFloat(offset)) / request.size.width * CGFloat(bitmap.pixelsWide))
                let y = Int(contour.bounds.midY / request.size.height * CGFloat(bitmap.pixelsHigh))
                guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.45 else {
                    throw failure("Contracting the input glow exposed a bitmap edge inside the visible preview")
                }
            }
        }
    }

    private static func verifySampleField(_ controls: AppearanceWindowController) throws {
        guard let host = controls.previewHost else { throw failure("Missing input preview") }
        func input(_ view: NSView) -> NSTextField? {
            if view.identifier?.rawValue == "appearance.sample.input" { return view as? NSTextField }
            return view.subviews.lazy.compactMap { input($0) }.first
        }
        guard let field = input(host), field.isEditable, field.bounds.width > 100 else { throw failure("Sample composer is not a native editable field") }
        let fieldFrame = field.convert(field.bounds, to: host)
        let panelFrame = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)
        guard host.bounds.contains(fieldFrame), fieldFrame.width >= 320, !fieldFrame.intersects(panelFrame) else { throw failure("The controls panel covers the editable sample field") }
        let original = controls.preview.sampleText
        defer { controls.preview.sampleText = original }
        field.stringValue = "A sample message, Grüße 👋"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        guard controls.preview.sampleText == field.stringValue, controls.state.phase == .idle else { throw failure("Sample typing changed dictation or lost its text") }
        print("PASS: actual mounted native sample input accepts Unicode text without dictation or network access.")
    }

    private static func verifyBezelDrag(_ controls: AppearanceWindowController) async throws {
        guard let window = controls.window, let host = controls.previewHost,
              let drag = descendant(BezelPreviewContainer.self, in: host), let screen = NSScreen.screens.first else { throw failure("Missing mounted Bezel drag control") }
        let expected = AppearancePreviewScene.bezelPreviewDisplay(in: host.bounds.size).size
        guard AppearancePreviewScene.bezelWallpaper?.size == CGSize(width: 969, height: 1215),
              abs(drag.bounds.width - expected.width) < 1,
              abs(drag.bounds.height - expected.height) < 1 else {
            throw failure("Bezel placement must span the visible display: \(drag.bounds.size), expected \(expected)")
        }
        let displayed = drag.convert(drag.bounds, to: host)
        let panelInHost = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)
        guard host.bounds.insetBy(dx: -1, dy: -1).contains(displayed), displayed.intersects(panelInHost),
              displayed.width >= 440, displayed.height >= 600,
              abs(displayed.midX - host.bounds.midX) < 0.5 else {
            throw failure("Bezel dragging must extend above and below the controls across the complete visible display")
        }
        for side in BezelSide.allCases {
            for position in stride(from: 0.0, through: 1.0, by: 0.025) {
                drag.synchronize(side: side, position: position, phase: 1, time: 0, reducedMotion: true)
                let shape = drag.indicator.displayedShape
                let body = drag.indicator.convert(shape.path.boundingBoxOfPath, to: host)
                guard host.bounds.contains(body), !body.intersects(controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)) else {
                    throw failure("A Bezel preview position is hidden by the controls or viewport")
                }
            }
        }
        try await verifyBezelControlAvoidance(controls, drag: drag)
        try verifyLiquidContact()
        let state = controls.state
        let originalPosition = state.bezelVerticalPosition, originalSide = state.bezelSide
        defer { state.bezelVerticalPosition = originalPosition; state.bezelSide = originalSide }
        let live = BezelWindowController(state: state, presentsWindows: false)
        for side in BezelSide.allCases {
            state.bezelSide = side
            drag.synchronize(side: side, position: 0.25, phase: 1, time: 0, reducedMotion: true)
            let start = drag.convert(NSPoint(x: side == .left ? 24 : drag.bounds.width - 24, y: drag.indicator.frame.midY), to: nil)
            let panelFrame = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: drag)
            let edgeX: CGFloat = side == .left ? 24 : drag.bounds.width - 24
            guard !panelFrame.contains(drag.convert(start, from: nil)) else {
                throw failure("The glass panel blocks the Bezel drag path")
            }
            func event(_ type: NSEvent.EventType, y: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: start.x, y: y), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            }
            drag.mouseDown(with: event(.leftMouseDown, y: start.y))
            drag.mouseDragged(with: event(.leftMouseDragged, y: start.y + 45))
            drag.mouseUp(with: event(.leftMouseUp, y: start.y + 45))
            guard state.bezelVerticalPosition < 0.5,
                  AppState(preview: true).bezelVerticalPosition == state.bezelVerticalPosition,
                  let panel = live.prepareWindow(screens: [screen], pointer: NSPoint(x: screen.frame.midX, y: screen.frame.midY)),
                  panel.frame == BezelGeometry.frame(screen: screen.frame, side: side, verticalPosition: state.bezelVerticalPosition),
                  panel.ignoresMouseEvents, !panel.isVisible else { throw failure("Bezel drag did not persist or reach the hidden live panel") }
            _ = drag.accessibilityPerformIncrement()
            guard state.bezelVerticalPosition == drag.position else { throw failure("Accessible Bezel positioning failed") }

            state.bezelSide = side
            state.bezelVerticalPosition = 0.25
            drag.synchronize(side: side, position: 0.25, phase: 1, time: 0, reducedMotion: true)
            let from = drag.convert(NSPoint(x: edgeX, y: drag.indicator.frame.midY), to: nil)
            let middle = drag.convert(NSPoint(x: drag.bounds.midX, y: drag.bounds.midY + 90), to: nil)
            let destination = drag.convert(NSPoint(x: side == .left ? drag.bounds.width - 24 : 24, y: drag.bounds.midY + 90), to: nil)
            func dragEvent(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            }
            drag.mouseDown(with: dragEvent(.leftMouseDown, at: from))
            drag.mouseDragged(with: dragEvent(.leftMouseDragged, at: middle))
            guard drag.isDragging, drag.indicator.isHidden, let floating = drag.floatingIndicator,
                  let shape = floating.previewShape, shape.path.contains(shape.symbolCenter),
                  shape.path.boundingBox.minX > 0, shape.path.boundingBox.maxX < floating.bounds.width,
                  state.bezelSide == side, state.bezelVerticalPosition == 0.25,
                  floating.superview?.superview === window.contentView else {
                throw failure("Dragging must detach into a floating blob above the controls, without prematurely saving placement")
            }
            let round = BezelPreviewContainer.blob(velocity: .zero).path.boundingBox
            let stretched = BezelPreviewContainer.blob(velocity: CGVector(dx: 800, dy: 0)).path.boundingBox
            guard stretched.width > round.width, stretched.height < round.height else { throw failure("The floating blob does not deform with drag motion") }
            drag.mouseDragged(with: dragEvent(.leftMouseDragged, at: destination))
            if let floating = drag.floatingIndicator, let shape = floating.previewShape {
                let contour = floating.convert(shape.path.boundingBoxOfPath, to: drag)
                let edge = side == .left ? contour.maxX : contour.minX
                guard abs(edge - (side == .left ? drag.bounds.width : 0)) < 0.01 else { throw failure("Dragged liquid shape does not visually reach the destination edge") }
            } else { throw failure("Missing attached liquid shape during drag") }
            drag.mouseUp(with: dragEvent(.leftMouseUp, at: destination))
            let other: BezelSide = side == .left ? .right : .left
            controls.refresh()
            guard state.bezelSide == other, AppState(preview: true).bezelSide == other,
                  state.bezelVerticalPosition < 0.5, !drag.isDragging, drag.floatingIndicator == nil,
                  !drag.indicator.isHidden, controls.sidePicker.selectedSegment == (other == .left ? 0 : 1),
                  live.prepareWindow(screens: [screen], pointer: screen.frame.origin)?.frame == BezelGeometry.frame(screen: screen.frame, side: other, verticalPosition: state.bezelVerticalPosition) else {
                throw failure("Cross-edge release did not save placement, update the switch or attach the Bezel")
            }
            let savedPosition = state.bezelVerticalPosition
            drag.mouseDown(with: dragEvent(.leftMouseDown, at: destination))
            drag.mouseDragged(with: dragEvent(.leftMouseDragged, at: middle))
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
            drag.keyDown(with: escape)
            guard !drag.isDragging, drag.floatingIndicator == nil, state.bezelSide == other,
                  state.bezelVerticalPosition == savedPosition else { throw failure("Escape did not cancel the floating drag") }
            drag.synchronize(side: other, position: savedPosition, phase: 1, time: 1, reducedMotion: false)
            drag.mouseDown(with: dragEvent(.leftMouseDown, at: destination))
            drag.mouseDragged(with: dragEvent(.leftMouseDragged, at: middle))
            if let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"], let content = window.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("bezel-floating-\(side.rawValue).png"))
            }
            drag.mouseDragged(with: dragEvent(.leftMouseDragged, at: from))
            drag.mouseUp(with: dragEvent(.leftMouseUp, at: from))
            let deadline = CACurrentMediaTime() + 2
            while drag.floatingIndicator != nil, CACurrentMediaTime() < deadline {
                pumpBezelTimers()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard drag.floatingIndicator == nil, !drag.indicator.isHidden, state.bezelSide == side else {
                throw failure("Animated release did not finish attaching to the chosen edge")
            }
            for (key, selectedSide) in [(UInt16(123), BezelSide.left), (UInt16(124), BezelSide.right)] {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key)!
                drag.keyDown(with: event)
                guard state.bezelSide == selectedSide else { throw failure("Arrow-key side placement failed") }
            }
        }
        print("PASS: native unposted drag events move and save the Bezel on both edges; live panels retain click-through behavior.")
    }

    private static func verifyBezelControlAvoidance(_ controls: AppearanceWindowController, drag: BezelPreviewContainer) async throws {
        guard let window = controls.window, let host = controls.previewHost else { throw failure("Missing Bezel fixture") }
        let state = controls.state
        let savedSide = state.bezelSide, savedPosition = state.bezelVerticalPosition
        defer { state.bezelSide = savedSide; state.bezelVerticalPosition = savedPosition }
        let panel = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: drag)
        let originalPanel = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)
        for reducedMotion in [false, true] {
            for side in BezelSide.allCases {
                for fraction in [0.2, 0.8] {
                    state.bezelSide = side
                    state.bezelVerticalPosition = 0.15
                    drag.synchronize(side: side, position: 0.15, phase: 1, time: 0, reducedMotion: reducedMotion)
                    let x: CGFloat = side == .left ? 24 : drag.bounds.width - 24
                    let start = CGPoint(x: x, y: drag.indicator.frame.midY)
                    let drop = CGPoint(x: x, y: panel.minY + panel.height * fraction)
                    func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
                        NSEvent.mouseEvent(with: type, location: drag.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 7, clickCount: 1, pressure: 1)!
                    }
                    guard controls.controlsPanel.bounds.width == 500,
                          abs(controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host).midX - host.bounds.midX) < 0.5 else {
                        throw failure("The Bezel bar must restore its full centered width outside overlap")
                    }
                    drag.mouseDown(with: event(.leftMouseDown, start))
                    drag.mouseDragged(with: event(.leftMouseDragged, drop))
                    guard controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host) == originalPanel else {
                        throw failure("Dragging must never move or resize the controls bar")
                    }
                    guard let floating = drag.floatingIndicator,
                          floating.superview?.superview === window.contentView,
                          abs(drag.convert(floating.frame, from: floating.superview).midY - drop.y) < 1 else {
                        throw failure("The dragged blob must follow the pointer over the controls")
                    }
                    drag.mouseUp(with: event(.leftMouseUp, drop))
                    if !reducedMotion {
                        guard drag.floatingIndicator != nil, drag.indicator.isHidden else {
                            throw failure("An obstructed drop must slide out, not jump to its destination")
                        }
                        try await Task.sleep(nanoseconds: 100_000_000)
                        guard let floating = drag.floatingIndicator else { throw failure("The escape animation ended abruptly") }
                        let current = drag.convert(floating.frame, from: floating.superview).midY
                        let target = drag.indicator.frame.midY
                        guard abs(current - drop.y) < 4, abs(current - target) < 4 else {
                            throw failure("The chosen Bezel height must remain unchanged")
                        }
                        let deadline = CACurrentMediaTime() + 2
                        while drag.floatingIndicator != nil, CACurrentMediaTime() < deadline {
                            pumpBezelTimers()
                            try await Task.sleep(nanoseconds: 10_000_000)
                        }
                    }
                    let panelInHost = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: host)
                    guard panelInHost == originalPanel else {
                        throw failure("The bar must remain fixed and centered throughout overlap")
                    }
                    let panel = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: drag)
                    let body = drag.indicator.convert(drag.indicator.displayedShape.path.boundingBoxOfPath, to: drag)
                    let hit = CGRect(x: side == .left ? 0 : drag.bounds.width - 70, y: drag.indicator.frame.midY - 56, width: 70, height: 112)
                    guard drag.floatingIndicator == nil, !drag.indicator.isHidden,
                          !body.intersects(panel),
                          host.bounds.contains(drag.convert(body, to: host)),
                          abs(drag.indicator.frame.midY - drop.y) < 1,
                          controls.controlsPanel.bounds.width == 500,
                          controls.sectionBar.isHidden,
                          controls.controlsPanel.bounds.contains(controls.modeBar.convert(controls.modeBar.bounds, to: controls.controlsPanel)),
                          state.bezelVerticalPosition == drag.position,
                          AppState(preview: true).bezelVerticalPosition == drag.position,
                          window.contentView?.hitTest(drag.convert(CGPoint(x: x, y: body.midY), to: window.contentView)) === drag else {
                        throw failure("Bezel clearance: reducedMotion=\(reducedMotion), floating=\(drag.floatingIndicator != nil), hidden=\(drag.indicator.isHidden), contains=\(host.bounds.contains(drag.convert(body, to: host))), persisted=\(AppState(preview: true).bezelVerticalPosition), side=\(side), panel=\(panel), hit=\(hit), height=\(drag.indicator.frame.midY - drop.y), width=\(controls.controlsPanel.bounds.width), position=\(state.bezelVerticalPosition)/\(drag.position), clickable=\(window.contentView?.hitTest(drag.convert(CGPoint(x: x, y: body.midY), to: window.contentView)) === drag)")
                    }
                }
            }
        }
        print("PASS: Bezel freely crosses the controls while the full bar remains fixed and centered; hit testing, persistence and Reduce Motion agree.")
    }

    private static func pumpBezelTimers() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }

    private static func verifyLiquidContact() throws {
        for side in BezelSide.allCases {
            for distance in [32.0, 55.0, 78.0] {
                let shape = BezelDragShape.make(velocity: .zero, side: side, distance: distance)
                let edge = 100 + (side == .left ? -distance : distance)
                let box = shape.path.boundingBoxOfPath
                guard abs((side == .left ? box.minX : box.maxX) - edge) < 0.001,
                      shape.path.contains(CGPoint(x: edge + (side == .left ? 0.1 : -0.1), y: 190)),
                      shape.path.contains(shape.symbolCenter) else { throw failure("Liquid connector is not flush with the \(side.title) preview edge") }
            }
        }
        let still = BezelDragShape.make(velocity: .zero).path.boundingBoxOfPath
        let moving = BezelDragShape.make(velocity: CGVector(dx: 900, dy: 0)).path.boundingBoxOfPath
        guard moving.width > still.width * 1.4, moving.height < still.height * 0.85 else { throw failure("Liquid drag has insufficient squash and stretch") }
        if let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"],
           let context = CGContext(data: nil, width: 1000, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
            for (index, distance) in [32.0, 55.0, 78.0, 100.0].enumerated() {
                for (row, side) in BezelSide.allCases.enumerated() {
                    context.saveGState()
                    context.translateBy(x: Double(index) * 250 + 25, y: Double(row) * 250 - 75)
                    let shape = BezelDragShape.make(velocity: CGVector(dx: 300, dy: 150), wobble: 0.6, side: side, distance: distance)
                    context.setStrokeColor(NSColor.systemBlue.cgColor)
                    let edge = 100 + (side == .left ? -distance : distance)
                    context.move(to: CGPoint(x: edge, y: 100)); context.addLine(to: CGPoint(x: edge, y: 280)); context.strokePath()
                    context.setFillColor(NSColor.black.cgColor); context.addPath(shape.path); context.fillPath()
                    context.restoreGState()
                }
            }
            if let image = context.makeImage() {
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("bezel-liquid-contact.png"))
            }
        }
        print("PASS: stronger liquid squash/stretch and generated flush neck geometry on both edges.")
    }

    private static func verifyPreviewProportions() async throws {
        let state = AppState(preview: true)
        let saved = state.glowAppearance
        defer { state.glowAppearance = saved }
        for mode in GlowAppearance.selectableCases {
            state.glowAppearance = mode
            let activity = AppearancePreviewActivity(mode: mode)
            let host = NSHostingView(rootView: AppearancePreview(state: state, activity: activity))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 572, height: 720),
                styleMask: [.borderless], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.close() }
            for size in [CGSize(width: 572, height: 720), CGSize(width: 900, height: 400), CGSize(width: 320, height: 900)] {
                window.setContentSize(size)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds: 50_000_000)
                host.layoutSubtreeIfNeeded()
                guard let background = descendant(AppearancePreviewBackdropView.self, in: host),
                      let contents = background.layer?.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID,
                      background.layer?.contentsGravity == .resizeAspect else {
                    throw failure("Preview background must preserve its source aspect ratio")
                }
                let pixels = contents as! CGImage
                let sourceRatio = CGFloat(pixels.width) / CGFloat(pixels.height)
                let displayed = background.convert(background.bounds, to: host)
                let sx = displayed.width / background.bounds.width
                let sy = displayed.height / background.bounds.height
                guard abs(sx - sy) < 0.00001,
                      abs(displayed.height - displayed.width / sourceRatio) < 0.5,
                      !window.isVisible else {
                    throw failure("\(mode) preview stretches at \(size): \(displayed.size), source \(pixels.width)×\(pixels.height), scales \(sx)/\(sy)")
                }
                let placement = AppearancePreviewScene.placement(for: mode, viewport: host.bounds.size, topInset: activity.topInset)
                let top = host.isFlipped ? displayed.minY - host.bounds.minY : host.bounds.maxY - displayed.maxY
                guard abs(displayed.midX - host.bounds.midX) < 0.5,
                      abs(top - placement.origin.y) < 0.5 else {
                    throw failure("The \(mode.rawValue) background must follow the shared centered/lifted preview placement: image \(displayed), host \(host.bounds)")
                }
                if !mode.followsInput {
                    guard displayed.insetBy(dx: -0.5, dy: -0.5).contains(host.bounds) else {
                        throw failure("The \(mode.rawValue) background leaves the pane uncovered")
                    }
                }
            }
        }
        print("PASS: preview backgrounds preserve proportions, centered input placement and lifted Bottom artwork in hidden windows.")
    }

    private static func rendered(_ frame: ChromaFrame) throws -> Data {
        let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: frame).frame(width: frame.request.size.width, height: frame.request.size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage, let data = image.dataProvider?.data else { throw failure("Canvas failed to render") }
        return data as Data
    }
    private static func bytes(_ image: NSImage) -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AppearanceWindowProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
