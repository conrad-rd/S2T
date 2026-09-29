import AppKit
import S2TCore

@MainActor enum AppearanceSelectionProbe {
    static func run() throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        let menu = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem); menu.appearanceWindow.window?.close() }
        menu.menuNeedsUpdate(menu.menu)
        try verify(state: state, menu: menu)
    }

    static func verify(state: AppState, menu: MenuBarController) throws {
        let controls = menu.appearanceWindow
        let window = controls.prepare()
        controls.sidebar.selectAppearance()
        controls.refresh()
        let saved = state.glowAppearance
        let savedPhase = state.phase
        defer { state.glowAppearance = saved; state.phase = savedPhase }
        guard let submenu = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance.styles" })?.submenu else {
            throw failure("Missing root Appearance submenu")
        }
        menu.menuNeedsUpdate(submenu)
        let options = submenu.items.compactMap { $0 as? ActionMenuItem }
        guard options.map(\.title) == GlowAppearance.selectableCases.map(\.title) else {
            throw failure("The menu must expose every appearance exactly once")
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let picker = controls.modeBar.picker
        guard picker.segmentCount == GlowAppearance.selectableCases.count else {
            throw failure("The preview must expose every appearance as native segments")
        }
        guard controls.sidebar.table.numberOfRows == 7,
              let cell = controls.sidebar.table.view(atColumn: 0, row: controls.sidebar.appearanceRow, makeIfNecessary: true) as? NSTableCellView,
              cell.accessibilityLabel() == "Appearance", cell.toolTip == "Appearance",
              let detail = controls.modeBar.superview,
              detail.bounds.contains(controls.modeBar.frame),
              controls.modeBar.bounds.insetBy(dx: -1, dy: -1).contains(picker.convert(picker.bounds, to: controls.modeBar)),
              controls.modeBar.isDescendant(of: controls.controlsPanel),
              controls.controlsPanel.bounds.contains(controls.modeBar.convert(controls.modeBar.bounds, to: controls.controlsPanel)),
              (controls.sectionBar.isHidden || !controls.modeBar.convert(controls.modeBar.bounds, to: controls.controlsPanel).intersects(controls.sectionBar.convert(controls.sectionBar.bounds, to: controls.controlsPanel))),
              picker.bounds.width / CGFloat(picker.segmentCount) >= 32 && picker.bounds.height >= 32,
              controls.modeBar.bounds.width == 228, controls.modeBar.bounds.height == 42 else {
            let cell = controls.sidebar.table.view(atColumn: 0, row: controls.sidebar.appearanceRow, makeIfNecessary: true)
            throw failure("Appearance layout: rows \(controls.sidebar.table.numberOfRows), label \(cell?.accessibilityLabel() ?? "nil"), tooltip \(cell?.toolTip ?? "nil"), detail \(String(describing: controls.modeBar.superview?.bounds)), bar \(controls.modeBar.frame), picker \(picker.convert(picker.bounds, to: controls.modeBar)), intrinsic \(picker.intrinsicContentSize), panel \(controls.controlsPanel.frame)")
        }
        for index in 0..<picker.segmentCount {
            guard picker.image(forSegment: index) != nil else { throw failure("A preview segment is missing its appearance icon") }
        }
        let previewModes: [GlowAppearance] = GlowAppearance.selectableCases
        guard (0..<picker.segmentCount).map { picker.toolTip(forSegment: $0) } == previewModes.map({ $0.title }) else {
            throw failure("Appearance controls must expose their native segment names")
        }
        try verifyStablePositions(controls)
        try verifyNativeSegments(picker, in: controls.modeBar)
        try verifyNativeSegments(controls.sectionBar.picker, in: controls.sectionBar)
        for (index, mode) in GlowAppearance.selectableCases.enumerated() {
            let previewMode = previewModes[(index + 1) % previewModes.count]
            activate((index + 1) % previewModes.count, in: picker)
            guard controls.preview.mode == previewMode, state.glowAppearance == (index == 0 ? saved : GlowAppearance.selectableCases[index - 1]) else {
                throw failure("Preview selection changed the live appearance")
            }
            state.phase = index.isMultiple(of: 2) ? .recording : .processing
            options[index].invoke()
            controls.refresh()
            guard state.glowAppearance == mode, AppState(preview: true).glowAppearance == mode,
                  controls.preview.mode == previewMode,
                  options.filter({ $0.state == .on }).map(\.title) == [mode.title] else {
                throw failure("Menu selection did not persist independently with one checkmark")
            }
            controls.showAPIKeys()
            controls.refresh()
            guard controls.modeBar.isHidden else { throw failure("The preview picker leaked into API keys") }
            controls.showModels()
            controls.refresh()
            guard controls.modeBar.isHidden else { throw failure("The preview picker leaked into Models") }
            controls.sidebar.selectAppearance()
            controls.refresh()
            let fixed = previewMode == .bezel || previewMode == .liquidGlass
            guard controls.controlsPanel.bounds.height == (fixed ? 60 : 340),
                  controls.adjustments.isHidden == fixed,
                  controls.sectionBar.isHidden == fixed,
                  controls.controlsPanel.bounds.contains(controls.modeBar.convert(controls.modeBar.bounds, to: controls.controlsPanel)) else {
                throw failure("The native capsule must fit inside the glass panel for every appearance")
            }
            if !fixed {
                let sectionPicker = controls.sectionBar.picker
                let modeCapsule = picker.convert(picker.bounds, to: controls.controlsPanel)
                let sectionCapsule = sectionPicker.convert(sectionPicker.bounds, to: controls.controlsPanel)
                let panel = controls.controlsPanel.bounds
                let cornerRadius: CGFloat = 30
                guard abs(modeCapsule.minX + modeCapsule.height / 2 - cornerRadius) < 0.75,
                      abs(sectionCapsule.maxX - sectionCapsule.height / 2 - (panel.maxX - cornerRadius)) < 0.75,
                      abs(modeCapsule.midY - (panel.maxY - cornerRadius)) < 0.75,
                      abs(sectionCapsule.midY - (panel.maxY - cornerRadius)) < 0.75 else {
                    throw failure("Native capsule ends must be concentric with the panel corners: modes \(modeCapsule), sections \(sectionCapsule), panel \(panel)")
                }
                let modes = controls.modeBar.convert(controls.modeBar.bounds, to: controls.controlsPanel)
                let sections = controls.sectionBar.convert(controls.sectionBar.bounds, to: controls.controlsPanel)
                guard abs(modes.midY - sections.midY) < 0.5,
                      sections.minX - modes.maxX >= 12,
                      controls.controlsPanel.bounds.contains(sections),
                      controls.controlsPanel.bounds.width == 500 else {
                    throw failure("The two capsule bars must sit side by side with a clear gap inside the wider panel")
                }
            }
            guard controls.preview.mode == previewMode, !controls.modeBar.isHidden, !controls.showingModels,
                  state.glowAppearance == mode else { throw failure("Settings navigation changed the active style or lost its preview") }
        }
        controls.selectPreview(.aroundNotch)
        controls.reveal(.intensity)
        let slider = controls.sliders[.intensity]!
        let savedStrength = state.glowStrength
        defer { state.glowStrength = savedStrength }
        slider.doubleValue = 0.91
        slider.sendAction(slider.action, to: slider.target)
        controls.selectPreview(.bottom)
        guard abs(state.glowStrength - 0.91) < 0.000001,
              abs(slider.doubleValue - 0.91) < 0.000001, state.glowAppearance == .liquidGlass,
              !window.isVisible else { throw failure("Shared settings or hidden preview isolation changed") }
        print("PASS: native capsule ends are concentric with the panel corners, both bars stay fixed across every mode transition, and preview segments remain independent of persisted menu selection; checkmarks, navigation and shared tuning agree.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AppearanceSelection", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func verifyStablePositions(_ controls: AppearanceWindowController) throws {
        let saved = controls.preview.mode
        defer { controls.selectPreview(saved) }
        controls.selectPreview(.bottom)
        func positions() -> [NSRect] {
            controls.window?.contentView?.layoutSubtreeIfNeeded()
            controls.modeBar.layoutSubtreeIfNeeded()
            controls.sectionBar.layoutSubtreeIfNeeded()
            let modes = controls.modeBar.picker
            let sections = controls.sectionBar.picker
            let panel = controls.controlsPanel.convert(controls.controlsPanel.bounds, to: nil)
            return [NSRect(x: panel.minX, y: panel.maxY, width: panel.width, height: 0),
                    modes.convert(modes.bounds, to: nil), sections.convert(sections.bounds, to: nil)]
        }
        let baseline = positions()
        for source in GlowAppearance.selectableCases {
            for target in GlowAppearance.selectableCases {
                controls.selectPreview(source)
                let picker = controls.modeBar.picker
                activate(AppearanceModeBar.modes.firstIndex(of: target)!, in: picker)
                let stable = target.isClassic ? Array(positions().prefix(2)) == Array(baseline.prefix(2)) : positions() == baseline
                guard stable, controls.sectionBar.isHidden == target.isClassic,
                      controls.preview.mode == target else {
                    throw failure("Switching \(source.rawValue) to \(target.rawValue) moved a capsule or its click targets: hidden=\(controls.sectionBar.isHidden), mode=\(controls.preview.mode), \(baseline) -> \(positions())")
                }
            }
        }
        print("PASS: all 25 appearance transitions retain identical header, capsule and item positions.")
    }

    private static func activate(_ index: Int, in picker: SettingsChoiceControl) {
        picker.selectedSegment = index
        picker.sendAction(picker.action, to: picker.target)
    }

    private static func verifyNativeSegments(_ picker: AppearanceIconGroup, in bar: NSView) throws {
        guard picker.action != nil, picker.target === picker, picker.superview === bar else {
            throw failure("Appearance choice actions must reach the preview controller")
        }
        for index in 0..<picker.segmentCount {
            guard picker.image(forSegment: index) != nil,
                  picker.toolTip(forSegment: index)?.isEmpty == false else {
                throw failure("Native segments need icons and accessible names")
            }
        }
        let selected = picker.selectedSegment
        defer { activate(selected, in: picker) }
        let next = (selected + 1) % picker.segmentCount
        activate(next, in: picker)
        guard picker.selectedSegment == next,
              (0..<picker.segmentCount).filter({ picker.isSelected(forSegment: $0) }) == [next] else {
            throw failure("Selection must activate exactly one native segment")
        }
        picker.performClick(nil)
        guard picker.selectedSegment == next else {
            throw failure("Activating the selected segment must keep it selected")
        }
    }
}
