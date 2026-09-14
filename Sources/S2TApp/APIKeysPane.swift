import AppKit
import Combine
import S2TCore

@MainActor final class APIKeysPane: NSViewController {
    let state: AppState
    private(set) var editors: [String: MenuValueEditor] = [:]
    let unlockButton = SettingsGlassButton(title: "Unlock saved keys…", target: nil, action: nil)
    private var subscription: AnyCancellable?

    init(state: AppState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
        subscription = state.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let scroll = SettingsGlassScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = true
        view = scroll
        let stack = SettingsDocumentStack()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        let heading = SettingsFormStyle.pageHeading("API keys")
        stack.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        let note = NSTextField(wrappingLabelWithString: "Connect the services you use. Your keys stay in macOS Keychain.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        unlockButton.target = self
        unlockButton.action = #selector(unlock)
        stack.addArrangedSubview(unlockButton)
        for account in APIAccount.allCases {
            let id = account.rawValue
            let card = SettingsGroup()
            card.identifier = NSUserInterfaceItemIdentifier("keys.group." + id)
            stack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
            let colors: [String: NSColor] = ["assemblyai": .systemBlue, "openrouter": .systemPurple, "cerebras": .systemOrange, "elevenlabs": .systemGray]
            let getKey = SettingsGlassButton(title: "Get API key", target: self, action: #selector(getAPIKey(_:)))
            getKey.identifier = NSUserInterfaceItemIdentifier(id)
            let title = SettingsHeading.make(account.title, symbol: id == "openrouter" ? "point.3.connected.trianglepath.dotted" : "waveform", color: colors[id] ?? .systemBlue)
            let header = NSStackView(views: [title, getKey])
            header.alignment = .centerY
            header.distribution = .fill
            header.spacing = 8
            card.add(header)
            let description = NSTextField(wrappingLabelWithString: id == "openrouter" ? "One key for speech to text, cleanup and Prompt vision." : id == "cerebras" ? "Text cleanup" : "Speech to text")
            description.font = .systemFont(ofSize: 12)
            description.textColor = .secondaryLabelColor
            card.add(description)
            let editor = MenuValueEditor(title: "API key", value: state.keyValue(id), secure: true,
                saved: state.savedKeyAccounts.contains(id), onPaste: { [weak self] value in
                    self?.setKey(value, account: id)
                }, onSave: { [weak self] value in
                    guard let self else { return "Settings closed." }
                    self.setKey(value, account: id)
                    self.state.saveAPIKey(account: id)
                    self.refresh()
                    return self.state.savedKeyAccounts.contains(id) ? nil : self.state.keyStatuses[id]?.message ?? "Could not save the key."
                })
            editor.identifier = NSUserInterfaceItemIdentifier("editor." + id)
            editor.useSettingsStyle()
            card.add(editor)
            editors[id] = editor

        }
        refresh()
    }

    func setKey(_ value: String, account: String) {
        guard state.keyValue(account) != value else { return }
        switch account {
        case "assemblyai": state.assemblyKey = value
        case "openrouter": state.routerKey = value
        case "cerebras": state.cerebrasKey = value
        case "elevenlabs": state.elevenLabsKey = value
        default: return
        }
    }

    func refresh() {
        guard isViewLoaded else { return }
        let enabled = !state.phase.busy && state.phase != .recording
        unlockButton.isHidden = !state.savedKeysLocked && state.clipboardMonitor.persistenceError == nil
        unlockButton.isEnabled = enabled
        for (id, editor) in editors {
            editor.field.stringValue = state.keyValue(id)
            let status = state.keyStatuses[id]
            let saved = state.savedKeyAccounts.contains(id)
            editor.setKeyStatus(status, saved: saved)
            editor.saveButton.title = status == .checking ? "Checking…" : status?.needsAttention == true ? "Save and retry" : saved ? "✓ Saved" : "Save API key"
            editor.setEnabled(enabled)
            editor.saveButton.attributedTitle = NSAttributedString(string: editor.saveButton.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
            ])
        }
    }
    @objc private func getAPIKey(_ sender: NSButton) {
        let addresses = [
            "assemblyai": "https://www.assemblyai.com/dashboard/signup",
            "openrouter": "https://openrouter.ai/settings/keys",
            "cerebras": "https://cloud.cerebras.ai/platform/",
            "elevenlabs": "https://elevenlabs.io/app/settings/api-keys"
        ]
        guard let id = sender.identifier?.rawValue, let address = addresses[id], let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func unlock() { state.loadSavedKeys(allowInteraction: true); refresh() }
}
