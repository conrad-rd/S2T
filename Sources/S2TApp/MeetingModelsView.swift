import SwiftUI
import S2TCore

struct MeetingModelsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var meetings: MeetingRecorder
    var back: () -> Void
    @State private var search = ""
    @State private var hosts: [OpenRouterHost] = []
    @State private var codexModels: [CodexModel] = []
    @State private var catalogError = ""
    @State private var reasoningRevision = 0
    private var provider: ProcessingProvider { meetings.textSettings.selectedProvider }
    private var codexModel: CodexModel? { codexModels.first { $0.slug == meetings.textSettings.model } }
    private var reasoningChoices: [(String, String)] {
        _ = reasoningRevision
        if provider == .codex { return [("", "Model default")] + (codexModel?.supported_reasoning_levels.map { ($0.effort, $0.effort.capitalized) } ?? []) }
        if provider == .openRouter { return OpenRouterOptions.supportedEfforts(for: meetings.textSettings.model).map { ($0.rawValue, $0.title) } }
        return [("", "Model default")]
    }
    private var suggestions: [ModelSuggestion] {
        switch provider {
        case .openRouter:
            let choices = meetings.textModels.isEmpty ? ModelSuggestion.cleanup : meetings.textModels.map { model in
                ModelSuggestion(model: model.id, title: model.name, host: ModelSuggestion.cleanup.first { $0.model == model.id }?.host ?? "")
            }
            return choices.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.model.localizedCaseInsensitiveContains(search) }
        case .codex: return codexModels.filter { $0.visibility == "list" }.map { .init(model: $0.slug, title: $0.display_name) }
        case .xai: return [.init(model: ProcessingProvider.xai.defaultModel, title: "Grok")]
        case .local: return []
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button(action: back) { Label("Meetings", systemImage: "chevron.left") }
                    .accessibilityIdentifier("meetings.models.back")
                Text("Meeting models").font(.system(size: 22, weight: .semibold))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech to text").font(.headline)
                    MeetingSpeechChoices(state: state, meetings: meetings)

                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text processing").font(.headline)
                    Toggle("Clean up each transcript part", isOn: $meetings.textSettings.enabled)
                        .toggleStyle(.switch).controlSize(.regular).tint(.blue).accessibilityIdentifier("meetings.processing.enabled")
                    MeetingModelPicker(label: "Text processing provider", identifier: "meetings.processing.provider",
                        choices: ProcessingProvider.allCases.filter { state.isProviderVisible($0.rawValue) }.map { ($0.rawValue, $0.requiresAPIKey ? $0.title + " · Personal API key" : $0.title) },
                        selection: $meetings.textSettings.provider, includeUnlistedSelection: false)
                    if state.isProviderVisible(provider.rawValue) {
                        if provider == .openRouter {
                            HStack {
                                TextField("Find a model", text: $search).accessibilityIdentifier("meetings.processing.search")
                                Button("Refresh") { meetings.loadTextModels(preview: state.isPreview, refresh: true) }.disabled(meetings.loadingModels)
                                if meetings.loadingModels { ProgressView().controlSize(.small) }
                            }
                            if !meetings.modelCatalogError.isEmpty { Text(meetings.modelCatalogError).font(.caption).foregroundStyle(.secondary) }
                        }
                        if !suggestions.isEmpty {
                            MeetingModelPicker(label: "Text processing model", identifier: "meetings.processing.model",
                                choices: suggestions.map { ($0.model, $0.title) }, selection: Binding(get: { meetings.textSettings.model }, set: { value in
                                    meetings.textSettings.model = value
                                    if provider == .openRouter, let suggestion = suggestions.first(where: { $0.model == value }) { meetings.textSettings.host = suggestion.host }
                                }))
                        }

                        LabeledContent("Model ID") {
                            TextField("Model ID", text: $meetings.textSettings.model).accessibilityIdentifier("meetings.processing.modelID")
                        }
                        if provider == .openRouter {
                            if !hosts.isEmpty {
                                Picker("Hosting provider", selection: $meetings.textSettings.host) {
                                    Text("Automatic").tag("")
                                    if !meetings.textSettings.host.isEmpty && !hosts.contains(where: { $0.tag == meetings.textSettings.host }) {
                                        Text(meetings.textSettings.host).tag(meetings.textSettings.host)
                                    }
                                    ForEach(hosts, id: \.tag) { Text($0.provider_name + " · " + $0.tag).tag($0.tag) }
                                }
                            }
                            LabeledContent("Host") {
                                TextField("Automatic", text: $meetings.textSettings.host).accessibilityIdentifier("meetings.processing.host")
                            }
                        }
                        if provider == .local {
                            LabeledContent("Endpoint") {
                                TextField(LocalEndpoint.defaultProcessingURL, text: $meetings.textSettings.localURL).accessibilityIdentifier("meetings.processing.endpoint")
                            }
                        }
                        if provider == .codex || provider == .openRouter {
                            Picker("Reasoning", selection: Binding(get: {
                                provider == .codex ? codexModel?.normalized(meetings.textSettings.codex).reasoning ?? "" : meetings.textSettings.router.reasoning.rawValue
                            }, set: { value in
                                if provider == .codex { meetings.textSettings.codex.reasoning = value }
                                else { meetings.textSettings.router.reasoning = OpenRouterOptions.Effort(rawValue: value) ?? .automatic }
                            })) {
                                ForEach(reasoningChoices, id: \.0) { Text($0.1).tag($0.0) }
                            }.disabled(reasoningChoices.count <= 1).accessibilityIdentifier("meetings.processing.reasoning")
                            Toggle(provider == .codex ? "Fast mode" : "Fast routing", isOn: Binding(get: {
                                provider == .codex ? codexModel?.normalized(meetings.textSettings.codex).fast ?? false : meetings.textSettings.router.fast
                            }, set: { value in
                                if provider == .codex { meetings.textSettings.codex.fast = value }
                                else { meetings.textSettings.router.fast = value }
                            })).disabled(provider == .codex && codexModel?.supportsFast != true)
                                .toggleStyle(.switch).controlSize(.regular).tint(.blue)
                        }
                        if provider == .openRouter && meetings.textSettings.model == OpenRouterOptions.contributorModel {
                            Toggle("Allow Meta to use prompts and responses", isOn: $meetings.textSettings.router.allowDataCollection)
                                .toggleStyle(.switch).controlSize(.regular).tint(.blue)
                        }
                        if provider == .codex {
                            Text("Uses the Codex executable and login configured in Models.").font(.caption).foregroundStyle(.secondary)
                            Button("Refresh models") { loadCodexModels() }
                            if !catalogError.isEmpty { Text(catalogError).foregroundStyle(.secondary) }
                        }
                    } else {
                        Text("Your current provider is hidden. Choose a visible provider above to change it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Keeps speakers and timestamps. Original transcripts remain available if processing fails. These settings apply to new meetings.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(meetings.isActive)
            }.padding(24)
        }
        .nativeGlassButtons().buttonBorderShape(.capsule)
        .accessibilityIdentifier("meetings.models")
        .task { loadCodexModels(); meetings.loadTextModels(preview: state.isPreview) }
        .task(id: meetings.textSettings.provider + meetings.textSettings.model) {
            guard provider == .openRouter, !state.isPreview else { return }
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            let model = meetings.textSettings.model
            hosts = []
            await OpenRouterReasoningCatalog.shared.refresh(model: model)
            reasoningRevision += 1
            if let loaded = try? await OpenRouterHost.load(model: model), !Task.isCancelled, meetings.textSettings.model == model { hosts = loaded }
        }
    }
    private func loadCodexModels() {
        guard !state.isPreview else { return }
        Task {
            do { codexModels = try await Task.detached { try CodexModelCatalog.read() }.value; catalogError = "" }
            catch { catalogError = "Open Codex once to populate its model list. You can also enter a model ID." }
        }
    }
}

struct MeetingSpeechChoices: View {
    @ObservedObject var state: AppState
    @ObservedObject var meetings: MeetingRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Provider") {
                MeetingModelPicker(label: "Speech to text provider", identifier: "meetings.speech.provider",
                    choices: [("assemblyai", "AssemblyAI"), ("xai", "xAI · Grok")].filter { state.isProviderVisible($0.0) },
                    selection: Binding(get: { meetings.model.provider.rawValue }, set: { value in
                        meetings.selectSpeechProvider(value)
                    }), includeUnlistedSelection: false)
            }
            if state.isProviderVisible(meetings.model.provider.rawValue) {
                LabeledContent("Voice model") {
                    MeetingModelPicker(label: "Speech to text model", identifier: "meetings.speech.model",
                        choices: MeetingModel.allCases.filter { $0.provider == meetings.model.provider }.map { ($0.rawValue, $0.title) },
                        selection: Binding(get: { meetings.model.rawValue }, set: { if let model = MeetingModel(rawValue: $0) { meetings.model = model } }))
                }
                Text("Speaker separation · Your \(meetings.model.provider.title) API key")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(meetings.isActive)
    }
}
