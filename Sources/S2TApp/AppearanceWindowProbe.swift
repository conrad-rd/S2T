import AppKit
import SwiftUI
import S2TCore

@MainActor enum AppearanceWindowProbe {
    static func verifyModeControls(state: AppState, menu: MenuBarController) throws {
        let saved = state.glowAppearance
        defer { state.glowAppearance = saved; menu.appearanceWindow.window?.close() }
        guard let entry = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance" }),
              entry.submenu == nil, entry is ActionMenuItem, entry.action != nil,
              entry.attributedTitle?.string.contains("Settings…") == true, entry.keyEquivalent == "," else { throw failure("Appearance must be a native window action") }
        let controls = menu.appearanceWindow
        let window = controls.prepare()
        controls.selectSection(.edge)
        defer { controls.selectSection(.glow) }
        guard controls.splitController.splitViewItems.first?.behavior == .sidebar,
              controls.sidebar.table.style == .sourceList,
              controls.sidebar.table.numberOfRows == 8,
              controls.sidebar.tableView(controls.sidebar.table, isGroupRow: 0),
              !controls.sidebar.tableView(controls.sidebar.table, shouldSelectRow: 0) else { throw failure("Mode switcher is not a native macOS sidebar") }
        window.contentView?.layoutSubtreeIfNeeded()
        let logo = controls.sidebar.logo
        let logoFrame = logo.convert(logo.bounds, to: controls.sidebar.view)
        let navigationFrame = controls.sidebar.table.enclosingScrollView!.convert(controls.sidebar.table.enclosingScrollView!.bounds, to: controls.sidebar.view)
        guard logo.image != nil, logo.bounds.width >= 150, logo.bounds.height >= 65,
              controls.sidebar.view.bounds.contains(logoFrame), !logoFrame.intersects(navigationFrame),
              controls.sidebar.view.bounds.width >= 200 else { throw failure("The large sidebar logo or navigation is clipped") }
        let theme = state.menuAppearance, phase = state.phase
        for mode in GlowAppearance.allCases {
            let index = controls.sidebar.row(for: mode)
            controls.sidebar.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            guard state.glowAppearance == mode, AppState(preview: true).glowAppearance == mode,
                  controls.sidebar.table.selectedRow == index, state.menuAppearance == theme,
                  state.phase == phase, !window.isVisible else { throw failure("Mode selection changed theme, dictation, or window visibility") }
            guard let content = window.contentView else { throw failure("No Appearance content") }
            content.layoutSubtreeIfNeeded()
            func findPreview(_ view: NSView) -> NSView? {
                if view.identifier?.rawValue == "appearance.preview" { return view }
                return view.subviews.lazy.compactMap { findPreview($0) }.first
            }
            guard let host = findPreview(content) else { throw failure("Missing mounted preview") }
            let previewFrame = host.convert(host.bounds, to: content)
            guard let detail = host.superview,
                  host.frame == detail.bounds,
                  previewFrame.width >= 540, previewFrame.height >= 700,
                  !detail.subviews.contains(where: { $0.identifier?.rawValue == "settings.theme" }),
                  detail.subviews.filter({ !$0.isHidden }).allSatisfy({ $0 === host || $0 === controls.controlsPanel }) else {
                throw failure("The preview must fill the appearance pane without headings or theme controls")
            }
            guard controls.controlsPanel.isHidden == (mode == .bezel) else {
                throw failure("Bezel must have no floating controls panel; glow modes must retain theirs")
            }
            if mode == .bezel { continue }
            let panel = controls.controlsPanel!
            let panelFrame = panel.convert(panel.bounds, to: content)
            guard previewFrame.contains(panelFrame), panelFrame.width >= 440,
                  abs(panelFrame.midX - previewFrame.midX) < 0.5,
                  abs((host.isFlipped ? host.bounds.maxY - panel.convert(panel.bounds, to: host).maxY : panel.convert(panel.bounds, to: host).minY) - 24) < 0.5,
                  controls.controlsScroll.isDescendant(of: panel),
                  controls.phasePicker.isDescendant(of: panel), controls.sectionBar.isDescendant(of: panel) else {
                throw failure("All appearance controls must share a floating panel over the preview")
            }
            let bar = controls.sectionBar
            let barFrame = bar.convert(bar.bounds, to: content)
            let phases = controls.phasePicker
            let phaseFrame = phases.convert(phases.bounds, to: content)
            guard bar.isHidden == (mode == .bezel), panelFrame.contains(phaseFrame),
                  mode == .bezel || (panelFrame.contains(barFrame) && !phaseFrame.intersects(barFrame) &&
                  abs(phaseFrame.midY - barFrame.midY) < 0.5 && phaseFrame.height == barFrame.height) else {
                throw failure("Preview states and tabs must align inside the glass panel")
            }
            if #available(macOS 26, *) {
                guard let glass = panel as? NSGlassEffectView, glass.contentView != nil,
                      glass.style == .regular, glass.cornerRadius == 36 else { throw failure("Missing native Liquid Glass control panel") }
                guard !glass.contentView!.subviews.contains(where: { $0 is NSGlassEffectView }) else {
                    throw failure("The controls must not stack glass layers inside glass")
                }
            }
            for group in [phases as NSView] + (mode == .bezel ? [] : [bar]) {
                guard group is SettingsCapsuleGroup, group.layer?.borderWidth == 0,
                      group.layer?.backgroundColor == NSColor.white.withAlphaComponent(0.12).cgColor,
                      group.layer?.cornerRadius == 24,
                      group.layer?.cornerCurve == .circular else { throw failure("Capsule groups must use a light tint without an outline") }
                let buttons: [NSButton] = group === phases ? phases.buttons : bar.buttons
                for button in [buttons.first!, buttons.last!] {
                    let frame = button.convert(button.bounds, to: group)
                    let inset = button === buttons.first! ? frame.minX : group.bounds.width - frame.maxX
                    guard abs(inset - 6) < 0.5, abs(frame.midY - group.bounds.midY) < 0.5,
                          abs(24 - inset - frame.height / 2) < 0.5 else {
                        throw failure("Group and button capsule corners are not concentric")
                    }
                }
            }
            if #available(macOS 26, *), let glass = panel as? NSGlassEffectView {
                guard let reset = glass.contentView?.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "appearance.reset" }),
                      reset.bezelStyle == .glass, reset.borderShape == .capsule, reset.tintProminence == .primary,
                      reset.bezelColor == NSColor.systemBlue, reset.action != nil,
                      reset.title == "Reset",
                      reset.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .white,
                      reset.bounds.height == 32, reset.isHidden == (mode == .bezel) else {
                    throw failure("Reset must be a blue native glass capsule")
                }
            }
            if mode == .aroundNotch {
                guard let notch = AppearancePreviewScene.notch.notch else { throw failure("Missing preview notch") }
                let origin = AppearancePreviewScene.renderOrigin(for: mode)
                guard notch.offsetBy(dx: origin.x, dy: origin.y) == CGRect(x: 342, y: 134, width: 246, height: 44),
                      AppearancePreviewScene.notchWallpaper?.size == CGSize(width: 969, height: 1215) else {
                    throw failure("The preview glow must align with the supplied Mac notch")
                }
            }
            guard phases.buttons.allSatisfy({ $0.bounds.size == NSSize(width: 36, height: 36) }),
                  mode == .bezel || bar.buttons.allSatisfy({ abs($0.bounds.width - bar.buttons[0].bounds.width) < 0.5 && $0.bounds.height == 36 }) else {
                throw failure("Preview controls differ in \(mode): phases \(phases.buttons.map { $0.bounds.size }), tabs \(bar.buttons.map { $0.bounds.size })")
            }
            for button in phases.buttons {
                guard button.isBordered == (button.state == .on) else {
                    throw failure("Only the selected preview icon may have a persistent circle")
                }
                button.setHovered(false)
                guard button.layer?.backgroundColor?.alpha == 0 else {
                    throw failure("An idle preview icon retains its hover fill")
                }
                button.setHovered(true)
                guard (button.layer?.backgroundColor?.alpha ?? 0) > 0 else {
                    throw failure("Preview icon hover must show a tinted circle")
                }
                button.setHovered(false)
            }
            for button in (bar.buttons + phases.buttons).compactMap({ $0 as? SettingsHoverButton }) {
                button.setHovered(true)
                guard button.hovered, button.layer?.masksToBounds == false, abs((button.layer?.cornerRadius ?? 0) - min(button.bounds.width, button.bounds.height) / 2) < 0.5 else {
                    throw failure("Hover backgrounds must have fully rounded ends")
                }
                button.setHovered(false)
            }
            for button in phases.buttons + (mode == .bezel ? [] : bar.buttons) {
                guard button.image != nil, button.bounds.height == 36,
                      button.title.isEmpty || (button.bounds.width >= 70 && button.title == AppearanceSection(rawValue: button.tag)?.title) else { throw failure("Missing icon or clipped tab: \(button.title), \(button.bounds), image \(button.image != nil)") }
                if mode != .bezel || button.title.isEmpty {
                    let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: content.superview)
                    let target = content.hitTest(point)
                    guard target === button || target?.isDescendant(of: button) == true else { throw failure("A sibling view intercepts tab clicks: \(String(describing: target))") }
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
        print("PASS: native split-view sidebar, all four saved selections, mounted preview at full width, fitting controls and isolated dictation phase.")
    }

    static func run() async throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let state = AppState(preview: true)
        let menu = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem); menu.appearanceWindow.window?.close() }
        menu.menuNeedsUpdate(menu.menu)
        try verifyModeControls(state: state, menu: menu)
        guard let action = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance" }) as? ActionMenuItem else { throw failure("Missing Appearance action") }
        action.invoke()
        let controls = menu.appearanceWindow
        guard controls.preview.running, let window = controls.window, !window.isVisible else { throw failure("Appearance action did not prepare its local preview") }
        try verifySpeechPreviewIsolation(controls)
        state.glowAppearance = .bottom
        for control in AppearanceControl.allCases {
            guard let slider = controls.sliders[control] else { throw failure("Missing slider") }
            let value = control.range.lowerBound + (control.range.upperBound - control.range.lowerBound) * 0.7
            slider.doubleValue = value
            slider.sendAction(slider.action, to: slider.target)
            guard abs(control.value(in: state) - value) < 0.000001,
                  abs(control.value(in: AppState(preview: true)) - value) < 0.000001 else { throw failure("\(control.title) did not persist") }
        }
        for (index, side) in BezelSide.allCases.enumerated() {
            controls.sidePicker.buttons[index].performClick(nil)
            guard controls.sidePicker.buttons.filter({ $0.state == .on }).map(\.tag) == [index] else { throw failure("Placement switch lost exclusive selection") }
            if #available(macOS 26, *) {
                guard controls.sidePicker.buttons.allSatisfy({ $0.bezelStyle == .glass && $0.borderShape == .capsule }) else { throw failure("Placement must use native glass capsules") }
            }
            guard state.bezelSide == side, AppState(preview: true).bezelSide == side else { throw failure("Bezel placement did not persist") }
        }
        for phase in 0...2 {
            controls.phasePicker.buttons[phase].performClick(nil)
            guard controls.phasePicker.buttons.filter({ $0.state == .on }).map(\.tag) == [phase],
                  controls.phasePicker.buttons.allSatisfy({ $0.image != nil && $0.title.isEmpty }),
                  controls.phasePicker.buttons.allSatisfy({ $0.bounds.size == NSSize(width: 36, height: 36) }),
                  controls.preview.phase == phase, state.phase == .idle else { throw failure("Preview state: selected=\(controls.phasePicker.buttons.map { $0.state.rawValue }), titles=\(controls.phasePicker.buttons.map { $0.title }), images=\(controls.phasePicker.buttons.map { $0.image != nil }), phase=\(controls.preview.phase), expected=\(phase), dictation=\(state.phase)") }
        }
        guard let wallpaper = AppearancePreviewScene.wallpaper, wallpaper.size.width >= 1000 else { throw failure("Sequoia wallpaper is missing or only a thumbnail") }
        guard let bottomImage = AppearancePreviewScene.bottomWallpaper,
              bottomImage.size == NSSize(width: 969, height: 1215),
              abs(AppearancePreviewScene.renderSize(for: .bottom).height - 345.1259) < 0.01,
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
            controls.sectionBar.buttons[section.rawValue].performClick(nil)
            guard controls.selectedSection == section, controls.sectionBar.buttons.filter({ $0.state == .on }).map(\.tag) == [section.rawValue] else { throw failure("Settings tab did not switch") }
            for control in AppearanceControl.allCases {
                guard let slider = controls.sliders[control],
                      slider.isHiddenOrHasHiddenAncestor == (control.section != section) else {
                    throw failure("Settings tab mixes unrelated controls")
                }
            }
        }
        controls.selectSection(.glow)
        controls.preview.phase = 1
        state.glowStrength = 1.3; state.glowWidth = 1; state.glowMinimum = 0.3; state.glowMaximum = 2
        state.glowTuning = .init()
        state.menuAppearance = "light"
        for mode in GlowAppearance.allCases {
            state.glowAppearance = mode
            controls.refresh()
            try await verifyMountedPreview(controls, mode: mode)
            if mode == .aroundInput {
                try verifySampleField(controls)
                controls.preview.phase = 0
                try await verifyMountedPreview(controls, mode: mode, fixtureSuffix: "-idle")
                controls.preview.phase = 1
            }
            if mode == .bezel { try await verifyBezelDrag(controls) }
        }
        state.glowAppearance = .aroundInput
        state.menuAppearance = "dark"
        controls.selectSection(.edge)
        controls.reveal(.maximum)
        try await verifyMountedPreview(controls, mode: .aroundInput)
        controls.selectSection(.glow)
        state.menuAppearance = "light"
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            state.glowAppearance = mode
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
        let renderer = controls.preview.renderer
        let request = AppearancePreviewScene.request(state: state, phase: 1, time: 0, reducedMotion: true, backdrop: true)
        renderer.submit(request)
        let deadline = CACurrentMediaTime() + 10
        while renderer.frame?.request != request, CACurrentMediaTime() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard renderer.frame != nil else { throw failure("Live preview did not publish") }
        // A never-shown window has no AppKit close notification; deliver that lifecycle event explicitly.
        controls.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        window.close()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard renderer.frame == nil, !controls.preview.running, state.phase == .idle,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Closing preview: framePresent=\(renderer.frame != nil), running=\(controls.preview.running), phase=\(state.phase), initialPID=\(String(describing: initialPID)), finalPID=\(String(describing: NSWorkspace.shared.frontmostApplication?.processIdentifier))") }
        print("PASS: saved native controls, menu action dispatch, preview completion and close cancellation. No screen, microphone, clipboard or focused-field access.")
    }

    private static func verifySpeechPreviewIsolation(_ controls: AppearanceWindowController) throws {
        guard controls.preview.phase == 0 else { throw failure("The main appearance preview must open idle") }
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            let originalMode = controls.state.glowAppearance
            controls.state.glowAppearance = mode
            let still = AppearancePreviewScene.request(state: controls.state, phase: 0, time: 0, reducedMotion: false, backdrop: true)
            let later = AppearancePreviewScene.request(state: controls.state, phase: 0, time: 9, reducedMotion: false, backdrop: true)
            let speaking = AppearancePreviewScene.request(state: controls.state, phase: 1, time: 0.7, reducedMotion: false, backdrop: true)
            controls.state.glowAppearance = originalMode
            guard still == later, still.brightness > 0, still.profile.blurGain > 0,
                  speaking.profile.energy > still.profile.energy,
                  speaking.profile.energy - still.profile.energy <= 0.08,
                  AppearancePreviewScene.cycleTime(phase: 0, time: 9, reducedMotion: false) == nil,
                  AppearancePreviewScene.cycleTime(phase: 1, time: 9, reducedMotion: false) == 9,
                  controls.phasePicker.buttons[0].toolTip == "Stiff" else {
                throw failure("Stiff preview must stay visible and unchanged while Speaking pulses gently")
            }
        }
        let savedMaximum = controls.state.glowMaximum
        defer { controls.state.glowMaximum = savedMaximum }
        for phase in [1, 2, 0] {
            controls.sectionBar.buttons[AppearanceSection.speech.rawValue].performClick(nil)
            controls.phasePicker.buttons[phase].performClick(nil)
            controls.sliders[.maximum]!.doubleValue = 4.5
            controls.sliders[.maximum]!.sendAction(controls.sliders[.maximum]!.action, to: controls.sliders[.maximum]!.target)
            guard controls.preview.phase == phase else { throw failure("Editing Speech reset its selected preview state") }
            for section in [AppearanceSection.glow, .edge] {
                controls.sectionBar.buttons[section.rawValue].performClick(nil)
                let request = AppearancePreviewScene.request(state: controls.state, phase: controls.preview.phase,
                    time: 0, reducedMotion: false, backdrop: true)
                guard controls.preview.phase == 0, controls.phasePicker.buttons[0].state == .on,
                      request.profile.distortion == .identity, request.profile.energy == 0.65,
                      controls.state.phase == .idle else { throw failure("Speech preview state leaked into the main preview") }
                controls.sectionBar.buttons[AppearanceSection.speech.rawValue].performClick(nil)
                guard controls.preview.phase == phase else { throw failure("Speech did not retain its own preview state") }
            }
        }
        controls.selectSection(.glow)
        print("PASS: Speech preview states stay independent; Glow and Edge return idle, while saved speech amounts remain intact.")
    }

    private static func verifyMountedPreview(_ controls: AppearanceWindowController, mode: GlowAppearance, fixtureSuffix: String = "") async throws {
        guard let host = controls.previewHost, let content = controls.window?.contentView else { throw failure("Missing preview host") }
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
        if mode == .aroundInput {
            guard let image = view.layer?.contents, CFGetTypeID(image as CFTypeRef) == CGImage.typeID else {
                throw failure("Missing Around Input background image")
            }
            guard let expected = AppearancePreviewScene.inputWallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  abs(AppearancePreviewScene.input.minX - 59.7) < 0.1,
                  abs(AppearancePreviewScene.input.maxX - 911.03) < 0.1,
                  abs(AppearancePreviewScene.input.maxY - 320.19) < 0.1,
                  AppearancePreviewScene.inputRadius == 40 else { throw failure("ChatGPT preview input geometry is misaligned") }
            let visibleLeft = view.convert(NSPoint(x: AppearancePreviewScene.inputPadding, y: 0), to: host).x
            let visibleRight = view.convert(NSPoint(x: AppearancePreviewScene.inputPadding + 969, y: 0), to: host).x
            guard abs(visibleLeft - host.bounds.minX) < 0.5,
                  abs(visibleRight - host.bounds.maxX) < 0.5 else {
                throw failure("The mounted ChatGPT image shifted within the preview: left \(visibleLeft), right \(visibleRight), viewport \(host.bounds)")
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
                  view.layer?.filters?.isEmpty == false else { throw failure("Mounted preview did not receive its rendered glow and native blur") }
        }
        // AppKit draws only our never-shown, authored view hierarchy into this bitmap.
        // This does not read a window image or any display pixels.
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw failure("Cannot draw the mounted preview") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var glowPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > color.greenComponent + 0.06,
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
        let request = AppearancePreviewScene.request(state: state, phase: 0, time: 0, reducedMotion: false, backdrop: true)
        guard case let .input(rect, _, _) = request.geometry,
              abs(rect.minX - AppearancePreviewScene.inputPadding - AppearancePreviewScene.input.minX) < 0.001,
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
                let y = Int(rect.midY / request.size.height * CGFloat(bitmap.pixelsHigh))
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
        guard host.bounds.contains(fieldFrame), !fieldFrame.intersects(panelFrame) else { throw failure("The controls panel covers the editable sample field") }
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
        guard AppearancePreviewScene.bezelWallpaper?.size == CGSize(width: 969, height: 1215),
              drag.bounds.size == CGSize(width: 837, height: 1095) else { throw failure("Bezel preview must fit the pictured display") }
        let displayed = drag.convert(drag.bounds, to: host)
        let sx = host.bounds.width / 969, sy = host.bounds.height / 1215
        guard abs(displayed.minX - 66 * sx) < 0.5,
              abs(displayed.maxX - 903 * sx) < 0.5,
              abs((host.isFlipped ? displayed.minY : host.bounds.maxY - displayed.maxY) - 120 * sy) < 0.5 else {
            throw failure("Bezel preview is not aligned to the supplied Mac screen edges")
        }
        try verifyLiquidContact()
        let state = controls.state
        let originalPosition = state.bezelVerticalPosition, originalSide = state.bezelSide
        defer { state.bezelVerticalPosition = originalPosition; state.bezelSide = originalSide }
        let live = BezelWindowController(state: state, presentsWindows: false)
        for side in BezelSide.allCases {
            state.bezelSide = side
            drag.side = side
            drag.position = 0.5
            let start = drag.convert(NSPoint(x: side == .left ? 24 : drag.bounds.width - 24, y: drag.bounds.midY), to: nil)
            let panelFrame = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: drag)
            let edgeX: CGFloat = side == .left ? 24 : drag.bounds.width - 24
            guard edgeX < panelFrame.minX || edgeX > panelFrame.maxX else {
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
            state.bezelVerticalPosition = 0.5
            drag.synchronize(side: side, position: 0.5, phase: 1, time: 0, reducedMotion: true)
            let from = drag.convert(NSPoint(x: edgeX, y: drag.bounds.midY), to: nil)
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
                  state.bezelSide == side, state.bezelVerticalPosition == 0.5,
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
        for button in controls.phasePicker.buttons {
            button.setHovered(true)
            guard button.hovered else { throw failure("Missing hover response") }
            button.setHovered(false)
        }
        print("PASS: native unposted drag events move and save the Bezel on both edges; live panels retain click-through behavior.")
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
