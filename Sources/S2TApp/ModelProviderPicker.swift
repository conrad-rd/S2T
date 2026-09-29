import AppKit
import Combine
import S2TCore

@MainActor final class ModelProviderPicker: NSPopUpButton {
    private let appState: AppState
    private let category: String
    private let providers: [(String, String)]
    private let selectedProvider: () -> String
    private let changeProvider: (String) -> Void
    private let changed: () -> Void
    var currentValue: String {
        appState.usesCredits(for: category) ? "s2t" : selectedProvider()
    }

    init(state appState: AppState, category: String, providers: [(String, String)], selected: @escaping () -> String,
         change: @escaping (String) -> Void, changed: @escaping () -> Void) {
        self.appState = appState
        self.category = category
        self.providers = providers
        selectedProvider = selected
        changeProvider = change
        self.changed = changed
        super.init(frame: .zero, pullsDown: false)
        SettingsFormStyle.menuPicker(self)
        setAccessibilityLabel("Provider")
        target = self
        action = #selector(selectProvider)
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    /// Who runs the model and who pays: S2T credits, a personal account, or this Mac. Installed local
    /// models are chosen in the Model menu below, so this list stays short.
    func refresh() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, value: String, detail: String) {
            guard appState.isProviderVisible(value) else { return }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value
            item.toolTip = detail
            if #available(macOS 14.4, *) { item.subtitle = detail }
            menu.addItem(item)
        }
        add("S2T", value: "s2t", detail: "Pay with S2T credits")
        for (value, title) in providers where value != "local" {
            let name = value == "codex" ? "Codex" : value == "xai" ? "xAI" : title
            add(name, value: value, detail: value == "codex" ? "Uses your Codex login" : "Uses your " + name + " API key")
        }
        if appState.isProviderVisible("local") {
            menu.addItem(.separator())
            add("Local models", value: "local", detail: "Runs on this Mac or your own server")
        }
        self.menu = menu
        if let item = menu.items.first(where: { $0.representedObject as? String == currentValue }) { select(item) }
        else {
            let placeholder = NSMenuItem(title: appState.isProviderVisible(currentValue) ? "Choose a provider…" : "Current provider hidden", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.insertItem(placeholder, at: 0)
            select(placeholder)
        }
    }

    @objc private func selectProvider() {
        guard let value = selectedItem?.representedObject as? String else { return }
        choose(value)
    }

    func choose(_ value: String) {
        guard appState.isProviderVisible(value) else { refresh(); return }
        guard appState.chooseModelProvider(value, category: category, personal: providers.map(\.0), change: changeProvider) else { refresh(); return }
        changed()
    }

}

extension AppState {
    /// Switches one task's provider or local model; other tasks are untouched. `local` selects the Local models
    /// group, `managed:<id>` an installed model and `endpoint` the custom local endpoint.
    func chooseModelProvider(_ value: String, category: String, personal: [String], change: (String) -> Void) -> Bool {
        guard !phase.busy, phase != .recording else { return false }
        if value == "s2t", ["speech", "text"].contains(category) {
            let creditChoices = creditModels.filter { $0.operation == (category == "speech" ? "transcription" : "cleanup") && isProviderVisible($0.provider) }
            if let first = creditChoices.first {
                if category == "speech" {
                    if !creditChoices.contains(where: { $0.provider == creditSpeechProvider.rawValue && $0.model == creditTranscriptionModel }),
                       let provider = TranscriptionProvider(rawValue: first.provider) {
                        creditSpeechProvider = provider
                        creditTranscriptionModel = first.model
                    }
                } else if !creditChoices.contains(where: { $0.provider == creditCleanupProvider.rawValue && $0.model == creditCleanupModel && $0.host == creditCleanupHost }),
                          let provider = ProcessingProvider(rawValue: first.provider) {
                    creditCleanupProvider = provider
                    creditCleanupModel = first.model
                    creditCleanupHost = first.host
                }
            }
            setUsesCredits(true, for: category)
        } else if value == "local" {
            let local = category == "speech" ? transcriptionProvider == .local : processingProvider == .local
            // Returning to Local models keeps its saved installed model or custom endpoint.
            if local { setUsesCredits(false, for: category); return true }
            let usable = localModels.catalog.filter {
                $0.category == category && localModels.installed.contains($0.id) && localModels.memoryFits($0) && ($0.isNative || localModels.supported)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let first = usable.first { localModels.use(first, state: self) } else { selectLocalEndpoint(for: category) }
        } else if value.hasPrefix("managed:") {
            guard let model = localModels.catalog.first(where: { $0.id == String(value.dropFirst("managed:".count)) && $0.category == category }),
                  localModels.installed.contains(model.id), localModels.memoryFits(model),
                  model.isNative || localModels.supported else { return false }
            localModels.use(model, state: self)
        } else if value == "endpoint" { selectLocalEndpoint(for: category) }
        else if personal.contains(value) {
            setUsesCredits(false, for: category)
            change(value)
        }
        else { return false }
        return true
    }
}
