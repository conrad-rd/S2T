import AppKit
import Combine
import S2TCore

/// An installed-model menu that refreshes in place when downloads finish, so unrelated drafts survive.
@MainActor final class LocalModelChoicePicker: NSPopUpButton {
    private let appState: AppState
    private let category: String
    private var subscription: AnyCancellable?
    var choose: ((String) -> Void)?
    var didRefresh: (() -> Void)?

    init(state: AppState, category: String) {
        appState = state
        self.category = category
        super.init(frame: .zero, pullsDown: false)
        SettingsFormStyle.menuPicker(self)
        setAccessibilityLabel("Model")
        refresh()
        subscription = state.localModels.$installed.combineLatest(state.localModels.$catalog)
            .dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
    }
    required init?(coder: NSCoder) { nil }

    var installed: [LocalModel] {
        appState.localModels.catalog.filter { $0.category == category && appState.localModels.installed.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func refresh() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, value: String?, detail: String = "", enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value
            item.isEnabled = enabled
            item.toolTip = detail.isEmpty ? nil : detail
            if !detail.isEmpty, #available(macOS 14.4, *) { item.subtitle = detail }
            menu.addItem(item)
        }
        let models = installed
        for model in models {
            let requirement = !appState.localModels.memoryFits(model) ? "Needs about " + model.memoryGB.formatted() + " GB of memory"
                : !model.isNative && !appState.localModels.supported ? "Needs Apple silicon and macOS 26" : nil
            add(model.name, value: "managed:" + model.id, detail: requirement ?? (model.isNative ? "Managed by macOS" : "Downloaded"), enabled: requirement == nil)
        }
        if models.isEmpty { add("No models installed", value: nil, enabled: false) }
        menu.addItem(.separator())
        add("Custom endpoint", value: "endpoint", detail: "Your own server, such as LM Studio or Ollama")
        add("Browse local models…", value: "browse")
        self.menu = menu
        let saved = appState.managedLocalModelID(for: category)
        let selected = saved.map { "managed:" + $0 } ?? "endpoint"
        if let item = menu.items.first(where: { $0.representedObject as? String == selected }) { select(item) }
        else {
            let name = saved.flatMap { id in appState.localModels.catalog.first { $0.id == id }?.name } ?? saved ?? "Choose a model…"
            let placeholder = NSMenuItem(title: name + " · Not installed", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.insertItem(placeholder, at: 0)
            select(placeholder)
        }
        didRefresh?()
    }

    func chooseSelected() {
        guard let value = selectedItem?.representedObject as? String else { refresh(); return }
        choose?(value)
    }
}

/// A native navigation row with a trailing summary and chevron, like System Settings.
@MainActor final class SettingsLinkRow: NSButton {
    private let summaryLabel = NSTextField(labelWithString: "")
    private var subscription: AnyCancellable?

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.setContentCompressionResistancePriority(.init(495), for: .horizontal)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        summaryLabel.lineBreakMode = .byTruncatingTail
        let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
        chevron.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        chevron.contentTintColor = .tertiaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let content = NSStackView(views: [icon, label, spacer, summaryLabel, chevron])
        content.spacing = 10
        content.alignment = .centerY
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        setAccessibilityLabel(title)
        toolTip = title
    }
    required init?(coder: NSCoder) { nil }

    var summary: String {
        get { summaryLabel.stringValue }
        set { summaryLabel.stringValue = newValue; setAccessibilityValueDescription(newValue) }
    }

    func observe(_ localModels: LocalModels) {
        summary = localModels.summary
        subscription = localModels.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak localModels] _ in
            guard let localModels else { return }
            self?.summary = localModels.summary
        }
    }

    /// The labels inside are decoration; the whole row is one button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }
}
