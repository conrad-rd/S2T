import AppKit
import Combine
import S2TCore

@MainActor final class WritingToolbar: NSObject, NSToolbarDelegate {
    let editing: WritingEditor
    let toolbar = NSToolbar(identifier: "S2TWritingToolbar")
    private var subscription: AnyCancellable?
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let identifiers = ["document", "preview", "find", "format", "options", "save"].map { NSToolbarItem.Identifier("writing." + $0) }

    init(editing: WritingEditor) {
        self.editing = editing
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        subscription = editing.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers + [.flexibleSpace] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [identifiers[0], .flexibleSpace] + identifiers.dropFirst()
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item: NSToolbarItem
        if id == identifiers[0] {
            let picker = SettingsChoiceControl(items: ["Instructions", "Dictionary"].map { .init(title: $0) }, label: "Document")
            picker.frame.size = picker.intrinsicContentSize
            picker.onSelection = { [weak self] index in
                guard let self, self.editing.suggestion == nil else { return }
                self.editing.selection = index == 0 ? .instructions : .dictionary
            }
            item = NSToolbarItem(itemIdentifier: id)
            item.view = picker
        } else if id == identifiers[3] || id == identifiers[4] {
            let menuItem = NSMenuToolbarItem(itemIdentifier: id)
            menuItem.showsIndicator = false
            let menu = NSMenu()
            menu.autoenablesItems = false
            if id == identifiers[3] {
                for (index, title) in ["Heading", "Bold", "Italic", "Inline code", "Link", "Bulleted list", "Numbered list"].enumerated() {
                    let action = NSMenuItem(title: title, action: #selector(format(_:)), keyEquivalent: "")
                    action.target = self; action.tag = index; menu.addItem(action)
                }
            } else {
                for (index, title) in ["Edit with AI", "Edit Markdown source", "Reload saved file…"].enumerated() {
                    let action = NSMenuItem(title: title, action: #selector(option(_:)), keyEquivalent: "")
                    action.target = self; action.tag = index; menu.addItem(action)
                }
            }
            menuItem.menu = menu
            item = menuItem
        } else {
            item = NSToolbarItem(itemIdentifier: id)
            item.target = self
            item.action = #selector(performAction(_:))
            item.autovalidates = false
        }
        item.isBordered = !(item.view is SettingsChoiceControl)
        item.autovalidates = false
        items[id] = item
        refresh()
        return item
    }

    func refresh() {
        let reviewing = editing.suggestion != nil
        let document = true
        let source = editing.selection == .instructions ? !editing.showingMarkdownPreview : editing.showingDictionaryMarkdown
        let labels = ["Document", source ? "Preview" : "Edit", "Find and replace", "Formatting", "Document options", reviewing ? "Apply and save" : "Save"]
        let symbols = ["doc", source ? "eye" : "pencil", "magnifyingglass", "textformat", "ellipsis", "checkmark"]
        for (index, id) in identifiers.enumerated() {
            guard let item = items[id] else { continue }
            item.label = labels[index]; item.toolTip = labels[index]
            item.paletteLabel = labels[index]
            if index != 0 { item.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: labels[index]) }
            item.isEnabled = document && editing.enabled
            if index == 0 { item.isEnabled = document && !reviewing }
            if index == 1 { item.isEnabled = document && !reviewing }
            if index == 2 || index == 3 {
                item.isEnabled = document && (reviewing ? editing.review == .suggestion && !editing.busy : source)
            }
            if index == 5 { item.isEnabled = document && editing.enabled && (!editing.busy && (reviewing || editing.dirty)) }
            (item.view as? SettingsChoiceControl)?.isEnabled = item.isEnabled
        }
        (items[identifiers[0]]?.view as? SettingsChoiceControl)?.select(editing.selection == .instructions ? 0 : 1)
        if let menu = (items[identifiers[4]] as? NSMenuToolbarItem)?.menu {
            menu.items[0].state = editing.showingAssistant ? .on : .off
            menu.items[0].isEnabled = true
            menu.items[1].isHidden = editing.selection != .dictionary
            menu.items[1].isEnabled = !reviewing
            menu.items[2].isEnabled = !reviewing && editing.enabled
        }
    }

    @objc private func performAction(_ sender: NSToolbarItem) {
        switch sender.itemIdentifier {
        case identifiers[1]:
            if editing.selection == .instructions { editing.showingMarkdownPreview.toggle() }
            else { editing.showingDictionaryMarkdown.toggle() }
        case identifiers[2]: (editing.suggestion == nil ? editing.document : editing.suggestionDocument).find()
        case identifiers[5]: if editing.suggestion != nil { editing.applySuggestion() } else { editing.save() }
        default: break
        }
    }
    @objc private func format(_ sender: NSMenuItem) {
        let document = editing.suggestion == nil ? editing.document : editing.suggestionDocument
        switch sender.tag {
        case 0: document.format(.heading)
        case 1: document.format(.bold)
        case 2: document.format(.italic)
        case 3: document.format(.inlineCode)
        case 4: document.format(.link)
        case 5: document.format(.bulletList)
        case 6: document.format(.numberedList)
        default: break
        }
    }
    @objc private func option(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: editing.showingAssistant.toggle()
        case 1: editing.showingDictionaryMarkdown = true
        case 2: if editing.dirty { editing.confirmReload = true } else { editing.reload() }
        default: break
        }
    }
}
