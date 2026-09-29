import AppKit
import SwiftUI
import S2TCore

/// Less-used Dictation options open as sub-pages, like System Settings.
@MainActor final class DictationNavigation: ObservableObject {
    enum Page: String {
        case prompt, clipboard, inputDetection, advanced
        var title: String {
            switch self {
            case .prompt: "Prompt mode"
            case .clipboard: "Clipboard history"
            case .inputDetection: "Input detection"
            case .advanced: "Advanced"
            }
        }
    }
    @Published var page: Page?
}

@MainActor struct DictationSettingsPane: View {
    static let buildLabel = BuildIdentity.menuLabel
    @ObservedObject var state: AppState
    @ObservedObject var inputs: AudioInputs
    @ObservedObject var navigation: DictationNavigation
    var openAPIKeys: () -> Void
    var openRecent: () -> Void

    private var canConfigure: Bool { !state.phase.busy && state.phase != .recording }
    private var issue: String? { state.errorMessage ?? state.clipboardMonitor.persistenceError ?? state.notice }

    var body: some View {
        Form {
            switch navigation.page {
            case nil: main
            case .prompt?: Section { prompt } footer: {
                Text("Attach images while you dictate. Command-click captures a reference; Command-drag selects an area.")
                    .foregroundStyle(.secondary)
            }.accessibilityIdentifier("dictation.prompt")
            case .clipboard?: Section { clipboard } footer: {
                Text("Keeps up to 50 copies for two days, encrypted on this Mac. S2T's own copies are excluded.")
                    .foregroundStyle(.secondary)
            }.accessibilityIdentifier("dictation.clipboard")
            case .inputDetection?: Section { inputDetection } footer: {
                Text("S2T detects input boxes automatically. App exceptions use tuned outlines for specific apps.")
                    .foregroundStyle(.secondary)
            }
            case .advanced?: advanced.accessibilityIdentifier("dictation.advanced")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .toggleStyle(.switch)
        .background(.background)
        .nativeGlassButtons()
        .onAppear { inputs.refresh(); state.refreshSetup() }
        .accessibilityIdentifier("settings.dictation")
    }

    @ViewBuilder private var main: some View {
        if !state.dictationPermissionsReady || state.needsInstallation || !state.setupKeysReady {
            Section {
                if state.needsInstallation {
                    LabeledContent("Install S2T to finish setup") {
                        Button("Open Applications") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
                    }
                } else if !state.dictationPermissionsReady {
                    LabeledContent(state.microphoneAccess == .authorized ? "Allow keyboard access" : "Allow microphone access") {
                        Button(state.permissionActionTitle) { state.setUpDictation() }
                            .disabled(state.microphoneAccess == .restricted || state.settingUpPermissions || !canConfigure)
                            .accessibilityIdentifier("dictation.permissions")
                    }
                }
                if !state.setupKeysReady {
                    LabeledContent("Connect a provider") { Button("API keys", action: openAPIKeys) }
                }
            }
        }
        Section("Microphone") {
            Picker("Input", selection: $state.microphoneUID) {
                Text("Automatic · \(inputs.defaultName)").tag("")
                ForEach(inputs.devices) { Text($0.name).tag($0.id) }
                if !state.microphoneUID.isEmpty && !inputs.devices.contains(where: { $0.id == state.microphoneUID }) {
                    Text("Disconnected microphone").tag(state.microphoneUID)
                }
            }.disabled(!canConfigure)
            LabeledContent(state.phase == .monitoring ? "Listening…" : state.phase == .preparing ? "Starting microphone…" : "Test") {
                Button(state.phase == .monitoring ? "Stop test" : "Test microphone") {
                    if state.phase == .monitoring { state.cancel() } else { state.testMicrophone() }
                }.disabled(state.phase.busy || state.phase == .recording || state.meetingRecordingActive)
                    .accessibilityIdentifier("dictation.microphone.test")
            }
            if inputs.devices.first(where: { $0.id == state.microphoneUID })?.isBluetooth == true {
                Text("A Bluetooth microphone may reduce playback quality.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Shortcut") {
            LabeledContent("Activation key") {
                Button(state.shortcutKey.displayName) { state.beginShortcutCapture?() }
                    .disabled(!canConfigure || !state.shortcutAccessGranted)
                    .help("Click, then press a new activation key")
                    .accessibilityIdentifier("dictation.shortcut")
            }
            Toggle("Hold to talk", isOn: $state.holdEnabled).disabled(!canConfigure)
            Toggle("Tap to start and stop", isOn: $state.tapEnabled).disabled(!canConfigure)
            if !state.shortcutAvailable { Text(state.shortcutStatus).font(.caption).foregroundStyle(.secondary) }
        }
        Section {
            Picker("Writing mode", selection: $state.mode) {
                ForEach(WritingMode.allCases, id: \.rawValue) { Text($0.title).tag($0) }
            }.disabled(!canConfigure)
        }
        if state.speechUsesCredits && state.isProviderVisible("s2t") {
            Section {
                Toggle("Transcribe while speaking", isOn: $state.earlyTranscriptionEnabled)
                    .disabled(!canConfigure)
                    .accessibilityIdentifier("dictation.early-transcription")
            } footer: {
                Text("Sends completed sections during pauses so less work remains after Finish. Cancelled recordings may already have used S2T credits.")
            }
        }
        Section {
            row(.prompt, symbol: "photo.on.rectangle", summary: state.promptModeEnabled ? "On" : "Off")
            row(.clipboard, symbol: "doc.on.clipboard", summary: state.clipboardContextEnabled ? "On" : "Off")
            row(.inputDetection, symbol: "character.cursor.ibeam", summary: "")
            row(.advanced, symbol: "gearshape.2", summary: "")
        }
        if let issue {
            Section {
                Text(issue).textSelection(.enabled)
                HStack {
                    if state.canRetry { Button("Retry") { state.retry() } }
                    if state.canSaveRecording { Button("Save recording") { state.saveRecording() } }
                    Spacer()
                    Button("Dismiss") { state.errorMessage = nil; state.notice = nil }
                }
            }
        }
    }

    private func row(_ page: DictationNavigation.Page, symbol: String, summary: String) -> some View {
        SettingsNavigationRow(title: page.title, summary: summary, symbol: symbol) { navigation.page = page }
            .accessibilityIdentifier("dictation.open." + page.rawValue)
    }

    @ViewBuilder private var prompt: some View {
        Toggle("Enable Prompt mode", isOn: $state.promptModeEnabled).disabled(!canConfigure)
        if state.promptModeEnabled {
            LabeledContent("Activation key") {
                Button(state.promptShortcutKey.displayName) { state.beginPromptShortcutCapture?() }
                    .disabled(!canConfigure || !state.shortcutAccessGranted)
            }
            Toggle("Hold to talk", isOn: $state.promptHoldEnabled).disabled(!canConfigure)
            Toggle("Tap to start and stop", isOn: $state.promptTapEnabled).disabled(!canConfigure)
            if state.promptShortcutConflict {
                Text("Choose a different key from normal dictation.").foregroundStyle(.red)
            }
            Picker("Reference language", selection: $state.promptLanguage) {
                Text("English").tag("en-US"); Text("German").tag("de-DE")
            }.disabled(!canConfigure)
            HStack {
                Button(state.phase == .recording && state.sessionIsPrompt ? "Finish prompt" : "Start prompt") {
                    state.toggleRecording(prompt: true)
                }.disabled(!(canConfigure || state.phase == .recording && state.sessionIsPrompt))
                Menu("Options") {
                    if state.promptSetupTitle != "Permissions ready" {
                        Button(state.promptSetupTitle) { state.setUpPromptMode() }.disabled(!canConfigure)
                    }
                    Button("Use Right Command") { state.saveShortcut(.rightCommand, prompt: true) }.disabled(!canConfigure)
                    Button("Reveal saved references") { state.revealSavedPromptReferences() }
                    if !state.promptImages.isEmpty {
                        Button("Reveal last images") { state.revealPromptImages() }
                        ForEach(state.promptImages, id: \.self) { image in
                            Button("Copy \(image.lastPathComponent)") { state.copyPromptImage(image) }
                        }
                    }
                }
            }
            if !state.promptStatus.isEmpty { Text(state.promptStatus).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var clipboard: some View {
        Toggle("Remember copied text", isOn: $state.clipboardContextEnabled).disabled(!canConfigure)
        if !state.clipboardMonitor.entries.isEmpty {
            Text("\(state.clipboardMonitor.entries.count) remembered items").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(state.clipboardMonitor.entries.enumerated()), id: \.offset) { indexed in
                VStack(alignment: .leading, spacing: 4) {
                    Text(indexed.element.copiedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(indexed.element.displayText).lineLimit(2)
                }
            }
            Button("Clear history") { state.clearClipboardHistory() }.disabled(!canConfigure)
        }
    }

    private var inputDetection: some View {
        LabeledContent("App exceptions") {
            Menu("Choose apps") {
                ForEach(InputTargetPreset.allCases.filter { $0 != .safari }, id: \.rawValue) { preset in
                    Toggle(preset.title, isOn: Binding(
                        get: { !state.disabledInputPresets.contains(preset.rawValue) },
                        set: { enabled in
                            if enabled { state.disabledInputPresets.remove(preset.rawValue) }
                            else { state.disabledInputPresets.insert(preset.rawValue) }
                        }
                    ))
                }
            }
            .disabled(!canConfigure)
            .accessibilityIdentifier("dictation.input.exceptions")
        }
    }

    @ViewBuilder private var advanced: some View {
        Section {
            Picker("Speech recognition", selection: $state.transcriptionMode) {
                ForEach(TranscriptionMode.allCases, id: \.rawValue) { Text($0.title).tag($0) }
            }.disabled(!canConfigure || state.transcriptionProvider != .assemblyAI)
        }
        Section("Shortcut troubleshooting") {
            LabeledContent("Shortcut test") {
                Button(state.shortcutTestActive ? "Cancel test" : "Test shortcut") {
                    if state.shortcutTestActive { state.stopShortcutTest?() } else { state.testShortcut?() }
                }.disabled(!state.shortcutAvailable || !canConfigure)
            }
            if state.shortcutTestActive { Text(state.shortcutTestStatus).font(.caption).foregroundStyle(.secondary) }
            LabeledContent("Fn key") {
                HStack {
                    if state.shortcutKey.keyCode == 63 {
                        Button("Fix Fn") { state.repairFnShortcut?() }.disabled(!state.shortcutAccessGranted || !canConfigure)
                    } else {
                        Button("Use Fn") { state.saveShortcut(.function, prompt: false) }.disabled(!canConfigure)
                    }
                    Button("Keyboard Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                }
            }
        }
        Section {
            LabeledContent("Recent recordings") { Button("Show", action: openRecent) }
            if let notice = state.historicalReceiptNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if state.canRetry || state.canSaveRecording {
                LabeledContent("Last dictation") {
                    HStack {
                        if state.canRetry { Button("Retry") { state.retry() } }
                        if state.canSaveRecording { Button("Save recording") { state.saveRecording() } }
                    }
                }
            }
            if !state.recoveredRecordings.isEmpty {
                LabeledContent("Saved recordings") {
                    Menu("Recover") {
                        ForEach(state.recoveredRecordings, id: \.id) { saved in
                            Button(saved.createdAt.formatted(date: .abbreviated, time: .standard)) { state.recoverRecording(saved) }.disabled(!canConfigure)
                        }
                    }.fixedSize()
                }
            }
        } header: {
            Text("Recordings")
        } footer: {
            Text(Self.buildLabel).foregroundStyle(.secondary)
        }
    }
}
