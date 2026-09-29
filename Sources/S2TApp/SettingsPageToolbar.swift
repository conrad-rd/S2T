import AppKit

/// Page actions live in the window toolbar. AppKit owns their layout and overflow.
@MainActor final class SettingsPageToolbar: NSObject, NSToolbarDelegate {
    enum Page {
        case dashboard, appearance, dictation, models, keys, meetings, recent
        var title: String {
            switch self {
            case .dashboard: "S2T"
            case .appearance: "Appearance"
            case .dictation: "Dictation"
            case .models: "Models"
            case .keys: "API keys"
            case .meetings: "Meetings"
            case .recent: "Recent recordings"
            }
        }
    }
    // Toolbars sharing an identifier mirror insertions across windows, which duplicates items when
    // verification opens several settings windows. Customization and autosave are off, so a unique name is safe.
    let toolbar = NSToolbar(identifier: "S2TPageToolbar-" + UUID().uuidString)
    weak var owner: AppearanceWindowController?
    private(set) var page = Page.appearance
    var title: String { page.title }
    private var items: [String: NSToolbarItem] = [:]
    private var itemSymbols: [String: String] = [:]

    override init() {
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        // The shared SwiftUI surface supplies one divider beneath the inset rail.
        toolbar.showsBaselineSeparator = false
    }

    func select(_ page: Page) { self.page = page; refresh() }

    /// Back navigation for sub-pages sits at the leading edge, before the flexible space.
    private var navigationActions: [String] {
        guard let owner else { return [] }
        switch page {
        case .models: return owner.modelsPane.navigation.onSubpage ? ["models.navigate"] : []
        case .dictation: return owner.dictationNavigation.page == nil ? [] : ["dictation.back"]
        default: return []
        }
    }
    var subpageTitle: String? {
        guard let owner else { return nil }
        switch page {
        case .models: return owner.modelsPane.navigation.onSubpage ? owner.modelsPane.navigation.pageTitle : nil
        case .dictation: return owner.dictationNavigation.page?.title
        default: return nil
        }
    }

    private var actions: [String] {
        switch page {
        case .dashboard: []
        case .appearance: ["appearance.use", "appearance.preview"]
        case .dictation: (owner?.state.canCancel == true ? ["dictation.cancel"] : []) + ["dictation.record"]
        case .models: ["models.refresh"]
        case .keys: (owner?.state.savedKeysLocked == true ? ["keys.unlock"] : []) + ["keys.paste"]
        case .meetings: ["meetings.options", "meetings.record"]
        case .recent: ["recent.search", "recent.copy"]
        }
    }
    private func identifier(_ action: String) -> NSToolbarItem.Identifier { .init("settings.toolbar." + action) }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        navigationActions.map(identifier) + [.flexibleSpace] + actions.map(identifier)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        navigationActions.map(identifier) + [.flexibleSpace] + actions.map(identifier)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let key = String(id.rawValue.dropFirst("settings.toolbar.".count))
        if let cached = items[key] { return cached }
        let item: NSToolbarItem
        switch key {
        case "appearance.preview":
            let names = ["Still preview", "Speaking preview", "Processing preview"]
            let images = zip(["pause", "waveform", "hourglass"], names).map {
                NSImage(systemSymbolName: $0, accessibilityDescription: $1)!
            }
            let picker = SettingsChoiceControl(items: zip(names, images).map { .init(title: $0, image: $1) }, label: "Preview state")
            picker.frame.size = picker.intrinsicContentSize
            picker.onSelection = { [weak self] index in self?.owner?.preview.phase = index }
            item = NSToolbarItem(itemIdentifier: id)
            item.view = picker
        case "keys.paste", "meetings.options":
            let menuItem = NSMenuToolbarItem(itemIdentifier: id)
            let menu = NSMenu()
            menu.autoenablesItems = false
            if key == "keys.paste" {
                for (name, account) in [("S2T", "s2t"), ("OpenRouter", "openrouter"), ("xAI", "xai"), ("AssemblyAI", "assemblyai"), ("TypeSafe", "typesafe")] {
                    let action = NSMenuItem(title: name, action: #selector(pasteKey(_:)), keyEquivalent: "")
                    action.target = self; action.representedObject = account; menu.addItem(action)
                }
            } else {
                for (index, title) in ["Microphone and Mac audio", "Microphone only", "Choose models"].enumerated() {
                    let action = NSMenuItem(title: title, action: #selector(meetingOption(_:)), keyEquivalent: "")
                    action.target = self; action.tag = index + 1; menu.addItem(action)
                }
                menu.item(at: 0)?.toolTip = "Use headphones to avoid recording an echo."
            }
            menuItem.menu = menu
            item = menuItem
        case "recent.search":
            let search = NSSearchToolbarItem(itemIdentifier: id)
            search.searchField.placeholderString = "Search recordings"
            search.searchField.setAccessibilityLabel("Search recordings")
            search.searchField.target = self
            search.searchField.action = #selector(searchRecordings(_:))
            search.searchField.sendsSearchStringImmediately = true
            item = search
        default:
            item = NSToolbarItem(itemIdentifier: id)
            item.target = self
            item.action = #selector(performAction(_:))
        }
        item.autovalidates = false
        item.isBordered = !(item.view is SettingsChoiceControl)
        items[key] = item
        update(item, key: key)
        return item
    }

    func refresh() {
        let leading = navigationActions.map(identifier)
        let desired = leading + actions.map(identifier)
        let current = toolbar.items.map(\.itemIdentifier).filter { $0.rawValue.hasPrefix("settings.toolbar.") }
        if current != desired {
            for index in toolbar.items.indices.reversed() where toolbar.items[index].itemIdentifier.rawValue.hasPrefix("settings.toolbar.") {
                toolbar.removeItem(at: index)
            }
            for (index, id) in leading.enumerated() { toolbar.insertItem(withItemIdentifier: id, at: index) }
            for id in actions.map(identifier) { toolbar.insertItem(withItemIdentifier: id, at: toolbar.items.count) }
        }
        if let owner, let window = owner.window, window.toolbar === toolbar, page == .models || page == .dictation {
            window.title = subpageTitle ?? page.title
        }
        for (key, item) in items { update(item, key: key) }
    }

    private func update(_ item: NSToolbarItem, key: String) {
        guard let owner else { return }
        var title = "", symbol = "", enabled = true
        switch key {
        case "appearance.use": title = "Use appearance"; symbol = "checkmark"; enabled = owner.state.glowAppearance != owner.preview.mode
        case "appearance.preview":
            title = "Preview state"
            (item.view as? SettingsChoiceControl)?.select(owner.preview.phase)
        case "dictation.cancel": title = "Cancel dictation"; symbol = "xmark"; enabled = owner.state.canCancel
        case "dictation.record":
            title = owner.state.phase == .recording ? "Finish dictation" : "Start dictation"
            symbol = owner.state.phase == .recording ? "stop.fill" : "mic"
            enabled = !owner.state.phase.busy && !owner.state.meetingRecordingActive
        case "models.navigate": title = "Back to Models"; symbol = "chevron.left"
        case "dictation.back": title = "Back to Dictation"; symbol = "chevron.left"
        case "models.refresh": title = "Refresh models"; symbol = "arrow.clockwise"
        case "keys.paste":
            title = "Paste API key"; symbol = "doc.on.clipboard"; enabled = !owner.state.savedKeysLocked
            for entry in (item as? NSMenuToolbarItem)?.menu.items ?? [] {
                if let account = entry.representedObject as? String { entry.isHidden = !owner.state.isProviderVisible(account) }
            }
        case "keys.unlock": title = "Unlock saved keys"; symbol = "lock.open"
        case "meetings.options":
            title = "Meeting options"; symbol = "ellipsis.circle"
            if let menu = (item as? NSMenuToolbarItem)?.menu {
                menu.item(withTag: 1)?.state = owner.state.meetings.includeMacAudio ? .on : .off
                menu.item(withTag: 2)?.state = owner.state.meetings.includeMacAudio ? .off : .on
                for tag in [1, 2] { menu.item(withTag: tag)?.isEnabled = !owner.state.meetings.isActive }
            }
        case "meetings.record":
            title = owner.state.meetings.starting ? "Cancel start" : owner.state.meetings.isActive ? "Stop recording" : "Record meeting"
            symbol = owner.state.meetings.isActive ? "stop.fill" : "record.circle"
            enabled = owner.state.meetings.isActive || !(owner.state.phase.busy || owner.state.phase == .recording || owner.state.phase == .monitoring)
        case "recent.search": title = "Search recordings"
        case "recent.copy": title = "Copy latest recording"; symbol = "doc.on.doc"; enabled = !owner.state.recentRecordings.entries.isEmpty
        default: break
        }
        if item.label != title { item.label = title }
        if item.paletteLabel != title { item.paletteLabel = title }
        if item.toolTip != title { item.toolTip = title }
        if item.isEnabled != enabled { item.isEnabled = enabled }
        if !symbol.isEmpty, item.image == nil || itemSymbols[key] != symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            itemSymbols[key] = symbol
        }
    }

    @objc private func performAction(_ sender: NSToolbarItem) {
        guard let owner else { return }
        switch sender.itemIdentifier.rawValue {
        case "settings.toolbar.appearance.use": owner.state.glowAppearance = owner.preview.mode
        case "settings.toolbar.dictation.cancel": owner.state.cancel()
        case "settings.toolbar.dictation.record": owner.state.toggleRecording()
        case "settings.toolbar.models.navigate": owner.modelsPane.navigation.back()
        case "settings.toolbar.dictation.back": owner.dictationNavigation.page = nil
        case "settings.toolbar.models.refresh": owner.modelsPane.loadCatalog(force: true); Task { await owner.state.refreshSpeechCatalog(force: true) }
        case "settings.toolbar.keys.unlock": owner.state.loadSavedKeys(allowInteraction: true)
        case "settings.toolbar.meetings.record":
            if owner.state.meetings.isActive { owner.state.meetings.stop() }
            else { owner.state.meetings.start(state: owner.state) }
        case "settings.toolbar.recent.copy":
            if let text = owner.state.recentRecordings.entries.first?.text { owner.state.copyText(text) }
        default: break
        }
        refresh()
    }
    @objc private func pasteKey(_ sender: NSMenuItem) {
        guard let owner, let id = sender.representedObject as? String, owner.state.isProviderVisible(id) else { return }
        owner.apiKeysPane.editing.paste(NSPasteboard.general.string(forType: .string), for: id)
        owner.apiKeysPane.editing.save(id)
    }
    @objc private func meetingOption(_ sender: NSMenuItem) {
        guard let owner else { return }
        switch sender.tag {
        case 1 where !owner.state.meetings.isActive: owner.state.meetings.includeMacAudio = true
        case 2 where !owner.state.meetings.isActive: owner.state.meetings.includeMacAudio = false
        case 3: owner.meetingsPane.navigation.showingModels = true
        default: break
        }
        refresh()
    }
    @objc private func searchRecordings(_ sender: NSSearchField) { owner?.recentFilter.query = sender.stringValue }
}
