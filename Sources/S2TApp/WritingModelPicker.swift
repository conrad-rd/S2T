import AppKit
import SwiftUI
import S2TCore

struct WritingModelChoice: Identifiable, Equatable {
    let provider: ProcessingProvider
    let model: String
    let title: String
    var host = ""
    var localURL: String?
    var detail = ""
    var id: String { provider.rawValue + "|" + model }
}

extension WritingEditor {
    var modelChoices: [WritingModelChoice] {
        if settings.usesCredits && state.isProviderVisible("s2t") { return creditModelChoices }
        var choices = ModelRecommendations.cleanup.map {
            WritingModelChoice(provider: .openRouter, model: $0.model, title: $0.title, host: $0.host, detail: $0.detail)
        }
        choices += state.routerTextModels.map { WritingModelChoice(provider: .openRouter, model: $0.id, title: $0.name) }
        choices.append(.init(provider: .codex, model: "default", title: "Codex default"))
        choices += catalog.filter { $0.visibility == "list" }.map { .init(provider: .codex, model: $0.slug, title: $0.display_name) }
        choices.append(.init(provider: .xai, model: "grok-4.6", title: "Grok 4.6"))
        choices += state.localModels.downloadedModels.filter { $0.category == "text" }.map {
            .init(provider: .local, model: $0.id, title: $0.name, localURL: LocalModels.managedEndpoint, detail: "Installed on this Mac")
        }
        for provider in ProcessingProvider.allCases {
            var saved = settings
            saved.funding = .personal
            saved.provider = provider.rawValue
            choices.append(.init(provider: provider, model: saved.model,
                title: saved.isCodex && saved.model == "default" ? "Codex default" : saved.model,
                host: saved.isOpenRouter ? saved.host : "", localURL: provider == .local ? saved.localURL : nil))
        }
        for favorite in favorites.sorted() {
            let parts = favorite.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let provider = ProcessingProvider(rawValue: parts[0]), provider.validModelID(parts[1]) else { continue }
            choices.append(.init(provider: provider, model: parts[1], title: parts[1]))
        }
        var seen = Set<String>()
        return choices.filter { state.isProviderVisible($0.provider.rawValue) && seen.insert($0.id).inserted }
    }
    var selectedModelID: String { settings.selectedProvider.rawValue + "|" + settings.model }
    var modelProviderVisible: Bool { (!settings.usesCredits || state.isProviderVisible("s2t")) && state.isProviderVisible(settings.selectedProvider.rawValue) }
    var selectedModelTitle: String { modelProviderVisible ? modelChoices.first { $0.id == selectedModelID }?.title ?? settings.model : "Current provider hidden" }

    func selectModel(_ choice: WritingModelChoice) {
        guard enabled, !busy, state.isProviderVisible(choice.provider.rawValue), choice.provider.validModelID(choice.model), canSelectModel(choice) else { return }
        var next = settings
        if !state.isProviderVisible("s2t") { next.funding = .personal }
        if next.usesCredits { next.creditSettings.provider = choice.provider.rawValue }
        else { next.provider = choice.provider.rawValue }
        if next.model != choice.model || (next.usesCredits && !state.supportsWritingCreditModel(provider: choice.provider, model: next.model, host: next.selectedHost)) {
            next.model = choice.model
            if next.isOpenRouter { next.selectedHost = choice.host }
        }
        if choice.provider == .local {
            let customURL = next.localURL == LocalModels.managedEndpoint ? nil : next.localURL
            next.localURL = choice.localURL ?? customURL ?? LocalEndpoint.defaultProcessingURL
        }
        settings = next
    }
}

private extension ProcessingProvider {
    var pickerSymbol: String {
        switch self {
        case .openRouter: "point.3.connected.trianglepath.dotted"
        case .codex: "terminal"
        case .xai: "xmark"
        case .local: "desktopcomputer"
        }
    }
    var pickerTitle: String { self == .local ? "Local" : self == .codex ? "Codex" : self == .xai ? "xAI" : "OpenRouter" }
}

struct WritingModelButton: View {
    @ObservedObject var editing: WritingEditor
    @ObservedObject var state: AppState
    @ObservedObject var localModels: LocalModels
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: editing.modelProviderVisible ? editing.settings.selectedProvider.pickerSymbol : "cpu")
                Text(editing.selectedModelTitle).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }.frame(maxWidth: 220)
        }
        .help("Choose writing model").accessibilityLabel("Writing model: " + editing.selectedModelTitle)
        .accessibilityIdentifier("writing.model.open").disabled(editing.busy || !editing.enabled)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            WritingModelPicker(editing: editing, choices: editing.modelChoices, close: { open = false })
                .frame(width: WritingModelPickerController.size.width, height: WritingModelPickerController.size.height)
        }
    }
}

private struct WritingModelPicker: NSViewControllerRepresentable {
    @ObservedObject var editing: WritingEditor
    let choices: [WritingModelChoice]
    let close: () -> Void
    func makeNSViewController(context: Context) -> WritingModelPickerController {
        WritingModelPickerController(editing: editing, choices: choices, close: close)
    }
    func updateNSViewController(_ controller: WritingModelPickerController, context: Context) {
        controller.configure(choices: choices)
    }
}

/// AppKit owns focus, table selection, scrolling and keyboard navigation inside the popover.
@MainActor final class WritingModelPickerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let size = NSSize(width: 360, height: 344)
    static let railWidth: CGFloat = 44
    let editing: WritingEditor
    let search = WritingModelSearchField()
    let table = WritingModelTable()
    private let close: () -> Void
    private var choices: [WritingModelChoice]
    private(set) var visibleChoices: [WritingModelChoice] = []
    private(set) var group: String
    private var rail: [WritingProviderButton] = []
    private let side = NSStackView()
    private let searchContainer = WritingSearchContainer()
    private let heading = NSTextField(labelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var favoritesSnapshot: Set<String> = []

    init(editing: WritingEditor, choices: [WritingModelChoice], close: @escaping () -> Void) {
        self.editing = editing; self.choices = choices; self.close = close
        group = editing.settings.selectedProvider.rawValue
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let surface = WritingModelPickerSurface(frame: NSRect(origin: .zero, size: Self.size))
        surface.searchField = search
        view = surface
        side.orientation = .vertical; side.spacing = 6; side.alignment = .centerX
        let providers: [ProcessingProvider] = [.openRouter, .codex, .xai, .local]
        let groups = [("favorites", "Favorites", "star.fill")] + providers.map { ($0.rawValue, $0.pickerTitle, $0.pickerSymbol) }
        for (id, title, symbol) in groups {
            let button = WritingProviderButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: #selector(changeGroup(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(id); button.toolTip = title
            button.setAccessibilityLabel(title); button.setAccessibilityIdentifier("writing.models." + id)
            button.isBordered = false; button.setButtonType(.toggle)
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            side.addArrangedSubview(button); rail.append(button)
        }
        search.placeholderString = "Search models…"; search.delegate = self
        search.font = .systemFont(ofSize: 12)
        search.isBezeled = false; search.drawsBackground = false; search.focusRingType = .none
        search.setAccessibilityIdentifier("writing.models.search")
        search.setAccessibilityLabel("Search all writing models")
        search.jump = { [weak self] index in self?.choose(index) }
        search.focusChanged = { [weak self] in self?.searchContainer.focused = $0 }
        searchContainer.addSubview(search); search.translatesAutoresizingMaskIntoConstraints = false
        let column = NSTableColumn(identifier: .init("model")); column.resizingMask = .autoresizingMask
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 34
        table.intercellSpacing = .zero; table.style = .plain; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.backgroundColor = .clear; table.dataSource = self; table.delegate = self
        table.focusRingType = .none
        table.target = self; table.action = #selector(activateRow)
        table.setAccessibilityLabel("Writing models"); table.setAccessibilityIdentifier("writing.models.list")
        table.setAccessibilityHelp("Use arrow keys and Return to select a model, or Command-1 through Command-9 to choose a visible row.")
        table.activate = { [weak self] in self?.choose(self?.table.selectedRow ?? -1) }
        table.dismiss = close
        table.jump = { [weak self] index in self?.choose(index) }
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        heading.font = .systemFont(ofSize: 10, weight: .medium); heading.textColor = .secondaryLabelColor
        heading.setAccessibilityIdentifier("writing.models.heading")
        empty.font = .systemFont(ofSize: 12); empty.textColor = .secondaryLabelColor
        empty.maximumNumberOfLines = 3; empty.alignment = .center
        let divider = NSBox(); divider.boxType = .separator
        for subview in [side, divider, searchContainer, heading, scroll, empty] {
            view.addSubview(subview); subview.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: view.leadingAnchor), side.widthAnchor.constraint(equalToConstant: Self.railWidth),
            side.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: side.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: view.topAnchor, constant: 8), divider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            searchContainer.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 10),
            searchContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 10), searchContainer.heightAnchor.constraint(equalToConstant: 28),
            search.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 7), search.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -5),
            search.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor), search.heightAnchor.constraint(equalToConstant: 20),
            heading.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 7),
            heading.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            heading.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 10), heading.heightAnchor.constraint(equalToConstant: 14),
            scroll.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            empty.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 18), empty.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -18),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        reload()
    }
    override func viewDidAppear() { super.viewDidAppear(); view.window?.makeFirstResponder(search) }
    func configure(choices: [WritingModelChoice]) {
        guard self.choices != choices || favoritesSnapshot != editing.favorites else { return }
        self.choices = choices
        if isViewLoaded { reload() }
    }
    func filter(_ query: String, group: String? = nil) {
        search.stringValue = query
        if let group { self.group = group }
        reload()
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func controlTextDidBeginEditing(_ obj: Notification) { searchContainer.focused = true }
    func controlTextDidEndEditing(_ obj: Notification) { searchContainer.focused = false }
    @objc private func changeGroup(_ sender: NSButton) { filter("", group: sender.identifier!.rawValue); view.window?.makeFirstResponder(search) }
    private func reload() {
        favoritesSnapshot = editing.favorites
        if !editing.state.isProviderVisible(group) { group = choices.first?.provider.rawValue ?? "favorites" }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleChoices = choices.filter { choice in
            if !query.isEmpty { return (choice.title + " " + choice.model + " " + choice.provider.pickerTitle).localizedCaseInsensitiveContains(query) }
            return group == "favorites" ? editing.favorites.contains(choice.id) : choice.provider.rawValue == group
        }
        if !query.isEmpty, let provider = ProcessingProvider(rawValue: group), provider.validModelID(query),
           editing.canSelectModel(.init(provider: provider, model: query, title: query)),
           !visibleChoices.contains(where: { $0.model == query && $0.provider == provider }) {
            visibleChoices.append(.init(provider: provider, model: query, title: query, detail: "Use custom model ID"))
        }
        rail.forEach {
            let id = $0.identifier?.rawValue ?? ""
            $0.isHidden = !editing.state.isProviderVisible(id) || (editing.settings.usesCredits && editing.state.isProviderVisible("s2t") && (id == "codex" || id == "local"))
            $0.state = id == group ? .on : .off; $0.needsDisplay = true
        }
        table.reloadData()
        let selected = visibleChoices.firstIndex { $0.id == editing.selectedModelID } ?? 0
        if !visibleChoices.isEmpty { table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false); table.scrollRowToVisible(selected) }
        heading.stringValue = !query.isEmpty ? "Search results" : group == "favorites" ? "Favorites" : ProcessingProvider(rawValue: group)?.pickerTitle ?? "Models"
        empty.isHidden = !visibleChoices.isEmpty
        empty.stringValue = group == "favorites" && query.isEmpty ? "Star a model to keep it here." : "No matching models."
    }
    private func subtitle(for choice: WritingModelChoice) -> String {
        let mixedProviders = group == "favorites" || !search.stringValue.isEmpty
        if mixedProviders { return choice.provider.pickerTitle }
        return choice.detail
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleChoices.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        subtitle(for: visibleChoices[row]).isEmpty ? 34 : 46
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = WritingModelRow()
        view.hovered = { [weak self] in
            guard let self, self.visibleChoices.indices.contains(row) else { return }
            self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let choice = visibleChoices[row]
        let title = NSTextField(labelWithString: choice.title)
        title.font = .systemFont(ofSize: 12, weight: .medium); title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSTextField(labelWithString: subtitle(for: choice))
        detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabelColor; detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(views: detail.stringValue.isEmpty ? [title] : [title, detail])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 2
        let selected = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Selected model")!)
        selected.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        selected.contentTintColor = .secondaryLabelColor; selected.isHidden = choice.id != editing.selectedModelID
        selected.setAccessibilityElement(!selected.isHidden)
        let star = NSButton(image: NSImage(systemSymbolName: editing.favorites.contains(choice.id) ? "star.fill" : "star", accessibilityDescription: "Favorite")!, target: self, action: #selector(favorite(_:)))
        star.isBordered = false; star.tag = row; star.controlSize = .small
        star.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        star.contentTintColor = editing.favorites.contains(choice.id) ? .systemYellow : .tertiaryLabelColor
        star.setAccessibilityLabel((editing.favorites.contains(choice.id) ? "Unfavorite " : "Favorite ") + choice.title)
        star.toolTip = star.accessibilityLabel()
        let cell = NSView(); cell.toolTip = choice.provider.pickerTitle + " · " + choice.model
        for v in [labels, selected, star] { cell.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), labels.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            labels.trailingAnchor.constraint(equalTo: selected.leadingAnchor, constant: -6),
            selected.trailingAnchor.constraint(equalTo: star.leadingAnchor, constant: -3), selected.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            selected.widthAnchor.constraint(equalToConstant: 12), selected.heightAnchor.constraint(equalToConstant: 12),
            star.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), star.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            star.widthAnchor.constraint(equalToConstant: 22), star.heightAnchor.constraint(equalToConstant: 26)
        ])
        return cell
    }
    @objc private func favorite(_ sender: NSButton) {
        guard visibleChoices.indices.contains(sender.tag) else { return }
        editing.toggleFavorite(visibleChoices[sender.tag].id); reload()
    }
    @objc private func activateRow() { choose(table.clickedRow) }
    func choose(_ index: Int) {
        guard visibleChoices.indices.contains(index), !editing.busy, editing.enabled else { return }
        editing.selectModel(visibleChoices[index]); close()
    }
    func move(_ offset: Int) {
        guard !visibleChoices.isEmpty else { return }
        let next = max(0, min(visibleChoices.count - 1, table.selectedRow + offset))
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false); table.scrollRowToVisible(next)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): move(1)
        case #selector(NSResponder.moveUp(_:)): move(-1)
        case #selector(NSResponder.insertNewline(_:)): choose(table.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }
}

private func writingModelJump(_ event: NSEvent, perform: ((Int) -> Void)?) -> Bool {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
          let characters = event.charactersIgnoringModifiers, let number = Int(characters), (1...9).contains(number) else { return false }
    perform?(number - 1); return true
}
final class WritingModelSearchField: NSSearchField {
    var jump: ((Int) -> Void)?
    var focusChanged: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        if focused { focusChanged?(true) }
        return focused
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { writingModelJump(event, perform: jump) || super.performKeyEquivalent(with: event) }
}
final class WritingModelTable: NSTableView {
    var activate: (() -> Void)?
    var dismiss: (() -> Void)?
    var jump: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { activate?() }
        else if event.keyCode == 53 { dismiss?() }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { writingModelJump(event, perform: jump) || super.performKeyEquivalent(with: event) }
}

/// A popover can inherit the I-beam from the editor beneath it. Own the arrow
/// over non-text regions, leaving the search field and its field editor native.
class WritingModelPickerSurface: NSView {
    weak var searchField: NSSearchField?
    var setArrowCursor: () -> Void = { NSCursor.arrow.set() }
    private var cursorTracking: [NSTrackingArea] = []
    private var trackedRegions: [NSRect] = []

    var arrowCursorRegions: [NSRect] {
        let area = visibleRect
        guard !area.isEmpty else { return [] }
        guard let searchField, searchField.isDescendant(of: self), !searchField.isHiddenOrHasHiddenAncestor else { return [area] }
        let searchArea = convert(searchField.bounds, from: searchField).intersection(area)
        guard !searchArea.isEmpty else { return [area] }
        return [
            NSRect(x: area.minX, y: area.minY, width: area.width, height: searchArea.minY - area.minY),
            NSRect(x: area.minX, y: searchArea.maxY, width: area.width, height: area.maxY - searchArea.maxY),
            NSRect(x: area.minX, y: searchArea.minY, width: searchArea.minX - area.minX, height: searchArea.height),
            NSRect(x: searchArea.maxX, y: searchArea.minY, width: area.maxX - searchArea.maxX, height: searchArea.height)
        ].filter { !$0.isEmpty }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for region in arrowCursorRegions { addCursorRect(region, cursor: .arrow) }
    }

    override func updateTrackingAreas() {
        cursorTracking.forEach(removeTrackingArea)
        trackedRegions = arrowCursorRegions
        cursorTracking = trackedRegions.map {
            NSTrackingArea(rect: $0, options: [.cursorUpdate, .activeInActiveApp], owner: self)
        }
        cursorTracking.forEach(addTrackingArea)
        super.updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        guard trackedRegions != arrowCursorRegions else { return }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if arrowCursorRegions.contains(where: { $0.contains(point) }) { setArrowCursor() }
        else { super.cursorUpdate(with: event) }
    }
}

/// Borderless native buttons retain keyboard traversal, focus and accessibility.
private final class WritingProviderButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    private var tracking: NSTrackingArea?
    private var hovering = false
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func viewDidMoveToWindow() { hovering = false; super.viewDidMoveToWindow(); needsDisplay = true }
    override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); needsDisplay = true; return result }
    override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); needsDisplay = true; return result }
    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        if selected || hovering || isHighlighted {
            NSColor.labelColor.withAlphaComponent(selected ? 0.10 : 0.05).setFill(); shape.fill()
        }
        if selected && NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.secondaryLabelColor.setStroke(); shape.lineWidth = 1; shape.stroke()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke(); shape.lineWidth = 1.5; shape.stroke()
        }
        let tint: NSColor = selected ? .labelColor : .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium).applying(.init(paletteColors: [tint]))
        if let symbol = image?.withSymbolConfiguration(configuration) {
            let scale = min(18 / symbol.size.width, 18 / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                                   width: size.width, height: size.height))
        }
    }
    override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 6, yRadius: 6).fill() }
}

private final class WritingSearchContainer: NSView {
    var focused = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.labelColor.withAlphaComponent(0.035).setFill(); path.fill()
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let stroke = focused ? NSColor.keyboardFocusIndicatorColor.withAlphaComponent(contrast ? 1 : 0.65) : NSColor.separatorColor
        stroke.setStroke(); path.lineWidth = focused && contrast ? 2 : 1; path.stroke()
    }
}

private final class WritingModelRow: NSTableRowView {
    var hovered: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered?() }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.08).setFill(); path.fill()
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.secondaryLabelColor.setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}
