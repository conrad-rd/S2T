import AppKit
import SwiftUI
import S2TCore

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var backHistory: [AppPage] = []
    @State private var forwardHistory: [AppPage] = []
    @State private var navigatingHistory = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .padding(8)
            VStack(alignment: .leading, spacing: 0) {
                navigationBar
                switch state.page {
                case .dictation: dictation
                case .settings: generalSettings
                case .connections: connectionSettings
                case .models: modelSettings
                case .appearance: appearanceSettings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white)
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: .labelColor))
        .preferredColorScheme(.light)
        .frame(minWidth: 760, minHeight: 590)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: state.page) { old, _ in
            if navigatingHistory { navigatingHistory = false }
            else { backHistory.append(old); forwardHistory.removeAll() }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button { navigateBack() } label: {
                Image(systemName: "chevron.left").frame(width: 15, height: 20)
            }.disabled(backHistory.isEmpty).help("Back").accessibilityLabel("Back")
            Button { navigateForward() } label: {
                Image(systemName: "chevron.right").frame(width: 15, height: 20)
            }.disabled(forwardHistory.isEmpty).help("Forward").accessibilityLabel("Forward")
            Text(state.page.rawValue).font(.system(size: 14, weight: .semibold)).padding(.leading, 5)
            Spacer()
            if state.page == .dictation { ShortcutBadge(key: state.shortcutKey) }
        }
        .nativeGlassButtons()
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 43)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Search settings…", text: $search)
                    .textFieldStyle(.plain).accessibilityLabel("Search settings")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10).frame(height: 33)
            .background(.black.opacity(0.035), in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.10), lineWidth: 0.5))
            .padding(.horizontal, 10).padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(AppPage.allCases.filter(matchesSearch), id: \.self) { page in
                        Button { state.page = page } label: {
                            HStack(spacing: 9) {
                                Image(systemName: icon(for: page))
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 22, height: 22)
                                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                Text(page.rawValue)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 7).frame(height: 33)
                            .contentShape(Rectangle())
                            .background(state.page == page ? Color.black.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(state.page == page ? [.isSelected] : [])
                        .accessibilityIdentifier("navigation.\(page.rawValue)")
                    }
                    if !AppPage.allCases.contains(where: matchesSearch) {
                        Text("No settings found").foregroundStyle(.secondary).padding(.vertical, 16)
                    }
                }.padding(.horizontal, 10)
            }
            HStack(spacing: 6) {
                Circle().fill(state.canRecord ? Color.green : Color.secondary).frame(width: 5, height: 5)
                Text(state.canRecord ? "Ready" : "API keys required").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(17)
        }
        .frame(width: 224)
        .background { SidebarMaterial().overlay(Color.white.opacity(0.65)) }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
    }

    private func matchesSearch(_ page: AppPage) -> Bool {
        let terms: String
        switch page {
        case .dictation: terms = "transcript record writing copy"
        case .settings: terms = "microphone input airpods bluetooth audio hold tap shortcut fn keyboard paste clipboard language accessibility"
        case .connections: terms = "assemblyai openrouter cerebras credentials api key keychain"
        case .models: terms = "model openrouter cerebras provider"
        case .appearance: terms = "light glow intensity preview bottom indicator"
        }
        return search.trimmingCharacters(in: .whitespaces).isEmpty || (page.rawValue + " " + terms).localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespaces))
    }

    private func icon(for page: AppPage) -> String {
        switch page {
        case .dictation: return "waveform"
        case .settings: return "gearshape"
        case .connections: return "key"
        case .models: return "cpu"
        case .appearance: return "paintpalette"
        }
    }

    private func navigateBack() {
        guard let page = backHistory.popLast() else { return }
        forwardHistory.append(state.page)
        navigatingHistory = true
        state.page = page
    }

    private func navigateForward() {
        guard let page = forwardHistory.popLast() else { return }
        backHistory.append(state.page)
        navigatingHistory = true
        state.page = page
    }

    private var dictation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Writing mode", selection: $state.mode) {
                ForEach(WritingMode.allCases) { mode in Text(mode.title).tag(mode) }
            }.pickerStyle(.segmented).labelsHidden()
                .disabled(state.phase.busy || state.phase == .recording)

            Group {
                if state.output.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: state.phase.busy ? "ellipsis" : "mic")
                            .font(.system(size: 30, weight: .regular)).foregroundStyle(.secondary)
                            .symbolEffect(.variableColor, isActive: state.phase == .recording)
                        Text(state.phase == .recording ? "Listening" : state.phase.busy ? state.phase.label : "No transcript")
                            .font(.system(size: 19, weight: .semibold))
                        Text(state.phase == .recording ? "Release a hold, tap again, or click Finish." : state.phase.busy ? "Processing your recording…" : "Use \(state.shortcutKey.displayName) or click Start dictation to begin.")
                            .foregroundStyle(.secondary)
                        if !state.canRecord {
                            Button("Add API keys") { state.page = .connections }.padding(.top, 4)
                        } else if !state.shortcutAvailable {
                            Button("Set up activation key") { state.page = .settings }.padding(.top, 4)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { transcript }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))

            if let message = state.errorMessage { MessageBanner(text: message, isError: true) }
            if let notice = state.notice { MessageBanner(text: notice) }

            HStack(spacing: 12) {
                Button(action: { state.toggleRecording() }) {
                    Label(state.phase == .recording ? "Finish dictation" : "Start dictation", systemImage: state.phase == .recording ? "stop.fill" : "mic.fill")
                }.nativeGlassButtons(prominent: true).controlSize(.large)
                    .disabled(state.phase.busy).accessibilityIdentifier("dictation.toggle")
                if state.phase.busy || state.phase == .recording || state.phase == .preview || state.phase == .monitoring {
                    Button("Cancel", action: state.cancel)
                } else if state.canRetry {
                    Button("Retry", action: state.retry)
                }
                Spacer()
                if state.phase.busy { ProgressView().controlSize(.small) }
                Text(state.phase == .recording ? state.timeLabel : state.phase.label)
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Text(state.mode == .verbatim ? "AssemblyAI" : "AssemblyAI → \(state.processingProvider?.title ?? "Choose a provider")")
                Spacer()
                if !state.modelUsed.isEmpty { Text(state.modelUsed).lineLimit(1).help(state.routeDescription) }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 25).padding(.bottom, 23)
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(state.showOriginal ? "Original transcript" : "Transcript").fontWeight(.semibold)
                Spacer()
                if state.output != state.rawTranscript {
                    Toggle("Show original", isOn: $state.showOriginal).toggleStyle(.switch).controlSize(.mini)
                }
                Button(action: state.copyResult) {
                    Label(state.copied ? "Copied" : "Copy", systemImage: state.copied ? "checkmark" : "doc.on.doc")
                }.controlSize(.small)
            }
            Divider()
            if state.showOriginal {
                ScrollView {
                    Text(state.rawTranscript).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextEditor(text: $state.output).font(.system(size: 16)).lineSpacing(5)
                    .scrollContentBackground(.hidden).disabled(state.phase.busy).accessibilityLabel("Transcript")
            }
            HStack {
                Text("\(state.wordCount) words")
                Spacer()
                Text(state.routeDescription)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(17)
    }

    private var generalSettings: some View {
        SettingsPage {
            SettingsCard {
                SettingsRow("Activation key") {
                    HStack(spacing: 7) {
                        ShortcutBadge(key: state.shortcutKey)
                        Button(state.isCapturingShortcut ? "Cancel" : "Change…") {
                            if state.isCapturingShortcut { state.cancelShortcutCapture?() }
                            else { state.beginShortcutCapture?() }
                        }.disabled(state.phase.busy || state.phase == .recording)
                        if state.shortcutKey != .function && !state.isCapturingShortcut {
                            Button("Use Fn") { state.shortcutKey = .function }
                        }
                    }
                }
                if state.isCapturingShortcut {
                    SettingsNote("Press a key or combination. Escape cancels.")
                }
                SettingsToggle("Hold to talk", isOn: $state.holdEnabled).help("Release the key to finish.")
                SettingsToggle("Tap to toggle", isOn: $state.tapEnabled).help("Tap once to start, again to finish.")
                if state.shortcutKey.keyCode == 63 {
                    SettingsRow("Fn emoji picker") { Text(state.shortcutAvailable ? "Overridden" : "Not active").foregroundStyle(.secondary) }
                }
                SettingsRow("Accessibility", detail: state.shortcutAccessGranted ? nil : "Required for shortcuts and pasting.") {
                    if state.shortcutAccessGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    } else { Button("Set up dictation…") { state.setUpDictation() } }
                }
            }
            SettingsCard("Text output") {
                SettingsRow("Writing mode") {
                    Picker("Writing mode", selection: $state.mode) {
                        ForEach(WritingMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.labelsHidden().fixedSize().disabled(state.phase.busy || state.phase == .recording)
                }
                SettingsRow("Copy finished text") { Text("Always").foregroundStyle(.secondary) }
                SettingsRow("Paste at cursor") { Text("Automatically").foregroundStyle(.secondary) }
                    .help("Finished dictation copies the text and sends ⌘V. Start returns to your previous app first.")
            }
            MicrophoneSettings(state: state, inputs: state.inputs)
            if !state.shortcutAvailable { SettingsNote(state.shortcutStatus) }
            if let message = state.errorMessage { MessageBanner(text: message, isError: true).padding(.horizontal, 12) }
        }
    }

    private var connectionSettings: some View {
        SettingsPage {
            SettingsCard("Text processing") {
                processingProviderRow
                if let provider = state.processingProvider, provider.requiresAPIKey {
                    SettingsRow("API key") {
                        if provider == .openRouter {
                            SecureField("OpenRouter API key", text: $state.routerKey)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                                .accessibilityIdentifier("settings.routerKey")
                        } else {
                            SecureField("Cerebras API key", text: $state.cerebrasKey)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                                .accessibilityIdentifier("settings.cerebrasKey")
                        }
                    }
                    SettingsRow("macOS Keychain") {
                        Link("Get an API key ↗", destination: URL(string: provider == .openRouter ? "https://openrouter.ai/settings/keys" : "https://cloud.cerebras.ai/platform/")!)
                        saveKeyButton(account: provider.rawValue, isEmpty: state.processingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            SettingsCard("Speech to text · AssemblyAI") {
                SettingsRow("API key") {
                    SecureField("AssemblyAI API key", text: $state.assemblyKey)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        .accessibilityIdentifier("settings.assemblyKey")
                }
                SettingsRow("macOS Keychain") {
                    Link("Get an API key ↗", destination: URL(string: "https://www.assemblyai.com/dashboard/signup")!)
                    saveKeyButton(account: "assemblyai", isEmpty: state.assemblyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            SettingsNote("AssemblyAI receives your recording. Only your selected processing provider receives the transcript. Verbatim mode skips processing.")
            if let message = state.errorMessage { MessageBanner(text: message, isError: true).padding(.horizontal, 12) }
            if let notice = state.notice { MessageBanner(text: notice).padding(.horizontal, 12) }
        }
    }

    private func saveKeyButton(account: String, isEmpty: Bool) -> some View {
        let saved = state.savedKeyAccounts.contains(account)
        return Button { state.saveAPIKey(account: account) } label: {
            HStack(spacing: 5) {
                if saved { Image(systemName: "checkmark") }
                Text(saved ? "Saved" : "Save API key")
            }.frame(minWidth: 88)
        }
        .nativeGlassButtons(prominent: true)
        .disabled(isEmpty)
        .accessibilityIdentifier("settings.save.\(account)")
        .accessibilityLabel(saved ? "Saved to Keychain" : "Save API key")
    }

    private var processingProviderRow: some View {
        SettingsRow("Provider") {
            Picker("Text processing provider", selection: $state.processingProvider) {
                ForEach(ProcessingProvider.allCases) { provider in Text(provider.title).tag(Optional(provider)).accessibilityIdentifier("provider.\(provider.rawValue)") }
            }.pickerStyle(.menu).labelsHidden().frame(width: 220)
                .disabled(state.phase.busy || state.phase == .recording)
                .accessibilityIdentifier("settings.processingProvider")
        }
    }

    private var processingProviderSettings: some View {
        SettingsCard("Text processing") { processingProviderRow }
    }

    private var modelSettings: some View {
        SettingsPage {
            processingProviderSettings
            if let provider = state.processingProvider {
                SettingsCard("Selected model") {
                    SettingsRow("Model ID") {
                        TextField(provider.defaultModel, text: $state.processingModel).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    }
                    if provider == .openRouter {
                        SettingsRow("Endpoint") {
                            TextField("cerebras/fp16", text: $state.routerEndpoint).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        }
                    }
                    if provider.requiresAPIKey { SettingsRow("Model catalog") { Link("Browse models ↗", destination: provider.modelCatalogURL) } }
                }
                SettingsNote("Every rewrite uses your selected model.")
            }
        }
    }

    private var appearanceSettings: some View {
        SettingsPage {
            SettingsCard {
                SettingsRow("Appearance") { Label("Light", systemImage: "sun.max").foregroundStyle(.secondary) }
            }
            SettingsCard("Recording indicator") {
                SettingsRow("Position") { Text("Bottom of the screen").foregroundStyle(.secondary) }
                SettingsRow("Glow intensity") {
                    Slider(value: $state.glowStrength, in: 0.25...1.3).controlSize(.regular).tint(.blue).frame(width: 200).accessibilityLabel("Glow intensity").accessibilityIdentifier("glow.intensity")
                }
                ZStack(alignment: .bottom) {
                    Color.white
                    BottomGlow(level: 0.45, strength: state.glowStrength, phase: .preview, timeOverride: 1.8, response: state.glowResponseSettings)
                }
                .frame(height: 135).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                .padding(12)
                SettingsRow("Preview", detail: "Try the glow without your microphone.") {
                    Button(state.phase == .preview ? "Stop preview" : "Preview") {
                        if state.phase == .preview { state.cancel() } else { state.previewGlow() }
                    }.disabled(state.phase.busy || state.phase == .recording).accessibilityIdentifier("glow.preview")
                }
            }
            SettingsNote("The glow responds to your voice. A thin moving line appears while processing. Reduce Motion keeps the glow steady.")
        }
    }
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
        }
        .nativeGlassButtons()
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String?
    var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12) }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: 13))
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String?
    var content: Content
    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            content
        }
        .padding(.vertical, detail == nil ? 10 : 12)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.045)).frame(height: 0.5) }
        .padding(.horizontal, 12)
    }
}

private struct SettingsToggle: View {
    var title: String
    var detail: String?
    @Binding var isOn: Bool
    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }
    var body: some View {
        SettingsRow(title, detail: detail) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

private struct SettingsNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12).padding(.vertical, 2)
    }
}

struct MessageBanner: View {
    let text: String
    var isError = false
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } icon: {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(isError ? Color.orange : Color.secondary)
        }.font(.system(size: 12)).lineSpacing(2)
    }
}

struct ShortcutBadge: View {
    var key: ShortcutKey = .function
    var body: some View {
        HStack(spacing: 5) {
            if key.keyCode == 63 { Image(systemName: "globe").font(.system(size: 11)) }
            Text(key.displayName).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        
        .foregroundStyle(.secondary)
        .accessibilityLabel("Activation key: \(key.displayName)")
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct MicrophoneSettings: View {
    @ObservedObject var state: AppState
    @ObservedObject var inputs: AudioInputs
    var body: some View {
        SettingsCard("Recording") {
            SettingsRow("Microphone") {
                Picker("Microphone input", selection: $state.microphoneUID) {
                    Text("Automatic · \(inputs.defaultName)").tag("")
                    ForEach(inputs.devices) { device in Text(device.name).tag(device.id) }
                    if !state.microphoneUID.isEmpty && !inputs.devices.contains(where: { $0.id == state.microphoneUID }) {
                        Text("Selected microphone is disconnected").tag(state.microphoneUID)
                    }
                }.labelsHidden().frame(maxWidth: 290)
                    .help("Automatic prefers your Mac's built-in microphone. You can choose another input, including AirPods.")
                    .disabled(state.phase.busy || state.phase == .recording)
                    .onChange(of: state.microphoneUID) { _, _ in
                        if state.phase == .monitoring { state.cancel(); state.testMicrophone() }
                    }
            }
            SettingsRow("Input level") {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: state.phase != .monitoring && state.phase != .recording)) { _ in
                    ProgressView(value: state.glowLevel).progressViewStyle(.linear).frame(width: 90)
                }
                Button(state.phase == .monitoring ? "Stop test" : "Test microphone", action: state.testMicrophone)
                    .disabled(state.phase.busy || state.phase == .recording)
                    .help("Test locally for 15 seconds. No audio is saved or sent.")
            }
            if inputs.devices.first(where: { $0.id == state.microphoneUID })?.isBluetooth == true {
                SettingsNote("This Bluetooth microphone may lower headphone playback quality. Automatic uses your Mac's microphone when available.")
                    .padding(.vertical, 8)
            }
            SettingsRow("Speech recognition") {
                Picker("Speech recognition", selection: $state.transcriptionMode) {
                    ForEach(TranscriptionMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.labelsHidden().fixedSize().disabled(state.phase.busy || state.phase == .recording)
                    .help("Fast dictation supports 19 languages, including English and German. Choose Extended for other languages. Recordings can last up to 10 minutes.")
            }
            SettingsRow("Language") { Text("Detect automatically").foregroundStyle(.secondary) }
        }
    }
}
