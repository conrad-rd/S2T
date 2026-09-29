import AppKit
import CoreText
import SwiftUI
import S2TCore

struct DashboardDay { let date: Date; let value: Decimal; let count: Int }

/// Everything the dashboard shows is derived once per data, source or range change,
/// so hovering the chart never touches the ledger records.
@MainActor final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: LocalUsageSnapshot?
    @Published var source: LocalUsageSource = .s2t { didSet { recompute() } }
    @Published var days = 30 { didSet { recompute() } }
    @Published var availableSources = LocalUsageSource.allCases {
        didSet {
            if !availableSources.contains(source), let first = availableSources.first { source = first }
        }
    }
    private(set) var records: [LocalUsageRecord] = []
    private(set) var complete: [LocalUsageRecord] = []
    private(set) var periodRecords: [LocalUsageRecord] = []
    private(set) var series: [DashboardDay] = []
    private(set) var total: Decimal = 0
    private(set) var pending: Decimal = 0
    private(set) var maximum: Decimal = 0
    private(set) var unknown = 0
    private(set) var estimated = false
    private(set) var today = Date()
    private(set) var start = Date()
    private var choseSource = false
    static let segments = 28
    static let utc: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()
    static let dateFormat: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "MMM d"
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }()
    static let tokenFormat: NumberFormatter = {
        let value = NumberFormatter()
        value.numberStyle = .decimal
        value.locale = Locale(identifier: "en_US_POSIX")
        value.usesGroupingSeparator = true
        value.groupingSeparator = ","
        value.groupingSize = 3
        value.maximumFractionDigits = 0
        return value
    }()

    init() { recompute() }

    func update(_ value: LocalUsageSnapshot) {
        snapshot = value
        if !choseSource, let first = value.records.first(where: { availableSources.contains($0.source) }) { choseSource = true; source = first.source } else { recompute() }
    }
    func select(_ value: LocalUsageSource) {
        guard availableSources.contains(value) else { return }
        choseSource = true; source = value
    }

    /// Local models are free, so they are measured in tokens instead of money.
    var countsTokens: Bool { source == .local }
    func value(_ record: LocalUsageRecord) -> Decimal? { countsTokens ? record.tokens.map { Decimal($0) } : record.amount }

    private func recompute() {
        records = (snapshot?.records ?? []).filter { $0.source == source }
        complete = records.filter { !$0.pending }
        total = complete.compactMap(value).reduce(0, +)
        pending = records.filter(\.pending).compactMap(value).reduce(0, +)
        today = Self.utc.startOfDay(for: Date())
        start = Self.utc.date(byAdding: .day, value: 1 - days, to: today)!
        let end = Self.utc.date(byAdding: .day, value: 1, to: today)!
        periodRecords = complete.filter { $0.date >= start && $0.date < end }
        unknown = periodRecords.filter { value($0) == nil }.count
        estimated = complete.contains(where: \.estimated)
        var totals = [Int: (value: Decimal, count: Int)]()
        for record in periodRecords {
            let index = Self.utc.dateComponents([.day], from: start, to: record.date).day ?? 0
            guard (0..<days).contains(index) else { continue }
            totals[index, default: (0, 0)].value += value(record) ?? 0
            totals[index, default: (0, 0)].count += 1
        }
        series = (0..<days).map { index in
            DashboardDay(date: Self.utc.date(byAdding: .day, value: index, to: start)!,
                         value: totals[index]?.value ?? 0, count: totals[index]?.count ?? 0)
        }
        maximum = series.map(\.value).max() ?? 0
        objectWillChange.send()
    }

    func strokes(_ value: Decimal) -> Int {
        guard maximum > 0 else { return 0 }
        return max(0, min(Self.segments, Int((NSDecimalNumber(decimal: value / maximum).doubleValue * Double(Self.segments)).rounded())))
    }
    func amount(_ value: Decimal) -> String {
        if countsTokens { return Self.tokenFormat.string(from: value as NSDecimalNumber) ?? "0" }
        let digits = String(format: "%.4f", NSDecimalNumber(decimal: value).doubleValue)
        return (source == .s2t ? "" : "$") + digits
    }
    func tokens(_ value: Int) -> String { Self.tokenFormat.string(from: NSNumber(value: value)) ?? "\(value)" }
    var unit: String { countsTokens ? "tokens" : source == .s2t ? "credits" : "USD" }
    var caption: String { countsTokens ? "Tokens processed" : source == .s2t ? "Credits used" : "Spent" }
    func date(_ value: Date) -> String { Self.dateFormat.string(from: value) }
}

enum DashboardTypography {
    static let postScriptName = "BitcountPropSingle-Regular"
    static let registered: Void = {
        guard let url = Bundle.main.url(forResource: "bitcount-regular", withExtension: "ttf", subdirectory: "Dashboard/fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func amount(size: CGFloat) -> Font {
        _ = registered
        return .custom(postScriptName, size: size)
    }
}

private struct DashboardAmount: View {
    let text: String
    let size: CGFloat
    var body: some View {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(String(parts.first ?? ""))
            if parts.count > 1 { Text("." + parts[1]).opacity(0.5) }
        }
        .font(DashboardTypography.amount(size: size))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    static let ink = Color(red: 239.0 / 255, green: 239.0 / 255, blue: 235.0 / 255)
    static let muted = Color(red: 146.0 / 255, green: 146.0 / 255, blue: 142.0 / 255)
    private var ink: Color { Self.ink }
    private var muted: Color { Self.muted }
    private static let sources: [(LocalUsageSource, String)] = [
        (.s2t, "S2T credits"), (.openRouter, "OpenRouter"), (.xai, "xAI"), (.assemblyAI, "AssemblyAI"), (.typeSafe, "TypeSafe"), (.local, "Local")
    ]

    init(model: DashboardModel) {
        self.model = model
        _ = DashboardTypography.registered
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 24) {
                    ForEach(Self.sources.filter { model.availableSources.contains($0.0) }, id: \.0) { source, title in sourceButton(source, title) }
                }
                .padding(.top, 20).padding(.bottom, 36)
                Text(model.caption).font(.system(size: 11)).foregroundStyle(muted).padding(.bottom, 10)
                DashboardAmount(text: model.amount(model.total), size: 64)
                    .accessibilityLabel("Total used, " + model.amount(model.total) + " " + model.unit)
                if model.pending > 0 {
                    HStack(spacing: 4) {
                        DashboardAmount(text: model.amount(model.pending), size: 13)
                        Text("pending").font(.system(size: 11))
                    }.foregroundStyle(muted).padding(.top, 9)
                }
                if let error = model.snapshot?.error, !error.isEmpty {
                    Text(error).foregroundStyle(.orange).font(.system(size: 11)).padding(.top, 12)
                }
                HStack {
                    Text("Daily · UTC").font(.system(size: 11)).foregroundStyle(muted)
                    Spacer()
                    HStack(spacing: 18) {
                        ForEach([7, 30, 90], id: \.self) { days in
                            Button("\(days) days") { model.days = days }
                                .foregroundStyle(ink.opacity(model.days == days ? 1 : 0.5))
                                .accessibilityAddTraits(model.days == days ? .isSelected : [])
                        }
                    }.buttonStyle(.plain).font(.system(size: 12))
                }.padding(.top, 40).padding(.bottom, 18)
                DashboardChart(days: model.series, strokes: model.series.map { model.strokes($0.value) },
                               peak: model.maximum > 0 ? model.amount(model.maximum) : "",
                               labels: model.series.map { day in
                                   model.date(day.date) + " · " + model.amount(day.value) + (model.countsTokens ? " tokens" : "")
                                       + " · \(day.count) request" + (day.count == 1 ? "" : "s")
                               })
                .id(model.source.rawValue + "\(model.days)")
                HStack {
                    Text(model.date(model.start))
                    Spacer()
                    Text(model.date(model.today))
                }.font(.system(size: 10)).foregroundStyle(muted).padding(.top, 13)
                if model.unknown > 0 {
                    Text("\(model.unknown) requests " + (model.countsTokens ? "reported no token count" : "have no reported cost") + " and are excluded.")
                        .font(.system(size: 11)).foregroundStyle(muted).padding(.top, 16)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent activity").fontWeight(.semibold)
                    VStack(spacing: 12) {
                        ForEach(model.complete.prefix(25), id: \.id) { record in activity(record) }
                        if model.complete.isEmpty { Text("No recorded usage yet.").foregroundStyle(muted) }
                    }.padding(.top, 16)
                }
                .font(.system(size: 12)).padding(.top, 35)
                if let note {
                    Text(note).font(.system(size: 10)).foregroundStyle(muted).padding(.top, 18)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 36).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: DashboardPane.backgroundColor))
    }

    private var note: String? {
        switch model.source {
        case .typeSafe: return "TypeSafe requests are recorded even when no billed amount is reported."
        case .assemblyAI: return "AssemblyAI amounts are estimates. Your invoice may differ."
        case .xai: return model.estimated ? "Speech-to-text requests without a reported cost are estimated at $0.10 per audio hour." : nil
        case .local: return "Local models run on this Mac at no cost, so they are measured in the tokens your local server reports."
        default: return nil
        }
    }

    private func activity(_ record: LocalUsageRecord) -> some View {
        HStack(spacing: 6) {
            Text(model.date(record.date)).foregroundStyle(muted)
            Spacer()
            if model.countsTokens {
                if let tokens = record.tokens {
                    DashboardAmount(text: model.tokens(tokens), size: 17)
                    Text("tokens").foregroundStyle(muted)
                } else { Text("Tokens unavailable").foregroundStyle(muted) }
            } else {
                if let tokens = record.tokens { Text(model.tokens(tokens) + " tokens").foregroundStyle(muted).padding(.trailing, 8) }
                if let amount = record.amount {
                    DashboardAmount(text: model.amount(amount), size: 17)
                    if record.estimated { Text("est.").foregroundStyle(muted) }
                } else { Text("Cost unavailable").foregroundStyle(muted) }
            }
        }.font(.system(size: 11))
    }

    private func sourceButton(_ source: LocalUsageSource, _ title: String) -> some View {
        Button(title) { model.select(source) }
            .buttonStyle(.plain).font(.system(size: 13))
            .foregroundStyle(ink.opacity(model.source == source ? 1 : 0.5))
            .accessibilityAddTraits(model.source == source ? .isSelected : [])
    }
}

/// One Canvas for all bars. Hover only changes this view's state, so it redraws a single
/// layer instead of re-diffing hundreds of segment views.
private struct DashboardChart: View {
    let days: [DashboardDay]
    let strokes: [Int]
    let peak: String
    let labels: [String]
    @State private var hovered: Int?
    private static let height: CGFloat = 166

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(peak).font(.system(size: 10)).foregroundStyle(DashboardView.muted).monospacedDigit()
                .frame(height: 12)
            GeometryReader { proxy in
                let layout = Layout(width: proxy.size.width, count: days.count)
                Canvas { context, _ in
                    var idle = Path(), active = Path(), empty = Path()
                    for index in days.indices {
                        let x = layout.x(index)
                        let filled = strokes[index]
                        for segment in 0..<DashboardModel.segments {
                            let rect = CGRect(x: x, y: Self.height - CGFloat(segment + 1) * 6 + 2, width: layout.bar, height: 4)
                            let shape = Path(roundedRect: rect, cornerRadius: min(2, layout.bar / 2), style: .continuous)
                            if segment >= filled { if index == hovered { empty.addPath(shape) } }
                            else if index == hovered { active.addPath(shape) } else { idle.addPath(shape) }
                        }
                    }
                    context.fill(empty, with: .color(DashboardView.ink.opacity(0.07)))
                    context.fill(idle, with: .color(DashboardView.ink.opacity(hovered == nil ? 0.62 : 0.4)))
                    context.fill(active, with: .color(DashboardView.ink))
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    var next: Int?
                    if case .active(let point) = phase { next = layout.index(point.x) }
                    if next != hovered { hovered = next }
                }
                .overlay(alignment: .topLeading) {
                    if let hovered, labels.indices.contains(hovered) {
                        tooltip(labels[hovered], center: layout.x(hovered) + layout.bar / 2, width: proxy.size.width)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityChildren {
                    HStack(spacing: 0) {
                        ForEach(labels.indices, id: \.self) { index in
                            Color.clear.accessibilityLabel(labels[index])
                        }
                    }
                }
            }
            .frame(height: Self.height)
            Rectangle().fill(DashboardView.muted.opacity(0.28)).frame(height: 1)
            if strokes.allSatisfy({ $0 == 0 }) {
                Text("No usage in this period.").font(.system(size: 11)).foregroundStyle(DashboardView.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 9)
            }
        }
    }

    private func tooltip(_ text: String, center: CGFloat, width: CGFloat) -> some View {
        let estimate = CGFloat(text.count) * 6.2 + 20
        let x = min(max(0, center - estimate / 2), max(0, width - estimate))
        return Text(text)
            .font(.system(size: 11)).monospacedDigit().foregroundStyle(DashboardView.ink)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.16)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(DashboardView.ink.opacity(0.08)))
            .offset(x: x, y: -30)
            .allowsHitTesting(false)
    }

    /// Bars fill the full width; very short ranges cap the bar width so they stay slender.
    private struct Layout {
        let slot: CGFloat, bar: CGFloat, inset: CGFloat, count: Int
        init(width: CGFloat, count: Int) {
            self.count = count
            slot = width / CGFloat(max(1, count))
            let gap: CGFloat = count <= 7 ? 14 : count <= 30 ? 4 : 2
            bar = max(2, min(slot - gap, count <= 7 ? 44 : 28))
            inset = (slot - bar) / 2
        }
        func x(_ index: Int) -> CGFloat { CGFloat(index) * slot + inset }
        func index(_ x: CGFloat) -> Int? {
            guard slot > 0, x >= 0, count > 0 else { return nil }
            return min(count - 1, Int(x / slot))
        }
    }
}
