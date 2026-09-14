import AppKit
import Combine
import S2TCore

@MainActor final class MenuBarController: NSObject, NSMenuDelegate {
    let state: AppState
    let statusItem: NSStatusItem
    let menu = NSMenu(title: "S2T")
    private var subscriptions = Set<AnyCancellable>()
    private(set) lazy var appearanceWindow = AppearanceWindowController(state: state, presentsWindows: presentsAppearanceWindow)
    private let presentsAppearanceWindow: Bool
    private var rootTitles: [ObjectIdentifier: (text: String, symbol: String)] = [:]
    private var appliedAppearance: String?
    private var refreshPending = false
    private var openMenus = Set<ObjectIdentifier>()
    private weak var processingModelEditor: MenuValueEditor?
    private weak var hostingEndpointEditor: MenuValueEditor?
    private var displayedProcessingModel: String?
    private var displayedHostingEndpoint: String?
    private weak var clipboardHistoryView: ClipboardHistoryView?
    private var processingEditors: [NSMenuItem] = []
    private var transcriptionEditors: [NSMenuItem] = []
    private var builders: [ObjectIdentifier: (NSMenu) -> Void] = [:]

    init(state: AppState, presentsAppearanceWindow: Bool = true) {
        self.state = state
        self.presentsAppearanceWindow = presentsAppearanceWindow
        statusItem = NSStatusBar.system.statusItem(withLength: MenuBarArtwork.size.width)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = MenuBarArtwork.image()
        statusItem.button?.imageScaling = .scaleNone
        statusItem.button?.setAccessibilityIdentifier("s2t.status")
        state.objectWillChange.sink { [weak self] in
            guard let self, !self.refreshPending else { return }
            self.refreshPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.refreshPending else { return }
                self.refreshStatus()
            }
        }.store(in: &subscriptions)
        refreshStatus()
    }

    func refreshStatus() {
        refreshPending = false
        let label = state.isCapturingShortcut ? "Press a key or combination. Escape cancels." : statusMessage ?? state.phase.label
        statusItem.button?.toolTip = "S2T · \(label)"
        statusItem.button?.setAccessibilityLabel("S2T, \(label)")
        statusItem.length = state.isCapturingShortcut ? 170 : MenuBarArtwork.size.width
        statusItem.button?.title = state.isCapturingShortcut ? " Press a key…" : ""
        statusItem.button?.contentTintColor = state.phase == .recording ? .systemRed : state.phase.busy ? .controlAccentColor : nil
        refreshItems(menu)
        if displayedProcessingModel != state.processingModel {
            processingModelEditor?.field.stringValue = state.processingModel
            displayedProcessingModel = state.processingModel
        }
        if displayedHostingEndpoint != state.routerEndpoint {
            hostingEndpointEditor?.field.stringValue = state.routerEndpoint
            displayedHostingEndpoint = state.routerEndpoint
        }
        clipboardHistoryView?.update(entries: state.clipboardMonitor.entries, enabled: state.clipboardContextEnabled)
        guard appliedAppearance != state.menuAppearance else { return }
        appliedAppearance = state.menuAppearance
        switch state.menuAppearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func showMenu() { statusItem.button?.performClick(nil) }
    func dismissMenu() { menu.cancelTracking() }

    func menuWillOpen(_ menu: NSMenu) {
        openMenus.insert(ObjectIdentifier(menu))
        TextInsertion.menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        openMenus.remove(ObjectIdentifier(menu))
        TextInsertion.menuIsOpen = !openMenus.isEmpty
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu {
            rootTitles.removeAll()
            builders.removeAll()
            processingEditors.removeAll()
            transcriptionEditors.removeAll()
            menu.removeAllItems()
            buildRoot(menu)
        } else if let build = builders[ObjectIdentifier(menu)] {
            menu.removeAllItems()
            build(menu)
        }
        refreshItems(menu)
    }

    private var statusMessage: String? { state.errorMessage ?? state.clipboardMonitor.persistenceError ?? state.notice }

    private var canConfigure: Bool { !state.phase.busy && state.phase != .recording }

    private func buildRoot(_ menu: NSMenu) {
        submenu("Set up dictation", id: "setup", in: menu) { [weak self] menu in self?.buildSetup(menu) }
        info(state.phase.label, in: menu, id: "status.phase")
        action(state.phase == .recording ? "Finish dictation" : "Start dictation", id: "dictation.toggle", in: menu, enabled: !state.phase.busy) { [weak self] in
            guard let self else { return }
            self.state.toggleRecording()

        }
        action("Cancel dictation", id: "dictation.cancel", in: menu, enabled: state.canCancel) { [weak self] in self?.state.cancel() }
        info("Add your keys under Settings → API keys to begin.", in: menu, id: "status.keys")
        submenu("Last dictation", id: "result", in: menu) { [weak self] menu in self?.buildResult(menu) }
        submenu("Clipboard history", id: "clipboard.history", in: menu) { [weak self] menu in self?.buildClipboardHistory(menu) }
        menu.addItem(.separator())
        submenu("Prompt mode · Experimental beta", id: "prompt", in: menu) { [weak self] menu in self?.buildPromptMode(menu) }
        submenu("Dictation settings", id: "dictation", in: menu) { [weak self] menu in self?.buildDictation(menu) }
        let settings = action("Settings…", id: "appearance", in: menu) { [weak self] in self?.appearanceWindow.show() }
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        submenu(statusMessage != nil ? "Needs attention" : "Status", id: "notice", in: menu) { [weak self] menu in
            guard let self else { return }
            self.message(self.statusMessage ?? self.state.phase.label, in: menu, id: "status.message")
            self.action("Dismiss message", id: "notice.dismiss", in: menu) { [weak self] in self?.state.errorMessage = nil; self?.state.notice = nil }
        }
        menu.addItem(.separator())
        action("Quit S2T", id: "quit", in: menu) { NSApp.terminate(nil) }
    }

    private func buildPromptMode(_ menu: NSMenu) {
        action("Enable Prompt mode", id: "prompt.enabled", in: menu, checked: state.promptModeEnabled, enabled: canConfigure) { [weak self] in self?.state.promptModeEnabled.toggle() }
        submenu("Activation key · \(state.promptShortcutKey.displayName)", id: "prompt.activation", in: menu) { [weak self] menu in self?.buildPromptActivation(menu) }
        action("Start prompt dictation", id: "prompt.start", in: menu, enabled: canConfigure && state.promptModeEnabled) { [weak self] in self?.state.toggleRecording(prompt: true) }
        message("Experimental beta. While dictating, point and say 'here', 'like here', 'look at this', or 'check this out'. Records the entire display and extracts screenshots at the time of each spoken reference.", in: menu)
        message("While you dictate, Prompt mode records full-screen frames in memory only. It discards the temporary recording after extracting reference screenshots, or when cancelled. No screen-recording file is saved. It matches references to the final transcript, then pastes the selected screenshots with short notes. Selected images and dictation go to your chosen image provider. Local endpoint uses your server; OpenRouter and Codex use cloud inference.", in: menu)
        action(state.promptSetupTitle, id: "prompt.setup", in: menu, enabled: canConfigure) { [weak self] in self?.state.setUpPromptMode() }
        submenu("Reference language", id: "prompt.language", in: menu) { [weak self] menu in
            guard let self else { return }
            for (locale, title) in [("en-US", "English"), ("de-DE", "German")] {
                self.action(title, id: "prompt.locale." + locale, in: menu, checked: self.state.promptLanguage == locale, enabled: self.canConfigure) { [weak self] in self?.state.promptLanguage = locale }
            }
            self.message("Detection runs on device while you speak. Recognition delay and missed phrases are possible. German examples: 'schau mal hier', 'schau dir das an'.", in: menu)
        }
        submenu("Image model · \(state.promptVisionProvider.title)", id: "prompt.model", in: menu) { [weak self] menu in
            self?.buildVisionModel(menu)
        }
        menu.addItem(.separator())
        message(state.promptStatus, in: menu, id: "prompt.status")
        submenu("Reference images", id: "prompt.images", in: menu) { [weak self] menu in self?.buildPromptImages(menu) }
    }

    private func buildVisionModel(_ menu: NSMenu) {
        let provider = state.promptVisionProvider
        for option in VisionProvider.allCases {
            action(option.title, id: "visionProvider." + option.rawValue, in: menu, checked: provider == option, enabled: canConfigure) { [weak self] in self?.state.promptVisionProvider = option }
        }
        menu.addItem(.separator())
        if provider == .local {
            let editor = MenuValueEditor(title: "Image endpoint URL", value: state.localVisionURL, secure: false, enabled: canConfigure, onPaste: { _ in }) { [weak self] value in
                guard let self, self.canConfigure, self.state.promptVisionProvider == provider else { return "Reopen Image model before saving." }
                do { self.state.localVisionURL = try LocalEndpoint.url(value).absoluteString; return nil }
                catch { return error.localizedDescription }
            }
            editor.identifier = NSUserInterfaceItemIdentifier("local.vision.url")
            custom(editor, in: menu)
            message("Load an image-capable model on your OpenAI-compatible server. Images go only to this endpoint, without API keys or cloud fallback. Image capability is checked when a reference is described.", in: menu)
        }
        if provider == .codex { codexSettings(in: menu) }
        let editor = MenuValueEditor(title: "Image-capable model ID", value: state.promptVisionModel, secure: false, enabled: canConfigure, onPaste: { _ in }) { [weak self] value in
            guard let self, self.canConfigure, self.state.promptVisionProvider == provider else { return "Provider changed. Reopen Image model before saving." }
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard provider.validModelID(value) else { return "Enter a valid image model ID." }
            self.state.promptVisionModel = value
            return nil
        }
        editor.identifier = NSUserInterfaceItemIdentifier("vision.model")
        editor.validateValue = { [weak self] value in
            guard let self, self.state.promptVisionProvider == provider else { return "Provider changed. Reopen Image model before saving." }
            return await self.state.validatePromptVisionModel(value)
        }
        custom(editor, in: menu)
        if provider == .openRouter { message("Uses the saved OpenRouter key. Image support is verified before saving and sending. Your text-cleanup model stays separate.", in: menu) }
    }

    private func codexSettings(in menu: NSMenu) {
        let editor = MenuValueEditor(title: "Codex executable path · blank for automatic", value: state.codexExecutable, secure: false, enabled: canConfigure, onPaste: { _ in }) { [weak self] value in
            guard let self, self.canConfigure else { return "Finish dictation before saving." }
            let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.isEmpty || CodexCLI.executableURL(path) != nil else { return "Choose an executable Codex CLI file." }
            self.state.codexExecutable = path
            return nil
        }
        editor.identifier = NSUserInterfaceItemIdentifier("codex.executable")
        custom(editor, in: menu)
        message("Uses your Codex login and OpenAI cloud inference. Run codex login once in Terminal. Use default for the CLI's default model, or enter a model ID. Text and image models stay separate.", in: menu)
        action("Codex setup instructions…", id: "codex.help", in: menu) { NSWorkspace.shared.open(URL(string: "https://developers.openai.com/codex/cli")!) }
    }

    private func buildPromptActivation(_ menu: NSMenu) {
        info("Current key: \(state.promptShortcutKey.displayName)", in: menu, id: "prompt.shortcut.current")
        action("Record custom key…", id: "prompt.shortcut.record", in: menu, enabled: canConfigure && state.shortcutAccessGranted) { [weak self] in
            DispatchQueue.main.async { self?.state.beginPromptShortcutCapture?() }
        }
        action("Use Right Command", id: "prompt.shortcut.default", in: menu, checked: state.promptShortcutKey == .rightCommand, enabled: canConfigure) { [weak self] in self?.state.saveShortcut(.rightCommand, prompt: true) }
        menu.addItem(.separator())
        action("Hold to talk", id: "prompt.shortcut.hold", in: menu, checked: state.promptHoldEnabled, enabled: canConfigure) { [weak self] in self?.state.promptHoldEnabled.toggle() }
        action("Tap to toggle", id: "prompt.shortcut.tap", in: menu, checked: state.promptTapEnabled, enabled: canConfigure) { [weak self] in self?.state.promptTapEnabled.toggle() }
        message("This shortcut starts Prompt mode. Your normal dictation key stays separate. Command combinations still work; another key cancels a held prompt recording.", in: menu)
        message("", in: menu, id: "prompt.shortcut.conflict")
    }

    private func buildPromptImages(_ menu: NSMenu) {
        action("Reveal saved references in Finder", id: "prompt.saved", in: menu) { [weak self] in self?.state.revealSavedPromptReferences() }
        menu.addItem(.separator())
        if state.promptImages.isEmpty { info("No reference images available for the last prompt", in: menu) }
        else {
            action("Reveal images in Finder", id: "prompt.reveal", in: menu) { [weak self] in self?.state.revealPromptImages() }
            for url in state.promptImages {
                action("Copy " + url.lastPathComponent, id: "prompt.copy." + url.lastPathComponent, in: menu) { [weak self] in self?.state.copyPromptImage(url) }
            }
            message("Screenshots paste automatically after the prompt. If your app doesn't accept them, attach these saved files manually. Each filename matches a reference in the text.", in: menu)
        }
    }

    private func buildSetup(_ menu: NSMenu) {
        message(state.setupSummary, in: menu, id: "setup.summary")
        action("Open Applications…", id: "setup.install", in: menu) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
        info("Microphone · Not allowed", in: menu, id: "setup.microphone")
        info("Accessibility · Not allowed", in: menu, id: "setup.accessibility")
        action(state.permissionActionTitle, id: "permissions.setup", in: menu) { [weak self] in self?.state.setUpDictation() }
        menu.addItem(.separator())
        action("Open Settings…", id: "setup.keys", in: menu) { [weak self] in self?.appearanceWindow.showAPIKeys() }
        action("Use Verbatim · Skip text cleanup", id: "setup.verbatim", in: menu) { [weak self] in self?.state.mode = .verbatim }
        menu.addItem(.separator())
        submenu("Activation key", id: "setup.activation", in: menu) { [weak self] menu in self?.buildActivation(menu) }
        action("Test shortcut", id: "setup.test", in: menu) { [weak self] in
            guard let self else { return }
            if self.state.shortcutTestActive { self.state.stopShortcutTest?() }
            else { self.state.testShortcut?() }
        }
        message(state.shortcutTestStatus, in: menu, id: "setup.testStatus")
        submenu("Fix Fn", id: "setup.fn", in: menu) { [weak self] menu in
            guard let self else { return }
            self.message("If Fn also opens emoji or dictation, open Keyboard settings and set 'Press Fn key to' or 'Press Globe key to' to 'Do Nothing'. Then test again.", in: menu)
            self.action("Open Keyboard settings…", id: "shortcut.keyboard", in: menu) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            self.action("Retry automatic Fn setup", id: "shortcut.repair", in: menu) { [weak self] in self?.state.repairFnShortcut?() }
            self.message("S2T restores your previous Fn setting when you quit. Other Fn combinations remain available.", in: menu)
        }
        action("Test microphone", id: "microphone.test", in: menu) { [weak self] in self?.state.testMicrophone() }
        menu.addItem(.separator())
        message("Try a short dictation in a text field. Hold your key to speak, then release. Or tap to start and tap again to finish. Last dictation keeps the result.", in: menu)
        menu.addItem(.separator())
        info(BuildIdentity.menuLabel, in: menu, id: "app.version")
    }

    private func buildClipboardHistory(_ menu: NSMenu) {
        action("Enable clipboard history", id: "clipboard.enabled", in: menu, checked: state.clipboardContextEnabled, enabled: canConfigure) { [weak self] in self?.state.clipboardContextEnabled.toggle() }
        menu.addItem(.separator())
        let view = ClipboardHistoryView()
        view.update(entries: state.clipboardMonitor.snapshot().entries, enabled: state.clipboardContextEnabled)
        clipboardHistoryView = view
        custom(view, in: menu)
        menu.addItem(.separator())
        action("Clear remembered clipboard items", id: "clipboard.clear", in: menu, enabled: canConfigure) { [weak self] in self?.state.clearClipboardHistory() }
        info("Saved for two days · API keys masked · S2T copies excluded", in: menu)
    }

    private func buildKeys(_ menu: NSMenu) {
        if state.savedKeysLocked || state.clipboardMonitor.persistenceError != nil {
            action("Unlock saved keys…", id: "keys.unlock", in: menu, enabled: canConfigure) { [weak self] in self?.state.loadSavedKeys(allowInteraction: true) }
            message("S2T keeps keys together in Keychain. Older separate items may need approval once while being imported.", in: menu)
            menu.addItem(.separator())
        }
        submenu("Speech to text · \(state.transcriptionProvider.title)", id: "keys.transcription", in: menu) { [weak self] menu in
            guard let self else { return }
            for provider in TranscriptionProvider.allCases {
                self.action(provider.title, id: "speechProvider.\(provider.rawValue)", in: menu, checked: self.state.transcriptionProvider == provider, enabled: self.canConfigure) { [weak self] in self?.state.transcriptionProvider = provider }
            }
            menu.addItem(.separator())
            self.keyEditor(account: self.state.transcriptionProvider.rawValue, title: "\(self.state.transcriptionProvider.title) API key", transcription: true, in: menu)
        }
        submenu("Text cleanup · \(state.processingProvider?.title ?? "OpenRouter")", id: "keys.processing", in: menu) { [weak self] menu in
            guard let self else { return }
            for provider in ProcessingProvider.allCases {
                self.action(provider.title, id: "provider.\(provider.rawValue)", in: menu, checked: self.state.processingProvider == provider, enabled: self.canConfigure) { [weak self] in self?.state.processingProvider = provider }
            }
            menu.addItem(.separator())
            if let provider = self.state.processingProvider { self.keyEditor(account: provider.rawValue, title: "\(provider.title) API key", in: menu) }
        }
    }

    private func makeKeyEditor(account: String, title: String) -> MenuValueEditor {
        let read: () -> String = { [weak self] in
            guard let self else { return "" }
            return self.state.keyValue(account)
        }
        let write: (String) -> Void = { [weak self] value in
            switch account { case "assemblyai": self?.state.assemblyKey = value; case "openrouter": self?.state.routerKey = value; case "elevenlabs": self?.state.elevenLabsKey = value; case "cerebras": self?.state.cerebrasKey = value; default: break }
        }
        let editor = MenuValueEditor(title: title, value: read(), secure: true, saved: state.savedKeyAccounts.contains(account), enabled: canConfigure, onPaste: write) { [weak self] _ in
            self?.state.saveAPIKey(account: account)
            return self?.state.savedKeyAccounts.contains(account) == true ? nil : self?.state.keyStatuses[account]?.message ?? "Could not save the key."
        }
        editor.setKeyStatus(state.keyStatuses[account], saved: state.savedKeyAccounts.contains(account))
        editor.identifier = NSUserInterfaceItemIdentifier("editor.\(account)")
        editor.setAccessibilityIdentifier("editor.\(account)")
        return editor
    }

    private func keyEditor(account: String, title: String, transcription: Bool = false, in menu: NSMenu) {
        let item = NSMenuItem()
        item.view = makeKeyEditor(account: account, title: title)
        item.isHidden = account == "local" || account == "codex"
        menu.addItem(item)
        if transcription { transcriptionEditors.append(item) } else { processingEditors.append(item) }
        action("Get an API key…", id: transcription ? "key.get.speech" : "key.get.processing", in: menu) { [weak self] in
            let provider = transcription ? self?.state.transcriptionProvider.rawValue ?? account : self?.state.processingProvider?.rawValue ?? account
            let address = provider == "assemblyai" ? "https://www.assemblyai.com/dashboard/signup" : provider == "openrouter" ? "https://openrouter.ai/settings/keys" : provider == "elevenlabs" ? "https://elevenlabs.io/app/settings/api-keys" : "https://cloud.cerebras.ai/platform/"
            NSWorkspace.shared.open(URL(string: address)!)
        }
    }

    private func localEndpointEditor(speech: Bool, in menu: NSMenu) {
        let editor = MenuValueEditor(title: "Endpoint URL", value: speech ? state.localTranscriptionURL : state.localProcessingURL,
            secure: false, enabled: canConfigure, onPaste: { _ in }) { [weak self] value in
            do {
                let url = try LocalEndpoint.url(value).absoluteString
                if speech { self?.state.localTranscriptionURL = url } else { self?.state.localProcessingURL = url }
                return nil
            } catch { return error.localizedDescription }
        }
        editor.identifier = NSUserInterfaceItemIdentifier(speech ? "local.speech.url" : "local.processing.url")
        custom(editor, in: menu)
        message("OpenAI-compatible server. Enter the complete endpoint URL and the model loaded on your server. Local requests do not send an API key or fall back to a cloud provider.", in: menu)
    }

    private func buildSpeechModel(_ menu: NSMenu) {
        let provider = state.transcriptionProvider
        if provider == .local { localEndpointEditor(speech: true, in: menu) }
        guard provider != .assemblyAI else {
            message("AssemblyAI uses Fast or Extended languages under Dictation → Speech recognition.", in: menu)
            return
        }
        let editor = MenuValueEditor(title: "\(provider.title) model ID", value: state.transcriptionModel, secure: false, enabled: canConfigure, onPaste: { _ in }) { [weak self] value in
            guard provider.validModelID(value) else { return "Enter a valid \(provider.title) model ID." }
            if provider == .local { self?.state.localTranscriptionModel = value }
            else if provider == .elevenLabs { self?.state.elevenLabsModel = value }
            else { self?.state.routerTranscriptionModel = value }
            return nil
        }
        custom(editor, in: menu)
        action("Use default · \(provider.defaultModel)", id: "speech.model.default", in: menu, enabled: canConfigure) { [weak self] in
            if provider == .local { self?.state.localTranscriptionModel = provider.defaultModel }
            else if provider == .elevenLabs { self?.state.elevenLabsModel = provider.defaultModel }
            else { self?.state.routerTranscriptionModel = provider.defaultModel }
            editor.field.stringValue = provider.defaultModel
            editor.saveButton.title = "✓ Saved"
            editor.feedback.stringValue = "Saved"
        }
        if provider == .local { return }
        action("Browse speech-to-text models…", id: "speech.model.catalog", in: menu) {
            NSWorkspace.shared.open(URL(string: provider == .openRouter ? "https://openrouter.ai/models?output_modalities=transcription" : "https://elevenlabs.io/docs/overview/capabilities/speech-to-text")!)
        }
    }

    private func buildInputPresets(_ menu: NSMenu) {
        for preset in InputTargetPreset.allCases {
            action(preset.title, id: "inputPreset." + preset.rawValue, in: menu,
                   checked: !state.disabledInputPresets.contains(preset.rawValue), enabled: canConfigure) { [weak self] in
                guard let self else { return }
                if self.state.disabledInputPresets.contains(preset.rawValue) { self.state.disabledInputPresets.remove(preset.rawValue) }
                else { self.state.disabledInputPresets.insert(preset.rawValue) }
            }
        }
        message("Around Input tries enabled app and website presets first, then automatic detection. Safari covers its address field; website presets take priority. Terminal and Claude Code use the cursor row when it is exposed.", in: menu)
    }

    private func buildDictation(_ menu: NSMenu) {
        submenu("Input presets", id: "inputPresets", in: menu) { [weak self] menu in self?.buildInputPresets(menu) }
        action("Paste where dictation started", id: "dictation.pasteAtStart", in: menu, checked: state.pasteAtStart, enabled: canConfigure) { [weak self] in self?.state.pasteAtStart.toggle() }
        submenu("Microphone", id: "microphone", in: menu) { [weak self] menu in self?.buildMicrophone(menu) }
        submenu("Activation key", id: "activation", in: menu) { [weak self] menu in self?.buildActivation(menu) }
        menu.addItem(.separator())
        info("Writing mode", in: menu)
        for mode in WritingMode.allCases {
            action(mode.title, id: "mode.\(mode.rawValue)", in: menu, checked: state.mode == mode, enabled: canConfigure) { [weak self] in self?.state.mode = mode }
        }
        menu.addItem(.separator())
        info("Speech recognition · AssemblyAI", in: menu)
        for mode in TranscriptionMode.allCases {
            action(mode.title, id: "transcription.\(mode.rawValue)", in: menu, checked: state.transcriptionMode == mode, enabled: canConfigure && state.transcriptionProvider == .assemblyAI) { [weak self] in self?.state.transcriptionMode = mode }
        }
        menu.addItem(.separator())
        submenu("Clipboard context", id: "clipboard", in: menu) { [weak self] menu in
            guard let self else { return }
            self.action("Enable clipboard history", id: "clipboard.enabled", in: menu, checked: self.state.clipboardContextEnabled, enabled: self.canConfigure) { [weak self] in self?.state.clipboardContextEnabled.toggle() }
            self.action("Clear remembered clipboard items", id: "clipboard.clear", in: menu, enabled: self.canConfigure) { [weak self] in self?.state.clearClipboardHistory() }
            self.message("Keeps the last 50 copies for two days, including across app restarts. Turning this off pauses capture without clearing saved history. Mention a link, API key, or copied text to insert it. Keys stay local during editing. Verbatim skips this.", in: menu)
        }
        info("Pastes the complete text in one action", in: menu)
    }

    private func buildMicrophone(_ menu: NSMenu) {
        state.inputs.refresh()
        action("Automatic · \(state.inputs.defaultName)", id: "microphone.automatic", in: menu, checked: state.microphoneUID.isEmpty, enabled: canConfigure) { [weak self] in self?.state.microphoneUID = "" }
        menu.addItem(.separator())
        for device in state.inputs.devices {
            action(device.name, id: "microphone.\(device.id)", in: menu, checked: state.microphoneUID == device.id, enabled: canConfigure) { [weak self] in self?.state.microphoneUID = device.id }
        }
        if !state.microphoneUID.isEmpty && !state.inputs.devices.contains(where: { $0.id == state.microphoneUID }) { info("Selected microphone is disconnected", in: menu) }
        menu.addItem(.separator())
        action(state.phase == .monitoring ? "Stop microphone test" : "Test microphone", id: "microphone.test", in: menu, enabled: canConfigure) { [weak self] in
            guard let self else { return }
            if self.state.phase == .monitoring { self.state.cancel() } else { self.state.testMicrophone() }
        }
        message("Automatic prefers the Mac microphone. Selecting an AirPods microphone can reduce Bluetooth playback quality.", in: menu)
    }

    private func buildActivation(_ menu: NSMenu) {
        info("Current key: \(state.shortcutKey.displayName)", in: menu, id: "shortcut.current")
        action("Record custom key…", id: "shortcut.record", in: menu, enabled: canConfigure && state.shortcutAccessGranted) { [weak self] in
            DispatchQueue.main.async { self?.state.beginShortcutCapture?() }
        }
        action("Use Fn", id: "shortcut.fn", in: menu, checked: state.shortcutKey == .function, enabled: canConfigure) { [weak self] in self?.state.saveShortcut(.function, prompt: false) }
        menu.addItem(.separator())
        action("Hold to talk", id: "shortcut.hold", in: menu, checked: state.holdEnabled, enabled: canConfigure) { [weak self] in self?.state.holdEnabled.toggle() }
        action("Tap to toggle", id: "shortcut.tap", in: menu, checked: state.tapEnabled, enabled: canConfigure) { [weak self] in self?.state.tapEnabled.toggle() }
        menu.addItem(.separator())
        message("Hold and release to finish, or tap once to start and again to finish. Fn replaces the emoji picker while enabled.", in: menu)
        message(state.shortcutStatus, in: menu, id: "shortcut.status")
        action("Open Keyboard settings…", id: "shortcut.keyboard", in: menu) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
        }
        if !state.shortcutAccessGranted {
            message("Choose Set up dictation in the main menu to enable the activation key and text insertion.", in: menu)
        }
    }

    private var modelRowTitle: String {
        let name = state.processingModel == ProcessingProvider.cerebrasOpenRouterModel
            ? "GPT-OSS 120B" : String(state.processingModel.split(separator: "/").last ?? "Choose model")
        return "Model · " + String(name.prefix(42)) + (name.count > 42 ? "…" : "")
    }

    private var hostRowTitle: String {
        let name = state.processingProvider == .cerebras || state.routerEndpoint == "cerebras/fp16"
            ? "Cerebras" : state.routerEndpoint.isEmpty ? "Automatic" : state.routerEndpoint
        return "Host · " + String(name.prefix(42)) + (name.count > 42 ? "…" : "")
    }

    private func buildModels(_ menu: NSMenu) {
        guard let provider = state.processingProvider else { return }
        if provider == .local { localEndpointEditor(speech: false, in: menu) }
        if provider == .codex { codexSettings(in: menu) }
        submenu(modelRowTitle, id: "model.selected", in: menu) { [weak self] menu in
            guard let self else { return }
            let editor = MenuValueEditor(title: "Model ID", value: self.state.processingModel, secure: false, enabled: self.canConfigure, onPaste: { _ in }) { [weak self] value in
                self?.state.saveProcessingModel(value, for: provider)
            }
            self.processingModelEditor = editor
            self.displayedProcessingModel = self.state.processingModel
            self.custom(editor, in: menu)
            self.action("Use default · \(provider.defaultModel)", id: "model.default", in: menu, enabled: self.canConfigure) { [weak self] in
                self?.state.processingModel = provider.defaultModel
                editor.field.stringValue = provider.defaultModel
            }
            if provider.requiresAPIKey { self.action("Browse models…", id: "model.catalog", in: menu) { NSWorkspace.shared.open(provider.modelCatalogURL) } }
        }
        if let endpoint = provider.defaultEndpoint {
            submenu(hostRowTitle, id: "model.endpoint", in: menu) { [weak self] menu in
                guard let self else { return }
                let editor = MenuValueEditor(title: "OpenRouter endpoint", value: self.state.routerEndpoint, secure: false,
                    enabled: self.canConfigure, onPaste: { _ in }) { [weak self] value in
                    guard value.isEmpty || value.range(of: #"^[a-z0-9][a-z0-9/_.-]{0,199}$"#, options: .regularExpression) != nil else {
                        return "Enter an endpoint such as cerebras/fp16."
                    }
                    self?.state.routerEndpoint = value
                    return nil
                }
                self.hostingEndpointEditor = editor
                self.displayedHostingEndpoint = self.state.routerEndpoint
                self.custom(editor, in: menu)
                self.action("Use default · \(endpoint)", id: "model.endpoint.default", in: menu, enabled: self.canConfigure) { [weak self] in
                    self?.state.routerEndpoint = endpoint
                    editor.field.stringValue = endpoint
                }
            }
        }
        if provider == .openRouter {
            menu.addItem(.separator())
            action("GPT-OSS 120B on Cerebras", id: "model.cerebrasPreset", in: menu,
                   checked: state.processingModel == ProcessingProvider.cerebrasOpenRouterModel && state.routerEndpoint == "cerebras/fp16",
                   enabled: canConfigure) { [weak self] in self?.state.useCerebrasThroughOpenRouter() }
        }
    }

    private func buildResult(_ menu: NSMenu) {
        guard !state.output.isEmpty else { info("No dictation yet", in: menu); return }
        action(state.copied ? "Copied" : "Copy text", id: "result.copy", in: menu) { [weak self] in self?.state.showOriginal = false; self?.state.copyResult() }
        if !state.promptImages.isEmpty { submenu("Reference images", id: "result.images", in: menu) { [weak self] menu in self?.buildPromptImages(menu) } }
        action("Copy original transcript", id: "result.original", in: menu) { [weak self] in self?.state.showOriginal = true; self?.state.copyResult() }
        if state.canRetry { action("Retry", id: "result.retry", in: menu) { [weak self] in self?.state.retry() } }
        if let model = state.processingFailureModel { message("Rewrite failed for \(model). The original transcript was delivered.", in: menu) }
        info("\(state.wordCount) words · \(state.modelUsed)", in: menu)
        menu.addItem(.separator())
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 170))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 322, height: 170))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textColor = .labelColor
        text.font = .systemFont(ofSize: 13)
        text.textContainerInset = NSSize(width: 10, height: 8)
        text.string = state.output
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        scroll.documentView = text
        custom(scroll, in: menu)
    }

    private func submenu(_ title: String, id: String, in menu: NSMenu, build: @escaping (NSMenu) -> Void) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(id)
        item.setAccessibilityIdentifier(id)
        let child = NSMenu(title: title)
        child.autoenablesItems = false
        child.delegate = self
        child.addItem(NSMenuItem(title: "Loading…", action: nil, keyEquivalent: ""))
        item.submenu = child
        builders[ObjectIdentifier(child)] = build
        menu.addItem(item)
    }

    @discardableResult private func action(_ title: String, id: String, in menu: NSMenu, checked: Bool = false, enabled: Bool = true, perform: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title: title) { [weak self] in perform(); self?.refreshStatus() }
        item.identifier = NSUserInterfaceItemIdentifier(id)
        item.setAccessibilityIdentifier(id)
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func keyTitle(_ title: String, accounts: [String]) -> String {
        accounts.contains { state.keyStatuses[$0]?.needsAttention == true } ? "⚠ " + title : title
    }

    private func applyRootTitle(_ text: String, symbol name: String, to item: NSMenuItem) {
        let font = NSFont.menuFont(ofSize: 0)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let symbol = image.withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)) ?? image
        let scale = min(1, 16 / max(symbol.size.width, symbol.size.height))
        let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let attachment = NSTextAttachment()
        attachment.image = symbol
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - size.height) / 2, width: size.width, height: size.height)
        let title = NSMutableAttributedString(attachment: attachment)
        title.append(NSAttributedString(string: "  " + text, attributes: [.font: font]))
        item.attributedTitle = title
    }

    private func refreshItems(_ menu: NSMenu) {
        for entry in menu.items {
            let identity = ObjectIdentifier(entry)
            var title = rootTitles[identity]?.text ?? entry.title
            var symbol: String?
            if menu === self.menu {
                switch entry.identifier?.rawValue {
                case "setup": symbol = "checklist"
                case "dictation.toggle": symbol = state.phase == .recording ? "stop.circle" : "mic"
                case "dictation.cancel": symbol = "xmark.circle"
                case "result": symbol = "text.bubble"
                case "clipboard.history": symbol = "clipboard"
                case "prompt": symbol = "sparkles"
                case "dictation": symbol = "slider.horizontal.3"
                case "appearance": symbol = "gearshape"
                case "keys": symbol = "key"
                case "notice": symbol = "exclamationmark.triangle"
                case "quit": symbol = "power"
                default: symbol = nil
                }
            }
            defer {
                if let symbol {
                    if rootTitles[identity]?.text != title || rootTitles[identity]?.symbol != symbol {
                        applyRootTitle(title, symbol: symbol, to: entry)
                        rootTitles[identity] = (title, symbol)
                    }
                } else if entry.title != title {
                    entry.title = title
                }
            }
            switch entry.identifier?.rawValue {
            case "prompt.activation": title = "Activation key · " + state.promptShortcutKey.displayName
            case "prompt.shortcut.current": title = "Current key: " + state.promptShortcutKey.displayName
            case "prompt": title = state.promptModeEnabled ? "Prompt mode · Beta · On" : "Prompt mode · Experimental beta"
            case "setup": title = state.setupReady ? "Dictation setup" : "Set up dictation"
            case "setup.microphone": title = "Microphone · \(state.microphoneAccess == .authorized ? "Allowed" : state.microphoneAccess == .restricted ? "Restricted" : "Not allowed")"
            case "setup.accessibility": title = "Accessibility · \(state.shortcutAccessGranted ? "Allowed" : "Not allowed")"
            case "setup.keys": title = state.setupKeysReady ? "Provider keys · Saved" : "Provider keys · Needs setup"
            case "setup.fn": entry.isHidden = state.shortcutKey.keyCode != 63
            case "bezel.side": entry.isHidden = state.glowAppearance != .bezel
            case "glow.intensity", "glow.minimum", "glow.maximum": entry.isHidden = state.glowAppearance == .bezel
            case "glow.width": entry.isHidden = ![.bottom, .aroundNotch].contains(state.glowAppearance)
            case "appearance.legend": title = state.glowAppearance == .bezel ? "Waveform · Spinner · Checkmark" : "Listening glow · Processing line"
            case "status.phase":
                entry.isHidden = [.idle, .complete].contains(state.phase) && !state.isWaitingToPaste && state.processingFailureModel == nil
                title = state.processingFailureModel != nil && state.phase == .complete ? "Original text delivered · Rewrite failed" : state.isWaitingToPaste ? "Text ready · Waiting to insert" : state.phase.label
            case "clipboard.history": title = state.clipboardContextEnabled ? "Clipboard history · \(state.clipboardMonitor.itemCount)" : "Clipboard history · Off"
            case "model.selected", "processing.model.summary": title = modelRowTitle
            case "model.endpoint", "processing.host.summary": title = hostRowTitle
            case "status.keys": entry.isHidden = state.canRecord
            case "shortcut.current": title = state.isCapturingShortcut ? "Press a key. Escape cancels." : "Current key: \(state.shortcutKey.displayName)"
            case "appearance": title = keyTitle("Settings…", accounts: APIAccount.allCases.map(\.rawValue))
            case "keys": title = keyTitle("API keys", accounts: APIAccount.allCases.map(\.rawValue))
            case "keys.transcription": title = keyTitle("Speech to text · \(state.transcriptionProvider.title)", accounts: TranscriptionProvider.allCases.map(\.rawValue))
            case "prompt.model": title = "Image model · \(state.promptVisionProvider.title)"
            case "keys.processing": title = keyTitle("Text cleanup · \(state.processingProvider?.title ?? "OpenRouter")", accounts: ["openrouter", "cerebras"])
            case "notice": title = "Needs attention"; entry.isHidden = statusMessage == nil
            default: break
            }
            if let slider = entry.view as? MenuSlider {
                switch entry.identifier?.rawValue {
                case "glow.intensity": slider.setValue(state.glowStrength)
                case "glow.width": slider.setValue(state.glowWidth)
                case "glow.minimum": slider.setValue(state.glowMinimum)
                case "glow.maximum": slider.setValue(state.glowMaximum)
                default: break
                }
            }
            if entry.view?.identifier?.rawValue == "appearance.inputHelp", let label = entry.view?.subviews.first as? NSTextField {
                label.stringValue = state.inputOutlineNotice ?? "Around Input outlines the focused text field during dictation. Uses Bottom when a field is unavailable."
                entry.isHidden = state.glowAppearance != .aroundInput
            }
            if entry.view?.identifier?.rawValue == "status.message", let label = entry.view?.subviews.first as? NSTextField {
                label.stringValue = statusMessage ?? state.phase.label
                label.toolTip = label.stringValue
            }
            if let id = entry.view?.identifier?.rawValue,
               ["setup.summary", "setup.testStatus", "shortcut.status"].contains(id),
               let label = entry.view?.subviews.first as? NSTextField {
                label.stringValue = id == "setup.summary" ? state.setupSummary : id == "setup.testStatus" ? state.shortcutTestStatus : state.shortcutStatus
                label.toolTip = label.stringValue
            }
            if entry.view?.identifier?.rawValue == "prompt.shortcut.conflict", let label = entry.view?.subviews.first as? NSTextField {
                entry.isHidden = !state.promptShortcutConflict
                label.stringValue = "This key is also assigned to normal dictation. Choose another Prompt mode key to activate its shortcut."
            }
            if entry.view?.identifier?.rawValue == "prompt.status", let label = entry.view?.subviews.first as? NSTextField {
                label.stringValue = state.promptStatus
                label.toolTip = state.promptStatus
            }
            if let editor = entry.view as? MenuValueEditor {
                if let id = editor.identifier?.rawValue, id.hasPrefix("editor.") {
                    let account = String(id.dropFirst(7))
                    editor.setKeyStatus(state.keyStatuses[account], saved: state.savedKeyAccounts.contains(account))
                }
                editor.setEnabled(canConfigure)
            }
            if let child = entry.submenu { refreshItems(child) }
            guard let item = entry as? ActionMenuItem, let id = item.identifier?.rawValue else { continue }
            if id.hasPrefix("inputPreset.") {
                item.state = state.disabledInputPresets.contains(String(id.dropFirst(12))) ? .off : .on
                item.isEnabled = canConfigure
            }
            if id.hasPrefix("speechProvider."), let provider = TranscriptionProvider(rawValue: String(id.dropFirst(15))) {
                title = keyTitle(provider.title, accounts: [provider.rawValue])
                item.state = state.transcriptionProvider == provider ? .on : .off
                item.isEnabled = canConfigure
            }
            if id.hasPrefix("provider."), let provider = ProcessingProvider(rawValue: String(id.dropFirst(9))) {
                title = keyTitle(provider.title, accounts: [provider.rawValue])
            }
            if id.hasPrefix("visionProvider.") { item.state = state.promptVisionProvider.rawValue == String(id.dropFirst(15)) ? .on : .off; item.isEnabled = canConfigure }
            if id.hasPrefix("provider.") { item.state = state.processingProvider?.rawValue == String(id.dropFirst(9)) ? .on : .off; item.isEnabled = canConfigure }
            if id.hasPrefix("mode.") { item.state = state.mode.rawValue == String(id.dropFirst(5)) ? .on : .off; item.isEnabled = canConfigure }
            if id.hasPrefix("transcription.") { item.state = state.transcriptionMode.rawValue == String(id.dropFirst(14)) ? .on : .off; item.isEnabled = canConfigure && state.transcriptionProvider == .assemblyAI }
            if id.hasPrefix("microphone.") && id != "microphone.test" {
                item.state = (id == "microphone.automatic" ? state.microphoneUID.isEmpty : state.microphoneUID == String(id.dropFirst(11))) ? .on : .off
                item.isEnabled = canConfigure
            }
            if id.hasPrefix("appearance.") { item.state = state.menuAppearance == String(id.dropFirst(11)) ? .on : .off }
            if id.hasPrefix("bezelSide.") { item.state = state.bezelSide.rawValue == String(id.dropFirst(10)) ? .on : .off }
            if id.hasPrefix("glowAppearance.") { item.state = state.glowAppearance.rawValue == String(id.dropFirst(15)) ? .on : .off }
            if id.hasPrefix("prompt.locale.") {
                item.state = state.promptLanguage == String(id.dropFirst(14)) ? .on : .off
                item.isEnabled = canConfigure
            }
            switch id {
            case "prompt.shortcut.default": item.state = state.promptShortcutKey == .rightCommand ? .on : .off; item.isEnabled = canConfigure
            case "prompt.shortcut.record": item.isEnabled = canConfigure && state.shortcutAccessGranted
            case "prompt.shortcut.hold": item.state = state.promptHoldEnabled ? .on : .off; item.isEnabled = canConfigure
            case "prompt.shortcut.tap": item.state = state.promptTapEnabled ? .on : .off; item.isEnabled = canConfigure
            case "prompt.start":
                title = state.phase == .recording && state.sessionIsPrompt ? "Finish prompt dictation" : "Start prompt dictation"
                item.isEnabled = state.promptModeEnabled && (canConfigure || (state.phase == .recording && state.sessionIsPrompt))
            case "prompt.enabled": item.state = state.promptModeEnabled ? .on : .off; item.isEnabled = canConfigure
            case "prompt.setup": title = state.promptSetupTitle; item.isEnabled = canConfigure && state.promptSetupTitle != "Permissions ready"
            case "dictation.toggle": title = state.phase == .recording ? "Finish dictation" : "Start dictation"; item.isEnabled = !state.phase.busy
            case "dictation.cancel":
                item.isEnabled = state.canCancel
                item.isHidden = !item.isEnabled
            case "keys.unlock":
                item.isHidden = !state.savedKeysLocked && state.clipboardMonitor.persistenceError == nil
                item.isEnabled = canConfigure
            case "permissions.setup":
                title = state.permissionActionTitle
                item.isHidden = state.dictationPermissionsReady
                item.isEnabled = !state.needsInstallation && state.microphoneAccess != .restricted && !state.settingUpPermissions && canConfigure
            case "setup.install": item.isHidden = !state.needsInstallation
            case "setup.test":
                title = state.shortcutTestActive ? "Cancel shortcut test" : state.shortcutTestPassed ? "Test shortcut again" : "Test shortcut"
                item.isEnabled = state.shortcutAvailable && canConfigure
                item.state = state.shortcutTestPassed ? .on : .off
            case "setup.verbatim": item.state = state.mode == .verbatim ? .on : .off; item.isEnabled = canConfigure
            case "shortcut.repair": item.isEnabled = state.shortcutAccessGranted && canConfigure
            case "dictation.pasteAtStart": item.state = state.pasteAtStart ? .on : .off; item.isEnabled = canConfigure
            case "shortcut.hold": item.state = state.holdEnabled ? .on : .off; item.isEnabled = canConfigure
            case "shortcut.tap": item.state = state.tapEnabled ? .on : .off; item.isEnabled = canConfigure
            case "shortcut.fn": item.state = state.shortcutKey == .function ? .on : .off; item.isEnabled = canConfigure
            case "shortcut.record": item.isEnabled = canConfigure && state.shortcutAccessGranted
            case "microphone.test": title = state.phase == .monitoring ? "Stop microphone test" : state.phase == .preparing ? "Starting microphone…" : "Test microphone"; item.isEnabled = canConfigure
            case "glow.preview": title = state.phase == .preview ? "Stop appearance preview" : "Preview appearance"; item.isEnabled = canConfigure
            case "model.cerebrasPreset": item.isEnabled = canConfigure; item.state = state.processingModel == ProcessingProvider.cerebrasOpenRouterModel && state.routerEndpoint == "cerebras/fp16" ? .on : .off
            case "clipboard.enabled": item.state = state.clipboardContextEnabled ? .on : .off; item.isEnabled = canConfigure
            case "clipboard.clear": item.isEnabled = canConfigure
            case "key.get.speech": item.isHidden = state.transcriptionProvider == .local
            case "key.get.processing": item.isHidden = state.processingProvider?.requiresAPIKey != true
            case "speech.model.default": item.isEnabled = canConfigure
            case "result.copy": title = state.copied ? "Copied" : "Copy text"
            default: break
            }
        }
        if menu === self.menu {
            let provider = state.transcriptionProvider
            for item in transcriptionEditors { item.isHidden = provider == .local }
            for item in transcriptionEditors where provider != .local && item.view?.identifier?.rawValue != "editor.\(provider.rawValue)" {
                item.view = makeKeyEditor(account: provider.rawValue, title: "\(provider.title) API key")
            }
        }
        if menu === self.menu, let provider = state.processingProvider {
            for item in processingEditors { item.isHidden = !provider.requiresAPIKey }
            for item in processingEditors where provider.requiresAPIKey && item.view?.identifier?.rawValue != "editor.\(provider.rawValue)" {
                item.view = makeKeyEditor(account: provider.rawValue, title: "\(provider.title) API key")
            }
        }
    }

    private func info(_ title: String, in menu: NSMenu, id: String? = nil) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let id { item.identifier = NSUserInterfaceItemIdentifier(id) }
        menu.addItem(item)
    }

    private func message(_ text: String, in menu: NSMenu, id: String? = nil) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 65))
        label.frame = NSRect(x: 14, y: 6, width: 292, height: 53)
        if let id { view.identifier = NSUserInterfaceItemIdentifier(id) }
        view.addSubview(label)
        custom(view, in: menu)
    }

    private func custom(_ view: NSView, in menu: NSMenu) {
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }


}

@MainActor final class ActionMenuItem: NSMenuItem {
    private let perform: () -> Void
    init(title: String, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc func invoke() { if isEnabled { perform() } }
}

@MainActor final class MenuValueEditor: NSView {
    let field: NSTextField
    let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)
    let feedback = NSTextField(labelWithString: "")
    private let onPaste: (String) -> Void
    private let onSave: (String) -> String?
    private let secure: Bool
    private var keyStatus: APIKeyStatus?
    var validateValue: ((String) async -> String?)?
    private var validationTask: Task<Void, Never>?
    private var validationID = UUID()
    private var isValidating = false

    init(title: String, value: String, secure: Bool, saved: Bool = false, enabled: Bool = true, onPaste: @escaping (String) -> Void, onSave: @escaping (String) -> String?) {
        self.secure = secure
        self.onPaste = onPaste
        self.onSave = onSave
        field = secure ? NSSecureTextField() : NSTextField()
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: secure ? 172 : 132))
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 14, y: secure ? 146 : 106, width: 312, height: 18)
        addSubview(label)
        field.stringValue = value
        field.placeholderString = "Use Paste below"
        field.isEditable = false
        field.isSelectable = false
        field.frame = NSRect(x: 14, y: secure ? 112 : 72, width: 312, height: 26)
        field.setAccessibilityLabel(title)
        addSubview(field)
        pasteButton.frame = NSRect(x: 12, y: secure ? 74 : 34, width: 92, height: 30)
        pasteButton.target = self
        pasteButton.action = #selector(pasteValue)
        pasteButton.bezelStyle = .rounded
        pasteButton.isEnabled = enabled
        pasteButton.setAccessibilityIdentifier("editor.paste")
        addSubview(pasteButton)
        saveButton.frame = NSRect(x: 212, y: secure ? 74 : 34, width: 116, height: 30)
        saveButton.target = self
        saveButton.action = #selector(saveValue)
        saveButton.bezelStyle = .rounded
        saveButton.isEnabled = enabled && !value.isEmpty
        saveButton.title = saved ? "✓ Saved" : secure ? "Save API key" : "Save"
        saveButton.setAccessibilityIdentifier("editor.save")
        addSubview(saveButton)
        feedback.frame = NSRect(x: 14, y: 8, width: 312, height: secure ? 60 : 20)
        feedback.font = .systemFont(ofSize: 11)
        feedback.textColor = .secondaryLabelColor
        feedback.lineBreakMode = secure ? .byWordWrapping : .byTruncatingTail
        feedback.maximumNumberOfLines = secure ? 4 : 1
        feedback.cell?.wraps = secure
        feedback.stringValue = saved ? "Saved in Keychain" : "Paste from your clipboard, then save."
        addSubview(feedback)
        label.autoresizingMask = [.width]
        field.autoresizingMask = [.width]
        feedback.autoresizingMask = [.width]
        saveButton.autoresizingMask = [.minXMargin]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func useSettingsStyle() {
        for child in subviews where child !== field && child !== pasteButton && child !== saveButton && child !== feedback { child.isHidden = true }
        field.placeholderString = "API key"
        let well = SettingsFormStyle.field(field)
        let actions = NSStackView(views: [well, pasteButton, saveButton])
        actions.distribution = .fill
        well.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.spacing = 8
        actions.alignment = .centerY
        for button in [pasteButton, saveButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            if #available(macOS 26, *) {
                button.bezelStyle = .glass
                button.borderShape = .capsule
                button.tintProminence = button === saveButton ? .primary : .none
            }
            button.bezelColor = button === saveButton ? .systemBlue : nil
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.widthAnchor.constraint(equalToConstant: button === saveButton ? 114 : 76).isActive = true
        }
        let stack = NSStackView(views: [actions, feedback])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for child in stack.arrangedSubviews {
            child.translatesAutoresizingMaskIntoConstraints = false
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        feedback.maximumNumberOfLines = 0
        feedback.cell?.wraps = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func setKeyStatus(_ status: APIKeyStatus?, saved: Bool) {
        guard keyStatus != status else { return }
        keyStatus = status
        feedback.stringValue = status?.message ?? (saved ? "Saved in Keychain" : "Pasted. Click Save to keep it.")
        if status == .accepted, !saved { feedback.stringValue = "Key accepted. Save to keep it in Keychain." }
        feedback.toolTip = feedback.stringValue
        feedback.textColor = status?.needsAttention == true ? .systemRed : .secondaryLabelColor
        saveButton.title = status == .checking ? "Checking…" : status?.needsAttention == true ? "Save and retry" : saved ? "✓ Saved" : "Save API key"
    }

    func setEnabled(_ enabled: Bool) {
        pasteButton.isEnabled = enabled
        saveButton.isEnabled = enabled && !isValidating && keyStatus != .checking && !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc func pasteValue(_ sender: Any?) {
        guard pasteButton.isEnabled else { return }
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            feedback.stringValue = "Copy a \(secure ? "key" : "value") first, then click Paste."
            return
        }
        field.stringValue = value
        validationTask?.cancel()
        validationID = UUID()
        isValidating = false
        onPaste(value)
        saveButton.isEnabled = true
        saveButton.title = secure ? "Save API key" : "Save"
        feedback.stringValue = "Pasted. Click Save to keep it."
    }

    @objc func saveValue(_ sender: Any?) {
        guard saveButton.isEnabled else { return }
        let value = field.stringValue
        guard let validateValue else { finishSaving(value); return }
        validationTask?.cancel()
        validationID = UUID()
        let id = validationID
        isValidating = true
        saveButton.isEnabled = false
        saveButton.title = "Checking…"
        feedback.stringValue = "Checking image support…"
        validationTask = Task { [weak self] in
            let error = await validateValue(value)
            guard !Task.isCancelled, let self, self.validationID == id, self.field.stringValue == value else { return }
            self.isValidating = false
            self.saveButton.isEnabled = true
            self.saveButton.title = "Save"
            if let error {
                self.feedback.stringValue = error
                self.feedback.toolTip = error
                return
            }
            self.finishSaving(value)
        }
    }

    private func finishSaving(_ value: String) {
        if let error = onSave(value) {
            feedback.stringValue = error
            feedback.toolTip = error
            return
        }
        saveButton.title = "✓ Saved"
        feedback.stringValue = secure ? "Saved in Keychain" : "Saved"
    }
}

@MainActor final class MenuSlider: NSView {
    let slider: NSSlider
    private let changed: (Double) -> Void
    private let label = NSTextField(labelWithString: "Glow intensity")
    private let title: String
    init(value: Double, title: String = "Glow intensity", range: ClosedRange<Double> = 0.25...1.3, id: String = "glow.intensity", changed: @escaping (Double) -> Void) {
        self.changed = changed
        self.title = title
        slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 65))
        label.frame = NSRect(x: 14, y: 40, width: 270, height: 18)
        label.font = .systemFont(ofSize: 12)
        addSubview(label)
        slider.frame = NSRect(x: 14, y: 10, width: 270, height: 24)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(update)
        slider.setAccessibilityIdentifier(id)
        slider.setAccessibilityLabel(title)
        setValue(value)
        addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setValue(_ value: Double) {
        if slider.doubleValue != value { slider.doubleValue = value }
        let text = "\(title) · \(Int((value * 100).rounded()))%"
        if label.stringValue != text { label.stringValue = text }
    }
    @objc private func update() { setValue(slider.doubleValue); changed(slider.doubleValue) }
}

extension NSMenuItem {
    var symbolLabel: String {
        if title.hasPrefix("\u{fffc}\t") { return String(title.dropFirst(2)) }
        return title.hasPrefix("\u{fffc}  ") ? String(title.dropFirst(3)) : title
    }
}
