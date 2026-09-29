import AppKit

@MainActor enum SettingsTopBarProbe {
    static func run() throws {
        let controller = AppearanceWindowController(state: AppState(preview: true), presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        let toolbar = controller.pageToolbar.toolbar
        func item(_ id: String) throws -> NSToolbarItem {
            guard let item = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "settings.toolbar." + id }) else {
                throw failure("Missing toolbar item: \(id)")
            }
            return item
        }
        func perform(_ item: NSToolbarItem) throws {
            guard let action = item.action, NSApp.sendAction(action, to: item.target, from: item) else {
                throw failure("Toolbar action did not dispatch: \(item.label)")
            }
        }
        func check(_ title: String, pane: NSView) throws {
            window.contentView?.layoutSubtreeIfNeeded()
            guard window.toolbar === toolbar, window.toolbarStyle == .unified,
                  window.title == title, window.titleVisibility == .visible,
                  !pane.isHiddenOrHasHiddenAncestor else {
                throw failure("\(title) lost its standard window title, toolbar or page")
            }
            guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == "settings.page.title" }) else {
                throw failure("A custom title must not replace the native window title")
            }
            for action in toolbar.items where action.itemIdentifier.rawValue.hasPrefix("settings.toolbar.") {
                guard !(action.toolTip ?? "").isEmpty,
                      action is NSSearchToolbarItem || action is NSMenuToolbarItem || action.view == nil || action.view is NSSegmentedControl else {
                    throw failure("Toolbar controls must use native toolbar items and accessible names")
                }
            }
            guard !window.isVisible else { throw failure("Verification exposed its window") }
        }

        try check("Appearance", pane: controller.controlsPanel)
        let savedAppearance = controller.state.glowAppearance
        defer { controller.state.glowAppearance = savedAppearance }
        controller.selectPreview(.aroundNotch)
        let use = toolbar.items.first { $0.itemIdentifier.rawValue == "settings.toolbar.appearance.use" }!
        guard use.isEnabled else { throw failure("Appearance cannot apply the selected mode") }
        guard let apply = use.action, NSApp.sendAction(apply, to: use.target, from: use) else {
            throw failure("Appearance must use a standard toolbar action")
        }
        guard controller.state.glowAppearance == .aroundNotch else { throw failure("Appearance did not save the selected mode") }
        guard let phaseItem = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "settings.toolbar.appearance.preview" }),
              let phase = phaseItem.view as? NSSegmentedControl,
              phase.trackingMode == .selectOne,
              (0..<phase.segmentCount).map({ phase.toolTip(forSegment: $0) }) == ["Still preview", "Speaking preview", "Processing preview"],
              (0..<phase.segmentCount).allSatisfy({ phase.image(forSegment: $0) != nil }),
              let action = phase.action else {
            throw failure("Appearance preview needs the system toolbar picker with named icon segments")
        }
        for index in [2, 1, 0, 0] {
            phase.selectedSegment = index
            guard NSApp.sendAction(action, to: phase.target, from: phase),
                  controller.preview.phase == index,
                  (0..<3).filter({ phase.isSelected(forSegment: $0) }) == [index],
                  controller.state.glowAppearance == .aroundNotch else {
                throw failure("Preview selection must retain exactly one state without changing the saved appearance")
            }
        }
        controller.preview.phase = 1
        controller.pageToolbar.refresh()
        guard phase.selectedSegment == 1 else { throw failure("The native picker did not reflect the preview state") }

        controller.showDictation()
        try check("Dictation", pane: controller.dictationPane)
        _ = try item("dictation.record")
        func leadsToolbar(_ id: String) -> Bool {
            toolbar.items.first?.itemIdentifier.rawValue == "settings.toolbar." + id
        }
        guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == "settings.toolbar.dictation.back" }) else {
            throw failure("Dictation shows Back without a sub-page")
        }
        for page in [DictationNavigation.Page.prompt, .clipboard, .inputDetection, .advanced] {
            controller.dictationNavigation.page = page
            controller.pageToolbar.refresh()
            guard leadsToolbar("dictation.back"), window.title == page.title else {
                throw failure("Dictation sub-page \(page.title) needs a leading Back item and its own title")
            }
            try perform(try item("dictation.back"))
            guard controller.dictationNavigation.page == nil, window.title == "Dictation" else {
                throw failure("Back did not return to Dictation")
            }
        }
        controller.showModels()
        try check("Models", pane: controller.modelsPane.view)
        guard !toolbar.items.contains(where: { $0.itemIdentifier.rawValue == "settings.toolbar.models.navigate" }) else {
            throw failure("Models overview shows Back without a sub-page")
        }
        for open in [{ controller.modelsPane.navigation.select(.local) }, { controller.modelsPane.navigation.showComparison() }] {
            open()
            controller.pageToolbar.refresh()
            guard controller.modelsPane.navigation.onSubpage, leadsToolbar("models.navigate"),
                  window.title == controller.modelsPane.navigation.pageTitle else {
                throw failure("Model sub-pages need a leading Back item and their own title")
            }
            try perform(try item("models.navigate"))
            guard !controller.modelsPane.navigation.onSubpage, window.title == "Models" else {
                throw failure("Models overview did not return")
            }
        }
        controller.showAPIKeys()
        try check("API keys", pane: controller.apiKeysPane.view)
        let paste = try item("keys.paste") as! NSMenuToolbarItem
        guard paste.menu.items.count == 5 else { throw failure("API key provider choices are missing") }
        controller.showMeetings()
        try check("Meetings", pane: controller.meetingsPane.view)
        let options = try item("meetings.options") as! NSMenuToolbarItem
        let choice = options.menu.item(withTag: 3)!
        guard let action = choice.action,
              NSApp.sendAction(action, to: choice.target, from: choice),
              controller.meetingsPane.navigation.showingModels else { throw failure("Meeting model settings did not open") }
        controller.meetingsPane.navigation.showingModels = false
        controller.showRecentRecordings()
        try check("Recent recordings", pane: controller.recentRecordingsPane)
        let first = UUID(), second = UUID()
        controller.state.recentRecordings.record(id: first, text: "One example transcript", appName: "Editor", bundleID: nil)
        controller.state.recentRecordings.record(id: second, text: "Another transcript", appName: "Browser", bundleID: nil)
        let search = (try item("recent.search") as! NSSearchToolbarItem).searchField
        search.stringValue = "example"
        guard let action = search.action,
              NSApp.sendAction(action, to: search.target, from: search),
              controller.recentRecordingsPane.rootView.visibleEntries.map(\.id) == [first] else {
            throw failure("Search did not filter recordings")
        }
        controller.showWriting()
        guard window.toolbar === controller.writingPane.nativeToolbar.toolbar,
              controller.writingPane.nativeToolbar.toolbar.items.contains(where: { $0.view is NSSegmentedControl }),
              controller.writingPane.nativeToolbar.toolbar.items.filter({ $0 is NSMenuToolbarItem }).count == 2 else {
            throw failure("Writing lost its document and dictionary toolbar")
        }
        controller.showDashboard()
        guard window.toolbar === toolbar, toolbar.items.allSatisfy({ $0.itemIdentifier == .flexibleSpace }),
              window.title == "S2T", window.titleVisibility == .hidden, window.titlebarAppearsTransparent,
              !controller.dashboardPane.view.isHiddenOrHasHiddenAncestor,
              controller.windowSurface.separator.isHidden else {
            throw failure("Dashboard toolbar or page changed")
        }
        controller.sidebar.selectAppearance()
        try check("Appearance", pane: controller.controlsPanel)
        guard toolbar.items.contains(where: { $0 === phaseItem }), phase.selectedSegment == controller.preview.phase,
              !window.isVisible else { throw failure("Navigation lost the native picker or exposed the verification window") }
        guard window.styleMask.contains(.resizable) else { throw failure("Settings must support native resizing") }
        for size in [NSSize(width: 780, height: 720), NSSize(width: 1040, height: 860)] {
            window.setContentSize(size)
            controller.sidebar.selectAppearance()
            for theme in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: theme)
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                guard window.titlebarAppearsTransparent, controller.windowSurface.separator.isHidden else {
                    throw failure("The Appearance title and actions must float over the preview without a titlebar fill")
                }
            }
            for route in [controller.showDictation, controller.showAPIKeys, controller.showModels,
                          controller.showWriting, controller.showMeetings, controller.showRecentRecordings] {
                route()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                window.contentView?.layoutSubtreeIfNeeded()
                try checkContinuousTitlebar(controller, window: window)
                let detail = controller.splitController.splitViewItems[1].viewController.view
                let pages = detail.subviews.filter { !$0.isHidden }
                guard pages.count == 1, let page = pages.first,
                      page.bounds.width > 500, page.bounds.height > 450,
                      page.convert(page.bounds, to: nil).maxY <= window.contentLayoutRect.maxY + 1 else {
                    throw failure("Page overlaps the titlebar or clips at \(size): \(window.title), pages=\(pages.map { $0.frame }), layout=\(window.contentLayoutRect), split=\(controller.splitController.splitView.frame), detail=\(detail.frame)")
                }
                let normalButtons = try trafficLightFrames(controller, window: window)
                controller.showDashboard()
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                guard try trafficLightFrames(controller, window: window) == normalButtons,
                      window.titlebarAppearsTransparent, window.titleVisibility == .hidden,
                      toolbar.items.allSatisfy({ $0.itemIdentifier == .flexibleSpace }),
                      controller.windowSurface.separator.isHidden else {
                    throw failure("Home must retain the native traffic-light positions without adding visible toolbar content")
                }
            }
        }
        window.setContentSize(AppearanceWindowController.contentSize)
        controller.sidebar.selectAppearance()
        print("PASS: continuous full-width native titlebar, inset sidebar, native window titles, unified toolbar actions and menus, system search, Appearance preview, Writing documents and hidden navigation. No screen capture.")
    }

    private static func trafficLightFrames(_ controller: AppearanceWindowController, window: NSWindow) throws -> [NSRect] {
        let rail = controller.sidebar.background
        return try [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { kind in
            guard let button = window.standardWindowButton(kind), !button.isHiddenOrHasHiddenAncestor else {
                throw failure("A native window control is missing")
            }
            let frame = button.convert(button.bounds, to: rail)
            guard rail.bounds.insetBy(dx: 6, dy: 6).contains(frame) else {
                throw failure("A native window control touches the inset sidebar edge: \(frame)")
            }
            return frame
        }
    }

    private static func checkContinuousTitlebar(_ controller: AppearanceWindowController, window: NSWindow) throws {
        let split = controller.splitController.splitView
        let sidebar = controller.sidebar.view
        let detail = controller.splitController.splitViewItems[1].viewController.view
        guard split.dividerThickness == 0, split.dividerColor.alphaComponent == 0,
              abs(sidebar.convert(sidebar.bounds, to: nil).maxX - detail.convert(detail.bounds, to: nil).minX) < 0.01 else {
            throw failure("A visible divider or gap separates the floating sidebar from the page")
        }
        guard controller.splitController.splitViewItems[0].behavior == .default else {
            throw failure("The custom glass rail must not acquire a separate native sidebar material")
        }
        guard window.toolbar?.items.contains(where: { $0 is NSTrackingSeparatorToolbarItem }) == false else {
            throw failure("A tracking divider must not split the continuous toolbar")
        }
        let surface = controller.windowSurface!
        let line = surface.separator
        let lineFrame = line.convert(line.bounds, to: nil)
        let backgroundFrame = surface.background.convert(surface.background.bounds, to: nil)
        guard let lineIndex = surface.view.subviews.firstIndex(of: line),
              let splitIndex = surface.view.subviews.firstIndex(of: controller.splitController.view),
              lineIndex < splitIndex, !line.isHiddenOrHasHiddenAncestor,
              abs(lineFrame.minX) < 0.01,
              abs(lineFrame.maxX - window.contentLayoutRect.maxX) < 0.01,
              abs(lineFrame.minY - window.contentLayoutRect.maxY) < 0.01,
              lineFrame.height > 0, lineFrame.height <= 1,
              backgroundFrame.contains(window.contentLayoutRect),
              abs(backgroundFrame.maxY - window.frame.height) < 0.01,
              window.titlebarAppearsTransparent,
              window.titlebarSeparatorStyle == .none, window.toolbar?.showsBaselineSeparator == false else {
            throw failure("Settings need one system divider and a shared background beneath the full-height rail: \(lineFrame), \(backgroundFrame)")
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let rail = controller.sidebar.background
        let railFrame = rail.convert(rail.bounds, to: nil)
        guard abs(railFrame.minX - AppearanceSidebarController.inset) < 1,
              abs(railFrame.width - AppearanceSidebarController.width) < 1,
              railFrame.maxY > window.contentLayoutRect.maxY else {
            throw failure("The full-height inset glass sidebar moved below the native toolbar")
        }
        if #available(macOS 26.0, *) {
            let materials = descendants(controller.sidebar.view.superview!).filter { $0 is NSGlassEffectView }
            guard materials.count == 1 else { throw failure("The inset sidebar gained a second glass surface") }
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "SettingsTopBarProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
