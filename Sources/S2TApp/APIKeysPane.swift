import AppKit
import SwiftUI
import S2TCore

@MainActor final class APIKeysPane: NSViewController {
    static let accounts: [APIAccount] = [.openRouter, .xai, .assemblyAI, .typeSafe]
    let editing: APIKeyEditing
    init(state: AppState) {
        editing = APIKeyEditing(state: state)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let host = NSHostingView(rootView: APIKeysView(state: editing.state, editing: editing))
        host.sizingOptions = []
        view = host
    }
    func refresh() { if !editing.enabled { editing.endEditing() } }
}

@MainActor final class APIKeyEditing: ObservableObject {
    let state: AppState
    @Published private(set) var drafts: [String: String] = [:]
    @Published private(set) var account: String?
    @Published private(set) var pasteNotice: String?
    var layout: [String: CGRect] = [:]

    init(state: AppState) { self.state = state }
    var enabled: Bool { !state.savedKeysLocked }
    func value(_ id: String) -> String { drafts[id] ?? state.keyValue(id) }
    func beginEditing(_ id: String) { if enabled { if account != id { endEditing() }; account = id } }
    func endEditing(commit: Bool = true) {
        let previous = account
        account = nil
        if commit, let previous { save(previous) }
    }
    func change(_ value: String, for id: String) {
        guard enabled else { return }
        drafts[id] = value
        pasteNotice = nil
    }
    func paste(_ value: String?, for id: String) {
        guard enabled else { return }
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            pasteNotice = id
            return
        }
        change(value, for: id)
    }
    func status(_ id: String) -> APIKeyStatus? { drafts[id] == nil ? state.keyStatuses[id] : nil }
    func saved(_ id: String) -> Bool { drafts[id] == nil && state.savedKeyAccounts.contains(id) }
    func canSave(_ id: String) -> Bool {
        let value = value(id).trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = drafts[id] != nil && value != state.keyValue(id)
        return enabled && !state.phase.busy && state.phase != .recording &&
            (changed || !value.isEmpty && (!saved(id) || status(id)?.needsAttention == true)) && status(id) != .checking
    }
    func message(_ id: String) -> String {
        if pasteNotice == id { return "Copy an API key, then click Paste." }
        if drafts[id] != nil {
            if state.phase.busy || state.phase == .recording { return "Finish dictation to save this key." }
            if value(id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let status = state.keyStatuses[id], status.needsAttention { return status.message }
            return ""
        }
        if let status = status(id), status.needsAttention { return status.message }
        return ""
    }
    func save(_ id: String) {
        guard canSave(id) else { return }
        endEditing(commit: false)
        let key = value(id).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            if state.clearAPIKey(account: id) { drafts[id] = nil }
            return
        }
        switch id {
        case "artificialanalysis": state.artificialAnalysisKey = key
        case "assemblyai": state.assemblyKey = key
        case "xai": state.xaiKey = key
        case "openrouter": state.routerKey = key
        case "typesafe": state.typeSafeKey = key
        case "s2t": state.creditsKey = key
        default: return
        }
        state.saveAPIKey(account: id)
        drafts[id] = nil
    }
}

private struct KeyLayout: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private extension View {
    func keyLayout(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: KeyLayout.self, value: [id: proxy.frame(in: .named("apiKeys"))])
        })
    }
}

struct APIKeysView: View {
    @ObservedObject var state: AppState
    @ObservedObject var editing: APIKeyEditing

    var body: some View {
        Form {
            if state.isProviderVisible("s2t") {
                Section("S2T credits") {
                    APIKeyRow(id: "s2t", title: "S2T key", state: state, editing: editing)
                }
            }
            Section("Personal API keys") {
                ForEach(APIKeysPane.accounts.filter { state.isProviderVisible($0.rawValue) }, id: \.rawValue) { provider in
                    APIKeyRow(id: provider.rawValue, title: provider.title, state: state, editing: editing)
                }
            }
            if state.savedKeysLocked || state.clipboardMonitor.persistenceError != nil {
                Section {
                    Button("Unlock saved keys…") { state.loadSavedKeys(allowInteraction: true) }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .background(.background)
        .nativeGlassButtons()
        .coordinateSpace(name: "apiKeys")
        .onPreferenceChange(KeyLayout.self) { editing.layout = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in editing.endEditing() }
        .onChange(of: editing.enabled) { _, enabled in if !enabled { editing.endEditing() } }
        .onDisappear { editing.endEditing() }
        .task { await state.refreshCredits() }
    }
}

private struct APIKeyRow: View {
    let id: String
    let title: String
    @ObservedObject var state: AppState
    @ObservedObject var editing: APIKeyEditing
    @FocusState private var focused: Bool
    private var revealed: Bool { editing.account == id }
    private var value: Binding<String> { Binding(get: { editing.value(id) }, set: { editing.change($0, for: id) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).fontWeight(.medium)
                    .fixedSize(horizontal: true, vertical: false)
                    .keyLayout("title." + id)
                Spacer(minLength: 0)
                SecureField("\(title) API key", text: value, prompt: Text("Add key"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { editing.save(id); focused = false }
                    .onExitCommand { editing.endEditing(commit: false); focused = false }
                    .help("Saved when you press Return or leave the field. Empty the field to remove this key.")
                    .frame(minWidth: 160, maxWidth: 320)
                    .accessibilityLabel("\(title) API key")
                    .accessibilityIdentifier("keys.field.\(id)")
                    .keyLayout("field.\(id)")
                if editing.status(id) == .checking {
                    ProgressView().controlSize(.small).accessibilityLabel("Checking \(title) key")
                }
            }
            .frame(minHeight: 28)
            .disabled(!editing.enabled)
            if !editing.message(id).isEmpty {
                Text(editing.message(id))
                    .font(.callout)
                    .foregroundStyle(editing.status(id)?.needsAttention == true ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .keyLayout("status.\(id)")
            }
            if id == "typesafe" && editing.value(id).isEmpty {
                HStack(spacing: 8) {
                    Text("Used for Jev cleanup decisions.")
                        .foregroundStyle(.secondary)
                    Link("Get a TypeSafe key", destination: URL(string: "https://console.typesafe.ai/")!)
                }
                .font(.caption)
            }
        }
        .keyLayout("row." + id)
        .onChange(of: focused) { _, focused in
            if focused { editing.beginEditing(id) }
            else if revealed { editing.endEditing() }
        }
        .onChange(of: revealed) { _, revealed in focused = revealed }
        .onAppear { focused = revealed }
    }
}
