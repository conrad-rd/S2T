import AppKit
import SwiftUI
import S2TCore

struct SettingsNavigationRow: View {
    let title: String
    var summary: String = ""
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13))
                        .frame(width: 20).foregroundStyle(.secondary)
                }
                Text(title).foregroundStyle(.primary).fixedSize()
                Spacer(minLength: 16)
                if !summary.isEmpty {
                    Text(summary).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(summary.isEmpty ? title : title + ", " + summary)
    }
}

/// The Compare models sub-page: benchmark rankings for models S2T can use. Scores never change settings.
struct ModelsComparisonView: View {
    @ObservedObject var state: AppState
    @ObservedObject var navigation: ModelsNavigation
    @StateObject private var feed: BenchmarkFeed
    @StateObject private var benchmarks = ModelBenchmarkPresentation()

    init(state: AppState, navigation: ModelsNavigation) {
        self.state = state; self.navigation = navigation
        _feed = StateObject(wrappedValue: BenchmarkFeed(preview: state.isPreview))
    }

    private var benchmarkOfferings: [BenchmarkOffering] {
        var offers = state.creditModels.filter { state.isProviderVisible("s2t") && state.isProviderVisible($0.provider) && ["transcription", "cleanup"].contains($0.operation) }.map {
            BenchmarkOffering(id: $0.provider == "openrouter" ? $0.model : $0.provider + "/" + $0.model,
                              name: $0.title, task: $0.operation == "transcription" ? "speech" : "text")
        }
        if state.isProviderVisible("openrouter") {
            offers += (ModelSuggestion.cleanup + ModelRecommendations.cleanup).map { BenchmarkOffering(id: $0.model, name: $0.title, task: "text") }
            offers += state.routerSpeechModels.map { BenchmarkOffering(id: "openrouter/" + $0.id, name: $0.name, task: "speech") }
        }
        offers += [
            .init(id: "assemblyai/universal-3-pro", name: "Universal 3 Pro", task: "speech"),
            .init(id: "assemblyai/universal-2", name: "Universal", task: "speech"),
            .init(id: "assemblyai/universal-3-5-pro", name: "Universal 3.5 Pro", task: "speech")
        ]
        if state.isProviderVisible("xai") {
            offers += [
                .init(id: "xai/grok-voice-transcribe-2.0", name: "Grok Transcribe 2", task: "speech"),
                .init(id: "xai/grok-voice-transcribe-1.0", name: "Grok Transcribe 1", task: "speech"),
                .init(id: ProcessingProvider.xai.defaultModel, name: "Grok 4.6", task: "text")
            ]
        }
        offers += BenchmarkCatalog.models(local: state.localModels.catalog).filter { $0.provider == "Local" && state.isProviderVisible("local") }.map {
            BenchmarkOffering(id: $0.id, name: $0.name, task: $0.task)
        }
        return offers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsChoiceBar(titles: ["Speech", "Cleanup"], selected: benchmarks.task == "speech" ? 0 : 1,
                                  label: "Task") { benchmarks.task = $0 == 0 ? "speech" : "text" }
                .accessibilityIdentifier("models.compare.task")
                ModelBenchmarkView(presentation: benchmarks, local: state.localModels.catalog,
                        compact: true, hiddenProviders: state.hiddenProviders,
                        suppliedModels: BenchmarkAvailability.filter(feed.models(local: state.localModels.catalog), offered: benchmarkOfferings).filter { state.isProviderVisible($0.provider) },
                        status: feed.status(for: benchmarks.task), warning: feed.snapshot?.warning,
                        loading: feed.loading, refresh: { Task { await feed.refresh(key: state.artificialAnalysisKey, force: true) } })
            }.padding(24)
        }
        .background(SettingsPageBackground())
        .onAppear { benchmarks.task = benchmarkTask }
        .onChange(of: navigation.section) { _, _ in benchmarks.task = benchmarkTask }
        .task { await state.refreshSpeechCatalog() }
        .task(id: state.artificialAnalysisKey) {
            if !state.isPreview { await feed.refresh(key: state.artificialAnalysisKey) }
        }
    }

    private var benchmarkTask: String {
        switch navigation.section {
        case .speech: "speech"
        case .cleanup, .local: "text"
        }
    }
}
