import SwiftUI
import S2TCore

@MainActor final class ModelBenchmarkPresentation: ObservableObject {
    @Published var task = "speech" {
        didSet {
            basis = task == "speech" ? .speech : .intelligence
            selected = nil
        }
    }
    @Published var basis: BenchmarkQuality = .speech { didSet { selected = nil } }
    @Published var enabled: Set<BenchmarkCategory> = [.quality] { didSet { selected = nil } }
    var layout: [String: CGRect] = [:]
    @Published var selected: String?
    func toggle(_ category: BenchmarkCategory) -> Binding<Bool> {
        Binding(get: { self.enabled.contains(category) }, set: {
            if $0 { self.enabled.insert(category) } else { self.enabled.remove(category) }
        })
    }
}

struct ModelBenchmarkView: View {
    @ObservedObject var presentation: ModelBenchmarkPresentation
    let local: [LocalModel]
    var compact = false
    var hiddenProviders = Set<String>()
    var suppliedModels: [BenchmarkModel]? = nil
    var status: String = "Reference data · " + BenchmarkCatalog.checkedAt
    var warning: String? = nil
    var loading = false
    var refresh: (() -> Void)? = nil
    @State private var showingAll = false
    @State private var showingSources = false
    @State private var showingUnranked = false
    private var models: [BenchmarkModel] { (suppliedModels ?? BenchmarkCatalog.models(local: local)).filter { $0.task == presentation.task } }
    private var basis: BenchmarkQuality {
        presentation.basis
    }
    private var ranked: [BenchmarkStanding] { BenchmarkRanking.rank(models, enabled: presentation.enabled, quality: basis) }
    private var standings: [BenchmarkStanding] { BenchmarkRanking.top(ranked) }
    private var unranked: [BenchmarkModel] {
        let ranked = Set(ranked.map(\.id))
        return models.filter { !ranked.contains($0.id) }
    }
    private func opacity(_ category: BenchmarkCategory) -> Double {
        switch category { case .quality: return 1; case .speed: return 0.6; case .cost: return 0.3 }
    }
    private func missing(_ model: BenchmarkModel) -> String {
        BenchmarkCategory.allCases.filter {
            presentation.enabled.contains($0) && model.measurement($0, quality: basis) == nil
        }.map { $0 == .quality ? basis.title : $0.title.lowercased() }.joined(separator: ", ")
    }

    var body: some View {
        if compact { compactBody }
        else { fullBody }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 22) {
                ForEach(BenchmarkCategory.allCases, id: \.self) { category in
                    Toggle(category.title, isOn: presentation.toggle(category))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .accessibilityIdentifier("benchmarks." + category.rawValue)
                }
                Spacer(minLength: 0)
            }
            Group {
                if presentation.enabled.isEmpty { Text("Select a score to compare.").foregroundStyle(.secondary) }
                else if standings.isEmpty { Text("No comparable results.").foregroundStyle(.secondary) }
                else { compactChart }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            if !standings.isEmpty {
                Text("Relative scores. 0 is the lowest measured result in this set.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button("All models") { showingAll = true }
                    .popover(isPresented: $showingAll, arrowEdge: .bottom) { allResults }
                Button("How scores work") { showingSources = true }
                    .popover(isPresented: $showingSources, arrowEdge: .bottom) { sources }
                Spacer()
                if let refresh { Button(loading ? "Refreshing…" : "Refresh", action: refresh).disabled(loading) }
            }
            .font(.system(size: 11)).buttonStyle(.borderless)
            Text(status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).help(status)
            if let warning { Text(warning).font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityIdentifier("models.overview.benchmarks")
    }

    private var compactChart: some View {
        VStack(spacing: 5) {
            ForEach(standings) { standing in
                Button { presentation.selected = standing.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Text(standing.model.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(standing.total.formatted(.number.precision(.fractionLength(0))))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        GeometryReader { geometry in
                            Capsule().fill(Color.primary.opacity(0.09))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.65))
                                        .frame(width: geometry.size.width * CGFloat(min(100, max(0, standing.total))) / 100)
                                }
                        }
                        .frame(height: 4)
                    }
                    .padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(standing.model.name), relative score \(standing.total.formatted(.number.precision(.fractionLength(0)))) out of 100")
                .popover(isPresented: Binding(get: { presentation.selected == standing.id },
                                              set: { if !$0 { presentation.selected = nil } }), arrowEdge: .top) {
                    details(standing)
                }
            }
        }
        .accessibilityIdentifier("benchmarks.chart")
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Compare models").font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("Task", selection: $presentation.task) {
                    Text("Speech").tag("speech")
                    Text("Cleanup").tag("text")
                }.labelsHidden().fixedSize()
                .accessibilityIdentifier("benchmarks.task")
            }
            Text("Top five by the scores you select. Comparing does not change your models.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Relative scores. 0 is the lowest measured result in this set.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                ForEach(BenchmarkCategory.allCases, id: \.self) { category in
                    HStack(spacing: 7) {
                        Text(category.title).foregroundStyle(.secondary)
                        Toggle(category.title, isOn: presentation.toggle(category))
                            .labelsHidden()
                            .benchmarkLayout("switch." + category.rawValue)
                            .accessibilityIdentifier("benchmarks." + category.rawValue)
                    }
                    .help(category == .speed ? (presentation.task == "speech" ? "Audio processed per second relative to real time." : "Output tokens per second.") : category.title)
                }
                Spacer(minLength: 0)
            }
            .toggleStyle(.switch).controlSize(.small)
            .benchmarkLayout("controls")
            Group {
                if presentation.enabled.isEmpty {
                    Text("Choose a score to compare.").foregroundStyle(.secondary)
                } else if standings.isEmpty {
                    Text("No comparable results.").foregroundStyle(.secondary)
                } else {
                    chart
                }
            }
            .frame(maxWidth: .infinity, minHeight: 310, maxHeight: 310)
            .benchmarkLayout("plot")
            HStack(spacing: 16) {
                Button("All \(Set(models.map { $0.modelID ?? $0.id }).count) models") { showingAll = true }
                    .popover(isPresented: $showingAll, arrowEdge: .bottom) { allResults }
                Button { showingSources = true } label: {
                    HStack(spacing: 5) {
                        Text("How scores work")
                        Image(systemName: "info.circle")
                    }
                }
                .popover(isPresented: $showingSources, arrowEdge: .bottom) { sources }
                Spacer()
                if !unranked.isEmpty && !presentation.enabled.isEmpty {
                    Button("\(unranked.count) missing data") { showingUnranked = true }
                        .popover(isPresented: $showingUnranked, arrowEdge: .bottom) { missingResults }
                }
            }
            .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Link("Artificial Analysis", destination: URL(string: "https://artificialanalysis.ai/")!)
                Text(status).foregroundStyle(.secondary).lineLimit(1).help(status)
                Spacer(minLength: 0)
                if let refresh {
                    Button(loading ? "Refreshing…" : "Refresh", action: refresh).disabled(loading)
                }
            }.font(.caption).buttonStyle(.borderless)
            if let warning { Text(warning).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.top, 12).padding(.bottom, 22)
        .accessibilityIdentifier("models.overview.benchmarks")
        .coordinateSpace(name: "benchmark")
        .onPreferenceChange(BenchmarkLayout.self) { presentation.layout = $0 }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(standings) { standing in
                Button { presentation.selected = standing.id } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            Text(String(standing.rank))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 19, alignment: .leading)
                            Text(standing.model.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(standing.model.provider)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(standing.total.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        HStack(spacing: 3) {
                            ForEach(0..<30, id: \.self) { index in
                                Capsule()
                                    .fill(strokeColor(standing, index: index))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 4)
                            }
                        }
                        .padding(.leading, 28)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) {
                    Color.clear.frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .benchmarkLayout("anchor." + standing.id)
                        .popover(isPresented: Binding(
                            get: { presentation.selected == standing.id },
                            set: { if !$0 && presentation.selected == standing.id { presentation.selected = nil } }
                        ), attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                            details(standing)
                        }
                }
                if standing.id != standings.last?.id {
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .benchmarkLayout("chart")
        .accessibilityIdentifier("benchmarks.chart")
    }

    private func strokeColor(_ standing: BenchmarkStanding, index: Int) -> Color {
        guard let tick = ticks(standing).first(where: { $0.id == index }) else {
            return Color.primary.opacity(0.08)
        }
        return Color.primary.opacity(opacity(tick.category) * 0.88)
    }

    private func details(_ standing: BenchmarkStanding) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(standing.model.name).font(.headline)
                    Text(standing.model.provider).foregroundStyle(.secondary)
                }
                Spacer()
                Text(standing.total.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .accessibilityLabel("Relative score \(standing.total.formatted()) out of 100")
            }
            ForEach(BenchmarkCategory.allCases, id: \.self) { category in
                if let contribution = standing.contributions[category],
                   let measurement = standing.model.measurement(category, quality: basis) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(opacity(category))).frame(width: 20, height: 7)
                            Text(category.title)
                            Spacer()
                            Text("+" + contribution.formatted(.number.precision(.fractionLength(1)))).monospacedDigit()
                        }
                        Text(standing.model.formatted(category, quality: basis)).foregroundStyle(.secondary)
                        if let url = URL(string: measurement.source) {
                            Link(measurement.note, destination: url).font(.caption)
                        }
                    }
                }
            }
        }.font(.system(size: 12)).padding(20).frame(width: 360)
    }

    private var allResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All models").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(BenchmarkRanking.top(ranked, limit: ranked.count)) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.model.name)
                                Text(row.model.provider).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.total.formatted(.number.precision(.fractionLength(1))))
                        }
                    }
                    ForEach(unranked) { model in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name + " · " + model.provider)
                            Text("Missing " + missing(model)).foregroundStyle(.secondary)
                        }
                    }
                }.font(.caption)
            }.frame(height: 340)
        }.padding(20).frame(width: 400)
    }

    private var missingResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Missing measurements").font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(unranked) { model in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name + " · " + model.provider)
                            Text("Missing " + missing(model)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
        }.padding(20).frame(width: 340)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sources and scoring").font(.headline)
            if presentation.task == "speech" {
                Picker("Quality", selection: $presentation.basis) {
                    Text(BenchmarkQuality.speech.title).tag(BenchmarkQuality.speech)
                    Text(BenchmarkQuality.fleurs.title).tag(BenchmarkQuality.fleurs)
                }
            } else {
                Text(basis.title).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Enabled categories have equal weight. The five highest-scoring distinct models are shown. Where named-host measurements are available, each model uses its best host for the enabled categories. Best is at the top. Each category scales from 0 to 100; the total is their average. Lower error and cost score higher. Missing measurements are excluded, and ties share a place. Bars round to whole strokes; selecting a model shows exact scores.")
                    Text("Bundled references checked " + BenchmarkCatalog.checkedAt + ". Live API results replace references for each available task. Text speed uses output tokens per second, never time to first token. AA reference denotes the free API’s model-level result with no measured host identity. Named-host measurements stay separate and never inherit a model average. Speech speed is audio duration divided by processing time, not TPS. Different quality benchmarks are never combined.")
                    Text("Cloud speed and cost refer to the cited API."
                        + (hiddenProviders.contains("openrouter") ? "" : " They do not measure OpenRouter routing.")
                        + (hiddenProviders.contains("s2t") ? "" : " They exclude S2T credits."))
                    if !hiddenProviders.contains("local") {
                        Text("Local speed is unmeasured and local cost counts API fees only. Parent-model quality can differ from local quantization.")
                    }
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.name + " · " + model.provider).fontWeight(.medium)
                            ForEach(BenchmarkCategory.allCases, id: \.self) { category in
                                if let measurement = model.measurement(category, quality: basis), let url = URL(string: measurement.source) {
                                    Link(category.title + ": " + model.formatted(category, quality: basis) + " · " + measurement.note, destination: url)
                                }
                            }
                        }
                    }
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 340)
        }.padding(20).frame(width: 400)
    }

    struct Tick: Identifiable {
        let id: Int
        let category: BenchmarkCategory
        let start: Double
        let end: Double
    }
    func ticks(_ standing: BenchmarkStanding) -> [Tick] {
        var result: [Tick] = []
        var base = 0.0
        let sections = BenchmarkCategory.allCases.compactMap { category -> (BenchmarkCategory, Double, Double)? in
            let height = standing.contributions[category] ?? 0
            guard height > 0 else { return nil }
            defer { base += height }
            return (category, base, base + height)
        }
        let count = max(0, Int((standing.total / 3.3).rounded()))
        for index in 0..<count {
            let position = Double(index) * 3.3
            let end = position + 3.3
            let category = sections.max { left, right in
                let leftOverlap = max(0, min(end, left.2) - max(position, left.1))
                let rightOverlap = max(0, min(end, right.2) - max(position, right.1))
                return leftOverlap < rightOverlap
            }?.0 ?? .quality
            result.append(Tick(id: index, category: category, start: position, end: position + 2.6))
        }
        return result
    }
}

private struct BenchmarkLayout: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func benchmarkLayout(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: BenchmarkLayout.self, value: [id: proxy.frame(in: .named("benchmark"))])
        })
    }
}
