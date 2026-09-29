import AppKit
import Combine
import SwiftUI
import S2TCore

@MainActor private final class LocalModelCell: NSTableCellView {
    private let name = NSTextField(labelWithString: "")
    private let availability = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = .init("local.model")
        textField = name
        name.font = .systemFont(ofSize: 13, weight: .medium)
        availability.font = .systemFont(ofSize: 11)
        availability.setContentCompressionResistancePriority(.required, for: .horizontal)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for child in [name, availability] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
            child.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: availability.leadingAnchor, constant: -12),
            availability.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        ])
        updateColors()
    }
    required init?(coder: NSCoder) { nil }

    func configure(model: LocalModel, availability: String) {
        name.stringValue = model.name
        self.availability.stringValue = availability
        self.availability.toolTip = availability.hasSuffix("GB RAM") ? "Estimated memory required" : availability
        toolTip = model.name + "\n" + model.details + "\n" + availability
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { updateColors() } }

    private func updateColors() {
        let selected = backgroundStyle == .emphasized
        name.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        availability.textColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}

@MainActor final class LocalModelsPane: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let state: AppState
    let table = NSTableView()
    let searchField = NSSearchField()
    let appleSearchField = NSSearchField()
    let appleLanguagePicker = NSPopUpButton()
    let sortPicker = NSPopUpButton()
    let taskPicker = NSPopUpButton()
    let overviewGroup = SettingsGroup(grouped: true)
    /// Lists every model that can run right now, where it came from and its size, plus downloads in progress.
    let installedGroup = SettingsGroup(grouped: true)
    private(set) var installedRowIDs: [String] = []
    private(set) var removeButtons: [String: NSButton] = [:]
    private(set) var useButtons: [String: NSButton] = [:]
    private let storageLabel = NSTextField(wrappingLabelWithString: "")
    private let storageRow = NSStackView()
    /// Asks before moving a download to the Trash. Verification replaces it to avoid presenting alerts.
    var confirmRemoval: (LocalModel, @escaping (Bool) -> Void) -> Void = { _, _ in }
    let backButton = NSButton()
    let detailBackButton = NSButton()
    private(set) var overviewChooseButtons: [NSButton] = []
    private(set) var overviewStatus: [NSTextField] = []
    private var overviewViews: [NSView] = []
    private var catalogViews: [NSView] = []
    private var appleSection: NSView?
    private var detailViews: [NSView] = []
    private enum Page { case overview, catalog, model }
    private var page: Page = .overview
    var isBrowsing: Bool { page != .overview }
    var isShowingDetail: Bool { page == .model }
    private var listHeight: NSLayoutConstraint!
    let taskSelection = LocalTaskSelection(index: 0)
    private(set) var selectedCategory = "speech"
    private var listRows: [LocalModel] = []
    let detail = SettingsGroup()
    private(set) var comparison: NSHostingView<LocalModelComparison>?
    let compareButton = NSButton()
    private let cancel = NSButton()
    private let cancelRow = NSStackView()
    private var refreshing = false
    private var comparisonVisible = false
    private(set) var detailModelID: String?
    private var selectedID: String?
    private let status = NSTextField(wrappingLabelWithString: "")
    private var subscription: AnyCancellable?
    private var stateSubscription: AnyCancellable?
    private(set) var rows: [LocalModel] = []

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        confirmRemoval = { [weak self] model, completion in
            let alert = NSAlert()
            alert.messageText = "Remove " + model.name + "?"
            let size = self?.state.localModels.diskUsage[model.id] ?? self?.state.localModels.partial[model.id]
            alert.informativeText = "This moves " + (size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "its download") + " to the Trash. You can download it again later."
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].hasDestructiveAction = true
            if let window = self?.view.window {
                alert.beginSheetModal(for: window) { completion($0 == .alertFirstButtonReturn) }
            } else { completion(alert.runModal() == .alertFirstButtonReturn) }
        }
        stateSubscription = state.$phase.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        subscription = state.localModels.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let page = SettingsScrollView(frame: .zero)
        page.hasVerticalScroller = true
        page.automaticallyAdjustsContentInsets = false
        view = page
        let stack = SettingsDocumentStack()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.documentView = stack
        stack.widthAnchor.constraint(equalTo: page.contentView.widthAnchor).isActive = true
        taskSelection.onChange = { [weak self] index in
            self?.taskPicker.selectItem(at: index)
            self?.selectedCategory = ["speech", "text"][index]
            self?.searchField.stringValue = ""
            self?.refresh()
        }
        let installedHeading = Self.heading("On this Mac")
        stack.addArrangedSubview(installedHeading)
        stack.addArrangedSubview(installedGroup)
        storageLabel.font = .systemFont(ofSize: 11)
        storageLabel.textColor = .secondaryLabelColor
        let showFiles = NSButton(title: "Show in Finder", target: self, action: #selector(showFiles))
        showFiles.setAccessibilityLabel("Show S2T local model files in Finder")
        SettingsFormStyle.nativeAction(showFiles)
        storageRow.setViews([storageLabel, NSView(), showFiles], in: .leading)
        storageRow.alignment = .centerY
        storageRow.spacing = 8
        storageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(storageRow)
        let taskHeading = Self.heading("Browse models for")
        stack.addArrangedSubview(taskHeading)
        taskPicker.addItems(withTitles: LocalTaskSelection.titles)
        SettingsFormStyle.menuPicker(taskPicker)
        taskPicker.setAccessibilityLabel("Local model task")
        taskPicker.identifier = .init("models.local.task")
        taskPicker.target = self
        taskPicker.action = #selector(changeTask)
        for (index, title) in LocalTaskSelection.titles.enumerated() {
            let name = NSTextField(labelWithString: title)
            name.font = .systemFont(ofSize: 13, weight: .medium)
            let current = NSTextField(labelWithString: "Not using a local model")
            current.font = .systemFont(ofSize: 11)
            current.textColor = .secondaryLabelColor
            current.lineBreakMode = .byTruncatingTail
            current.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            overviewStatus.append(current)
            let labels = NSStackView(views: [name, current])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 3
            let choose = NSButton(title: "Browse", target: self, action: #selector(openCategory(_:)))
            choose.tag = index
            choose.setAccessibilityLabel("Browse local models for " + title)
            SettingsFormStyle.nativeAction(choose)
            overviewChooseButtons.append(choose)
            let row = NSStackView(views: [labels, NSView(), choose])
            row.alignment = .centerY
            row.spacing = 8
            overviewGroup.add(row)
            if index < LocalTaskSelection.titles.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                overviewGroup.add(divider)
            }
        }
        stack.addArrangedSubview(overviewGroup)
        overviewViews = [installedHeading, installedGroup, storageRow, taskHeading, overviewGroup]
        backButton.title = "Local models"
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.imagePosition = .imageLeading
        backButton.setAccessibilityLabel("Back to local models")
        backButton.target = self
        backButton.action = #selector(backToOverview)
        SettingsFormStyle.nativeAction(backButton)
        let backRow = NSStackView(views: [backButton, NSView()])
        backRow.alignment = .centerY
        stack.addArrangedSubview(backRow)
        catalogViews.append(backRow)
        detailBackButton.title = "All models"
        detailBackButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        detailBackButton.imagePosition = .imageLeading
        detailBackButton.setAccessibilityLabel("Back to local model list")
        detailBackButton.target = self
        detailBackButton.action = #selector(backToCatalog)
        SettingsFormStyle.nativeAction(detailBackButton)
        let detailBackRow = NSStackView(views: [detailBackButton, NSView()])
        detailBackRow.alignment = .centerY
        stack.addArrangedSubview(detailBackRow)
        detailViews.append(detailBackRow)
        let chart = NSHostingView(rootView: comparisonView())
        comparison = chart
        chart.sizingOptions = [.intrinsicContentSize]
        chart.setContentHuggingPriority(.required, for: .vertical)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(openTableSelection)
        table.rowHeight = 36
        table.headerView = nil
        table.allowsEmptySelection = false
        table.style = .inset
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let name = NSTableColumn(identifier: .init("name"))
        name.title = "Model"
        name.minWidth = 200
        table.addTableColumn(name)
        table.setAccessibilityLabel("Available local models")
        scroll.documentView = table
        searchField.placeholderString = "Find a local model"
        searchField.setAccessibilityLabel("Find a local model")
        searchField.target = self
        searchField.action = #selector(filterModels)
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .regular
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sortPicker.addItems(withTitles: ["Memory", "Download size", "Name"])
        SettingsFormStyle.menuPicker(sortPicker)
        sortPicker.setAccessibilityLabel("Sort local models")
        sortPicker.target = self
        sortPicker.action = #selector(filterModels)
        let sorting = NSStackView(views: [taskPicker, searchField, sortPicker])
        sorting.alignment = .centerY
        sorting.spacing = 8
        taskPicker.widthAnchor.constraint(equalToConstant: 132).isActive = true
        sortPicker.widthAnchor.constraint(equalToConstant: 112).isActive = true
        stack.addArrangedSubview(sorting)
        catalogViews.append(sorting)
        let appleHeading = NSTextField(labelWithString: "Apple Speech languages")
        appleHeading.font = .systemFont(ofSize: 12, weight: .semibold)
        appleHeading.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))
        appleSearchField.placeholderString = "Find a language"
        appleSearchField.setAccessibilityLabel("Find an Apple Speech language")
        appleSearchField.target = self
        appleSearchField.action = #selector(filterModels)
        appleSearchField.sendsSearchStringImmediately = true
        SettingsFormStyle.menuPicker(appleLanguagePicker)
        appleLanguagePicker.setAccessibilityLabel("Apple Speech language")
        appleLanguagePicker.target = self
        appleLanguagePicker.action = #selector(openAppleLanguage)
        let appleControls = NSStackView(views: [appleSearchField, appleLanguagePicker])
        appleControls.alignment = .centerY
        appleControls.spacing = 8
        appleLanguagePicker.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let appleSection = NSStackView(views: [appleHeading, appleControls])
        appleSection.orientation = .vertical
        appleSection.alignment = .leading
        appleSection.spacing = 6
        appleControls.widthAnchor.constraint(equalTo: appleSection.widthAnchor).isActive = true
        stack.addArrangedSubview(appleSection)
        catalogViews.append(appleSection)
        self.appleSection = appleSection
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)
        cancel.title = "Pause download"
        cancel.target = self
        cancel.action = #selector(cancelDownload)
        SettingsFormStyle.nativeAction(cancel)
        cancelRow.addArrangedSubview(cancel)
        cancelRow.addArrangedSubview(NSView())
        stack.addArrangedSubview(cancelRow)
        stack.addArrangedSubview(scroll)
        catalogViews.append(scroll)
        listHeight = scroll.heightAnchor.constraint(equalToConstant: 220)
        listHeight.isActive = true
        stack.addArrangedSubview(detail)
        detailViews.append(detail)
        compareButton.title = "Compare performance"
        compareButton.setAccessibilityLabel("Compare local model performance")
        compareButton.target = self
        compareButton.action = #selector(toggleComparison)
        SettingsFormStyle.nativeAction(compareButton)
        let comparisonRow = NSStackView(views: [compareButton, NSView()])
        comparisonRow.alignment = .centerY
        stack.addArrangedSubview(comparisonRow)
        detailViews.append(comparisonRow)
        stack.addArrangedSubview(chart)
        detailViews.append(chart)
        for child in stack.arrangedSubviews {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        updatePage(resetScroll: true)
        refresh()
    }

    func selectCategory(_ index: Int) {
        page = .catalog
        taskSelection.select(index)
        updatePage(resetScroll: true)
    }

    func showOverview() {
        page = .overview
        comparisonVisible = false
        compareButton.title = "Compare performance"
        compareButton.setAccessibilityLabel("Compare local model performance")
        updatePage(resetScroll: true)
    }

    @objc private func openCategory(_ sender: NSButton) { selectCategory(sender.tag) }
    @objc private func backToOverview() { showOverview() }
    @objc private func backToCatalog() {
        page = .catalog
        updatePage(resetScroll: true)
    }

    private func updatePage(resetScroll: Bool = false) {
        guard isViewLoaded else { return }
        for item in overviewViews { item.isHidden = page != .overview }
        for item in catalogViews { item.isHidden = page != .catalog }
        appleSection?.isHidden = page != .catalog || selectedCategory != "speech"
        for item in detailViews { item.isHidden = page != .model || (item === comparison && !comparisonVisible) }
        storageRow.isHidden = page != .overview || storageLabel.stringValue.isEmpty
        // The overview's installed list already shows download progress and a Pause button.
        status.isHidden = page == .overview || status.stringValue.isEmpty || status.stringValue == "Models run on this Mac after installation."
        cancelRow.isHidden = page == .overview || state.localModels.installing == nil
        if resetScroll, let page = view as? NSScrollView {
            page.contentView.scroll(to: .zero)
            page.reflectScrolledClipView(page.contentView)
        }
    }

    @objc private func filterModels() { refresh() }
    @objc private func changeTask() { taskSelection.select(taskPicker.indexOfSelectedItem) }

    func tableRow(for id: String) -> Int? { listRows.firstIndex { $0.id == id } }

    @objc private func openAppleLanguage() {
        guard let id = appleLanguagePicker.selectedItem?.representedObject as? String,
              state.localModels.catalog.contains(where: { $0.id == id && $0.isNative }) else { return }
        selectedID = id
        showDetails()
        page = .model
        updatePage(resetScroll: true)
    }

    @objc private func cancelDownload() { state.localModels.cancelInstall() }
    @objc private func toggleComparison() {
        comparisonVisible.toggle()
        comparison?.isHidden = !comparisonVisible
        compareButton.title = comparisonVisible ? "Hide comparison" : "Compare performance"
        compareButton.setAccessibilityLabel(compareButton.title + " of local models")
    }

    func refresh() {
        guard isViewLoaded else { return }
        for (index, category) in ["speech", "text"].enumerated() {
            let active = state.managedLocalModelID(for: category)
            if let active, let model = state.localModels.catalog.first(where: { $0.id == active }) {
                overviewStatus[index].stringValue = "Using " + model.name + (state.localModels.installed.contains(active) ? "" : " · Not installed")
            } else {
                let ready = state.localModels.catalog.filter { $0.category == category && state.localModels.installed.contains($0.id) }.count
                overviewStatus[index].stringValue = "Not using a local model" + (ready == 0 ? "" : " · \(ready) ready on this Mac")
            }
            overviewStatus[index].toolTip = overviewStatus[index].stringValue
        }
        refreshInstalledGroup()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let models = state.localModels.catalog.filter {
            $0.category == selectedCategory && ($0.isNative || query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.details.localizedCaseInsensitiveContains(query))
        }.sorted {
            if sortPicker.indexOfSelectedItem == 2 { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let a = sortPicker.indexOfSelectedItem == 1 ? $0.diskGB : $0.memoryGB
            let b = sortPicker.indexOfSelectedItem == 1 ? $1.diskGB : $1.memoryGB
            return a == b ? $0.name < $1.name : a < b
        }
        let other = models.filter { !$0.isNative }
        let appleQuery = appleSearchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apple = models.filter { $0.isNative && (appleQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(appleQuery) || $0.details.localizedCaseInsensitiveContains(appleQuery)) }
        rows = other + apple
        listRows = other
        appleLanguagePicker.removeAllItems()
        appleLanguagePicker.addItem(withTitle: apple.isEmpty ? "No matching languages" : "Choose a language")
        for model in apple.filter({ state.localModels.installed.contains($0.id) }) + apple.filter({ !state.localModels.installed.contains($0.id) }) {
            appleLanguagePicker.addItem(withTitle: model.name + (state.localModels.installed.contains(model.id) ? " · Installed" : ""))
            appleLanguagePicker.lastItem?.representedObject = model.id
        }
        appleLanguagePicker.isEnabled = !apple.isEmpty
        if let selectedID, let index = appleLanguagePicker.itemArray.firstIndex(where: { $0.representedObject as? String == selectedID }) {
            appleLanguagePicker.selectItem(at: index)
        }
        appleSection?.isHidden = page != .catalog || selectedCategory != "speech" || !models.contains(where: \.isNative)
        let contentHeight = CGFloat(20 + listRows.count * 38)
        listHeight.constant = min(300, max(160, contentHeight))
        status.stringValue = state.localModels.supported ? state.localModels.message : "These MLX models require Apple Silicon and macOS 26 or newer. Custom endpoints remain available in Models."
        status.isHidden = status.stringValue.isEmpty || status.stringValue == "Models run on this Mac after installation."
        cancelRow.isHidden = state.localModels.installing == nil
        if !rows.contains(where: { $0.id == selectedID }) { selectedID = rows.first?.id }
        refreshing = true
        table.reloadData()
        if let selectedID, let index = tableRow(for: selectedID) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        refreshing = false
        showDetails()
        updatePage()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { listRows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 36 }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let model = listRows[row]
        let active = state.managedLocalModelID(for: model.category) == model.id
        let installed = state.localModels.installed.contains(model.id)
        let availability = active ? "In use" : installed ? "Installed"
            : state.localModels.installing == model.id ? "Downloading…"
            : state.localModels.partial[model.id] != nil ? "Incomplete"
            : !state.localModels.memoryFits(model) ? "Too large for this Mac"
            : "~\(model.memoryGB.formatted()) GB RAM"
        let cell = tableView.makeView(withIdentifier: .init("local.model"), owner: self) as? LocalModelCell ?? LocalModelCell()
        cell.configure(model: model, availability: availability)
        return cell
    }

    private static func heading(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.setAccessibilityRole(NSAccessibility.Role(rawValue: "AXHeading"))
        return label
    }

    private static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

    private func activeCategories(for model: LocalModel) -> [String] {
        ["speech", "text"].filter { state.managedLocalModelID(for: $0) == model.id }
    }

    private var canChangeModels: Bool { !state.phase.busy && state.phase != .recording }

    private func refreshInstalledGroup() {
        for child in installedGroup.stack.arrangedSubviews {
            installedGroup.stack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        installedRowIDs = []
        removeButtons = [:]
        useButtons = [:]
        let local = state.localModels
        var rows: [NSView] = []
        if let id = local.installing, let model = local.catalog.first(where: { $0.id == id }) {
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.controlSize = .small
            let detail: String
            if let bytes = local.downloadedBytes, !model.isNative {
                let total = model.diskGB * 1_000_000_000
                bar.isIndeterminate = false
                bar.minValue = 0; bar.maxValue = 1
                bar.doubleValue = min(0.99, Double(bytes) / total)
                detail = "Downloading · \(Self.bytes(bytes)) of about \(Self.bytes(Int64(total)))"
            } else {
                bar.isIndeterminate = true
                bar.startAnimation(nil)
                detail = local.message
            }
            bar.setAccessibilityLabel("Download progress for " + model.name)
            let pause = NSButton(title: "Pause", target: self, action: #selector(cancelDownload))
            pause.setAccessibilityLabel("Pause downloading " + model.name)
            SettingsFormStyle.nativeAction(pause)
            rows.append(installedRow(id: model.id, title: model.name, detail: detail, progress: bar, trailing: [pause]))
        }
        for model in local.downloadedModels.sorted(by: { $0.name < $1.name }) + local.systemModels.sorted(by: { $0.name < $1.name }) {
            let active = activeCategories(for: model)
            var parts = [model.categoryTitle, model.isNative ? "Managed by macOS" : "Downloaded by S2T"]
            if !model.isNative { parts.append(local.diskUsage[model.id].map(Self.bytes) ?? "~\(model.diskGB.formatted()) GB") }
            var trailing: [NSView] = []
            if active.isEmpty {
                let use = NSButton(title: "Use", target: self, action: #selector(modelAction(_:)))
                use.identifier = .init(model.id)
                use.setAccessibilityLabel("Use " + model.name + " for " + model.categoryTitle.lowercased())
                let requirement = !local.memoryFits(model) ? "Needs \(model.memoryGB.formatted()) GB of memory."
                    : !model.isNative && !local.supported ? "Needs Apple silicon and macOS 26." : nil
                use.isEnabled = requirement == nil && canChangeModels
                use.toolTip = requirement
                SettingsFormStyle.nativeAction(use)
                useButtons[model.id] = use
                trailing.append(use)
            } else {
                let inUse = NSTextField(labelWithString: "In use")
                inUse.font = .systemFont(ofSize: 12, weight: .medium)
                inUse.textColor = .secondaryLabelColor
                trailing.append(inUse)
            }
            if !model.isNative { trailing.append(removeButton(for: model, inUse: !active.isEmpty)) }
            rows.append(installedRow(id: model.id, title: model.name, detail: parts.joined(separator: " · "), trailing: trailing))
        }
        for model in local.partialModels {
            let resume = NSButton(title: "Resume", target: self, action: #selector(modelAction(_:)))
            resume.identifier = .init(model.id)
            resume.setAccessibilityLabel("Resume downloading " + model.name)
            resume.isEnabled = local.installing == nil && local.supported && local.memoryFits(model) && canChangeModels
            SettingsFormStyle.nativeAction(resume)
            let detail = "Download incomplete · \(Self.bytes(local.partial[model.id] ?? 0)) of about \(model.diskGB.formatted()) GB"
            rows.append(installedRow(id: model.id, title: model.name, detail: detail, trailing: [resume, removeButton(for: model, inUse: false)]))
        }
        if rows.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: "Nothing is installed yet. Browse a task below to download a model that runs on this Mac, without an API key.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            rows.append(empty)
        }
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                installedGroup.add(divider)
            }
            installedGroup.add(row)
        }
        storageLabel.stringValue = local.totalBytes > 0
            ? "S2T's local model files use \(Self.bytes(local.totalBytes)), including the Python runtime." + (local.systemModels.isEmpty ? "" : " macOS stores Apple Speech languages separately.")
            : local.systemModels.isEmpty ? "" : "macOS stores Apple Speech languages outside S2T."
        storageRow.isHidden = page != .overview || storageLabel.stringValue.isEmpty
        storageRow.arrangedSubviews.last?.isHidden = local.totalBytes == 0
    }

    private func removeButton(for model: LocalModel, inUse: Bool) -> NSButton {
        let remove = NSButton(title: "Remove…", target: self, action: #selector(removeModel(_:)))
        remove.identifier = .init(model.id)
        remove.setAccessibilityLabel("Remove " + model.name)
        remove.isEnabled = !inUse && state.localModels.installing == nil && canChangeModels
        remove.toolTip = inUse ? "In use. Choose another model first." : "Move this download to the Trash."
        SettingsFormStyle.nativeAction(remove)
        removeButtons[model.id] = remove
        return remove
    }

    private func installedRow(id: String, title: String, detail: String, progress: NSProgressIndicator? = nil, trailing: [NSView]) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let info = NSTextField(wrappingLabelWithString: detail)
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(views: [name, info] + (progress.map { [$0] } ?? []))
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if let progress { progress.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true }
        let buttons = NSStackView(views: trailing)
        buttons.spacing = 8
        buttons.setContentCompressionResistancePriority(.required, for: .horizontal)
        buttons.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [labels, buttons])
        row.alignment = .centerY
        row.spacing = 12
        row.distribution = .fill
        row.setAccessibilityElement(false)
        installedRowIDs.append(id)
        return row
    }

    @objc private func removeModel(_ sender: NSButton) {
        guard let model = state.localModels.catalog.first(where: { $0.id == sender.identifier?.rawValue }),
              activeCategories(for: model).isEmpty else { return }
        confirmRemoval(model) { [weak self] confirmed in
            guard confirmed, let self, self.canChangeModels,
                  self.state.localModels.installing == nil, self.activeCategories(for: model).isEmpty else { return }
            do { try self.state.localModels.remove(model) }
            catch {
                let alert = NSAlert(error: error)
                if let window = self.view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            }
            self.refresh()
        }
    }

    @objc private func showFiles() {
        NSWorkspace.shared.activateFileViewerSelecting([state.localModels.root])
    }

    private func showDetails() {
        for child in detail.stack.arrangedSubviews {
            detail.stack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        comparison?.rootView = comparisonView()
        detailModelID = selectedID
        guard let model = rows.first(where: { $0.id == selectedID }) else {
            detail.add(NSTextField(wrappingLabelWithString: "No matching models. Try another search."))
            return
        }
        let title = NSTextField(labelWithString: model.name)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.toolTip = model.details
        let installed = state.localModels.installed.contains(model.id)
        let installing = state.localModels.installing == model.id
        let fits = state.localModels.memoryFits(model)
        let active = state.managedLocalModelID(for: model.category) == model.id
        let button = NSButton(title: installing ? "Downloading…" : installed ? (active ? "In use" : "Use") : state.localModels.partial[model.id] != nil ? "Resume download" : "Download", target: self, action: #selector(modelAction(_:)))
        button.identifier = .init(model.id)
        button.isEnabled = fits && (model.isNative || state.localModels.supported) && !active && !installing && (installed || state.localModels.installing == nil) && !state.phase.busy && state.phase != .recording
        SettingsFormStyle.nativeAction(button)
        let source = NSButton(title: "Details", target: self, action: #selector(openSource(_:)))
        SettingsFormStyle.nativeAction(source)
        source.identifier = .init(model.id)
        source.setAccessibilityLabel("Details for " + model.name)
        detail.add(title)
        let availabilityText = installed ? (model.isNative ? "Installed · Managed by macOS" : "Installed · " + (state.localModels.diskUsage[model.id].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + " on disk" } ?? "Downloaded by S2T"))
            : model.isNative ? "Not installed · Apple downloads this language through macOS" : "Not installed · ~\(model.diskGB.formatted()) GB download"
        let summary = NSTextField(wrappingLabelWithString: model.isNative ? availabilityText + " · No provider fees" : availabilityText + " · ~\(model.memoryGB.formatted()) GB RAM · No provider fees")
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.toolTip = model.details + " Hardware and electricity costs vary."
        detail.add(summary)
        let description = NSTextField(wrappingLabelWithString: model.details)
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        detail.add(description)
        let actions = NSStackView(views: [button, source])
        if installed && !model.isNative {
            let repair = NSButton(title: "Repair", target: self, action: #selector(repairModel(_:)))
            SettingsFormStyle.nativeAction(repair)
            repair.identifier = .init(model.id)
            repair.isEnabled = state.localModels.installing == nil && !state.phase.busy && state.phase != .recording
            actions.addArrangedSubview(repair)
        }
        actions.addArrangedSubview(NSView())
        actions.spacing = 8
        detail.add(actions)
        let requirement = !fits ? "Requires \(model.memoryGB.formatted()) GB of memory. Choose a smaller model for this Mac."
            : !model.isNative && !state.localModels.supported ? "Requires Apple silicon and macOS 26 or later." : nil
        if let requirement {
            let explanation = NSTextField(wrappingLabelWithString: requirement)
            explanation.font = .systemFont(ofSize: 12)
            explanation.textColor = .secondaryLabelColor
            detail.add(explanation)
            button.toolTip = requirement
            button.setAccessibilityHelp(requirement)
        }
    }

    private func comparisonView() -> LocalModelComparison {
        LocalModelComparison(models: state.localModels.catalog.filter { $0.category == selectedCategory }.sorted {
            $0.memoryGB == $1.memoryGB ? $0.name < $1.name : $0.memoryGB < $1.memoryGB
        }, selectedID: selectedID) { [weak self] id in
            guard let self, self.state.localModels.catalog.contains(where: { $0.id == id }) else { return }
            self.searchField.stringValue = ""
            self.selectedID = id
            self.refresh()
            if let index = self.tableRow(for: id) { self.table.scrollRowToVisible(index) }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) { openTableSelection() }

    @objc private func openTableSelection() {
        guard !refreshing, page == .catalog,
              listRows.indices.contains(table.selectedRow) else { return }
        let model = listRows[table.selectedRow]
        selectedID = model.id
        showDetails()
        page = .model
        updatePage(resetScroll: true)
    }

    @objc private func modelAction(_ sender: NSButton) {
        guard let model = state.localModels.catalog.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        if !state.localModels.installed.contains(model.id) { state.localModels.install(model) }
        else { state.localModels.use(model, state: state) }
        refresh()
    }
    @objc private func repairModel(_ sender: NSButton) {
        guard let model = state.localModels.catalog.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        state.localModels.repair(model)
    }
    @objc private func openSource(_ sender: NSButton) {
        guard let model = state.localModels.catalog.first(where: { $0.id == sender.identifier?.rawValue }) else { return }
        NSWorkspace.shared.open(URL(string: model.isNative ? "https://developer.apple.com/documentation/speech/speechtranscriber" : "https://huggingface.co/" + model.repository)!)
    }
}
