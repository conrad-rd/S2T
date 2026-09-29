import SwiftUI
import S2TCore

struct LocalModelComparison: View {
    let models: [LocalModel]
    let selectedID: String?
    let select: (String) -> Void

    private var chartModels: [LocalModel] { models.filter { !$0.isNative } }
    private var metric: LocalBenchmarkMetric { .forCategory(models.first?.category ?? "speech") }
    var nativeSelection: LocalModel? { models.first { $0.isNative && $0.id == selectedID } ?? models.first { $0.isNative } }
    private var selectedScore: LocalModelBenchmark? { selectedID.flatMap { LocalModelBenchmark.scores[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Published performance").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let score = selectedScore, let url = URL(string: score.sourceURL) {
                    Link(score.sourceName, destination: url).font(.system(size: 11))
                        .help(score.configuration + " · Checked " + LocalModelBenchmark.checkedAt)
                }
            }
            Text(metric.title).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 5) {
                ForEach(chartModels) { model in
                    benchmarkRow(model)
                }
            }
            HStack {
                Color.clear.frame(width: 170, height: 1)
                Text("0")
                Spacer()
                Text(metric.chartMaximum.formatted())
                Color.clear.frame(width: 62, height: 1)
            }.font(.system(size: 9).monospacedDigit()).foregroundStyle(.tertiary)
            if let native = nativeSelection {
                Button { select(native.id) } label: {
                    HStack {
                        Text("Apple Speech")
                        Spacer()
                        Text("No published comparison").foregroundStyle(.secondary)
                    }.font(.system(size: 11)).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text(selectedScore?.configuration ?? "No comparable published result for this model.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("Parent-model scores · Local quantization and speed can differ · Sep 21, 2026")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14).padding(.bottom, 4)
        .accessibilityIdentifier("models.local.benchmarks")
    }

    private func benchmarkRow(_ model: LocalModel) -> some View {
        let score = LocalModelBenchmark.scores[model.id]
        let selected = model.id == selectedID
        return Button { select(model.id) } label: {
            HStack(spacing: 10) {
                Text(model.name).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1).frame(width: 170, alignment: .leading)
                GeometryReader { geometry in
                    if let score {
                        Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.22))
                            .frame(width: geometry.size.width * score.fraction, height: 5)
                            .frame(maxHeight: .infinity)
                    }
                }.frame(height: 20)
                Text(score?.formattedValue ?? "Unrated")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(score.map { $0.configuration + ". " + $0.metric.title } ?? "No comparable published result. No score is assigned.")
        .accessibilityLabel(model.name + ". " + (score.map { $0.formattedValue + ". " + $0.metric.title + ". " + $0.configuration } ?? "No published comparison"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
