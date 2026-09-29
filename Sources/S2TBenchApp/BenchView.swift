import SwiftUI
import Charts
import S2TBenchCore

struct BenchView: View {
    @ObservedObject var store: BenchStore
    private let accent = Color(red: 0.18, green: 0.40, blue: 0.72)
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("S2T Bench").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("Find the breaking point.").font(.callout).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.top, 22)
                List(selection: $store.page) {
                    ForEach(BenchPage.allCases) { page in Label(page.rawValue, systemImage: page.symbol).tag(page) }
                    if !store.history.isEmpty {
                        Section("Saved runs") {
                            ForEach(store.history.prefix(15)) { report in
                                Button { store.show(report) } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(report.created.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                        Text("\(report.results.filter { $0.status == .failed }.count) failed · \(report.settings["kind"] ?? "run")").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain).disabled(store.running)
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev")")
                    .font(.caption).foregroundStyle(.tertiary).padding(18)
            }.navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text(store.page.rawValue).font(.system(size: 26, weight: .semibold))
                    Spacer()
                    if store.running {
                        ProgressView().controlSize(.small)
                        Button("Stop", role: .cancel) { store.cancel() }.keyboardShortcut(".", modifiers: .command)
                    } else if store.page == .stress {
                        Button("Run selected tests") { store.runStress() }.buttonStyle(.borderedProminent)
                            .disabled(!store.animations && !store.inputs && !store.reliability)
                    } else if store.page == .prompts {
                        Button(store.provider.cloud ? "Run paid API comparison" : "Run model comparison") { store.runPrompts() }
                            .buttonStyle(.borderedProminent).disabled(store.modelIDs.isEmpty)
                    } else if store.page == .media {
                        Button("Run local model tests") { store.runMedia() }.buttonStyle(.borderedProminent).disabled(store.selectedMedia.isEmpty)
                    }
                }.padding(24)
                Divider()
                Group {
                    switch store.page {
                    case .stress: stress
                    case .prompts: prompts
                    case .media: media
                    case .results: results
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Circle().fill(store.running ? accent : store.failed > 0 ? Color.orange : Color.secondary).frame(width: 6, height: 6)
                    Text(store.status).font(.caption).lineLimit(2).textSelection(.enabled)
                    Spacer()
                }.padding(.horizontal, 18).padding(.vertical, 10)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(accent).frame(minWidth: 1040, minHeight: 720)
    }

    private var stress: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("A pass means every assertion and timing limit held. A crash, timeout or unfinished test stays visible.")
                    .font(.body).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        suite("Animation stress", symbol: "waveform.path", on: $store.animations,
                            text: "Bottom, Notch, Around Input and Within Input. Changing spectrum, full padded fields, geometry churn, 2× Canvas drawing and native blur maps.", limit: "57 prepared frames/s minimum · p99 ≤33.334 ms · worst gap ≤100 ms")
                        Divider()
                        suite("Text box detection", symbol: "rectangle.dashed", on: $store.inputs,
                            text: "Deep wrappers, competing fields, secure inputs, stale focus, resizing, attachments, fractional coordinates and unfamiliar app identities. Both input appearances use the production detector.", limit: "400 seeded hostile metadata cases per repeat, plus production fixtures")
                        Divider()
                        suite("Failure and isolation checks", symbol: "exclamationmark.shield", on: $store.reliability,
                            text: "Wrong provider keys, stale validation, model routing, clipboard persistence, shortcut cancellation and native indicator lifecycle.", limit: "Fake credentials, synthetic input and isolated storage")
                    }.padding(12)
                }
                GroupBox("Workload") {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Button("Harsh") { store.preset(false) }
                            Button("Endurance") { store.preset(true) }
                            Spacer()
                            Text("Reproducible seed").foregroundStyle(.secondary)
                            TextField("Seed", text: $store.seed).frame(width: 110).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Seconds per animation workload")
                            Slider(value: $store.seconds, in: 2...60, step: 1)
                            Text("\(Int(store.seconds)) s").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                        Stepper("Detection repeats: \(store.repetitions)", value: $store.repetitions, in: 1...20)
                        Text("Animation suite has eight workloads plus cold starts and drawing checks. Endurance uses the same strict limits for longer.").font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                }
                Text("Generated frame throughput is measured offscreen. It does not establish displayed FPS or universal compatibility with every app. No screen or microphone capture is used.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24).disabled(store.running)
        }
    }

    private func suite(_ title: String, symbol: String, on: Binding<Bool>, text: String, limit: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(accent).frame(width: 28, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(title, isOn: on).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(limit).font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
            }
        }
    }

    private var prompts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Compare A and B on identical adversarial cases. Case order is seeded; A/B order alternates. Each request uses S2T's production dictation envelope.")
                    .foregroundStyle(.secondary)
                GroupBox("Model connection") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Provider", selection: $store.provider) { ForEach(BenchProvider.allCases) { Text($0.title).tag($0) } }
                            .onChange(of: store.provider) { _, _ in store.providerChanged() }
                        if store.provider == .local { TextField("Full chat completions URL", text: $store.address).textFieldStyle(.roundedBorder) }
                        if store.provider == .managed {
                            if store.installed.isEmpty { Text("No installed text models found. Install a text model in S2T's Local settings, then refresh.").foregroundStyle(.secondary) }
                            HStack {
                                Menu("Add installed model") {
                                    ForEach(store.installed) { model in
                                        Button("\(model.name) · ~\(Int(model.memoryGB)) GB") {
                                            if !store.modelIDs.contains(model.id) { store.models = (store.modelIDs + [model.id]).joined(separator: ", ") }
                                        }
                                    }
                                }
                                Button("Refresh") { store.loadInstalled() }
                            }
                            Text("Runs installed models in a separate offline worker. Downloads are managed by S2T. The worker stops when this run ends. Its current runtime may omit token usage or enforce its own output limit; unavailable counts remain unreported.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Model IDs, separated by commas", text: $store.models).textFieldStyle(.roundedBorder)
                        if store.provider == .openRouter { TextField("Optional hosting endpoint, separate from model ID", text: $store.host).textFieldStyle(.roundedBorder) }
                        if store.provider.cloud {
                            SecureField("Provider API key for this session", text: $store.key).textFieldStyle(.roundedBorder)
                            Text("The run button sends these test cases to the selected paid provider. Keys stay in memory and are cleared when you change providers. Request and output limits bound the workload; they are not a dollar spending cap.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(10)
                }
                HStack {
                    Button("Load S2T instructions into A") { store.loadS2TInstructions() }
                    Button("Save benchmark drafts") { store.saveDrafts() }
                    Spacer()
                    Text("A \(store.promptA.utf8.count) bytes · B \(store.promptB.utf8.count) bytes").font(.caption).monospacedDigit()
                }
                HStack(alignment: .top, spacing: 14) {
                    promptEditor("A · Baseline", text: $store.promptA)
                    promptEditor("B · Candidate", text: $store.promptB)
                }
                GroupBox("Limits and repeatability") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Stepper("Repeats: \(store.repetitions)", value: $store.repetitions, in: 1...20)
                            Spacer()
                            TextField("Seed", text: $store.seed).frame(width: 110).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Stepper("Request limit: \(store.requestLimit)", value: $store.requestLimit, in: 1...2000, step: 24)
                            Spacer()
                            Stepper("Max output tokens: \(store.maxTokens)", value: $store.maxTokens, in: 32...8192, step: 256)
                        }
                        HStack { Text("Timeout per request"); Slider(value: $store.timeout, in: 5...300, step: 5); Text("\(Int(store.timeout)) s").monospacedDigit() }
                        Text("\(store.caseCount) cases × 2 prompts × \(store.modelIDs.count) models × \(store.repetitions) repeats = \(store.plannedRequests) planned calls. This run allows at most \(min(store.plannedRequests, store.requestLimit)). Unrun cases are reported as skipped.")
                            .font(.callout).foregroundStyle(store.plannedRequests > store.requestLimit ? .orange : .secondary)
                    }.padding(10)
                }
                DisclosureGroup("Add a custom exact-output test") {
                    HStack(alignment: .top) {
                        promptEditor("Dictated text", text: $store.customInput)
                        promptEditor("Expected output", text: $store.customExpected)
                    }.padding(.top, 10)
                }
                DisclosureGroup("Inspect the adversarial corpus") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(PromptCorpus.cases) { test in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(test.name).font(.headline)
                                Text(test.input).font(.caption).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
                            }
                            Divider()
                        }
                    }.padding(.top, 12)
                }
                Text("Token savings count only when the candidate preserves quality. Assertions catch specific regressions; inspect the actual outputs before choosing a prompt. Token counts and cost come from provider responses, never a characters-per-token guess.").font(.callout).foregroundStyle(.secondary)
            }.padding(24).disabled(store.running)
        }
    }
    private func promptEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextEditor(text: text).font(.system(size: 12, design: .monospaced)).frame(height: 210)
                .padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
        }.frame(maxWidth: .infinity)
    }

    private var media: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Test installed MLX speech models with generated fixtures. Text models use the A/B tests in Prompt lab.").foregroundStyle(.secondary)
                HStack { Button("Refresh installed models") { store.loadInstalled() }; Spacer(); Stepper("Repeats: \(store.repetitions)", value: $store.repetitions, in: 1...20) }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        if store.mediaModels.isEmpty { Text("No installed MLX speech models found. Install them in S2T's Local settings, then refresh.").foregroundStyle(.secondary).padding(10) }
                        ForEach(store.mediaModels) { model in
                            Toggle(isOn: Binding(get: { store.selectedMedia.contains(model.id) }, set: { if $0 { store.selectedMedia.insert(model.id) } else { store.selectedMedia.remove(model.id) } })) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name).font(.headline)
                                    Text("\(model.categoryTitle) · estimated \(model.memoryGB, specifier: "%.1f") GB memory").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(12)
                }
                GroupBox("Speech stress") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Four synthesized clips: clean, fast, 10 dB signal-to-noise and quiet speech.")
                        Text("Clean audio allows at most 5% word errors; difficult clips allow 10%. Losing either negation fails regardless of the average. Processing slower than the clip's duration also fails.").foregroundStyle(.secondary)
                        Text("First requests include model loading. Repeat results expose warm behavior. Synthetic speech does not represent all accents or real microphone conditions.").font(.caption).foregroundStyle(.secondary)
                    }.padding(12)
                }
                Text("Models run sequentially in an offline worker that stops with the run. No models are downloaded here. These tests use no microphone, camera or screen capture.").font(.callout).foregroundStyle(.secondary)
            }.padding(24).disabled(store.running)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Text("\(store.results.filter { $0.status == .passed }.count) passed").foregroundStyle(.secondary)
                Text("\(store.failed) failed").foregroundStyle(store.failed == 0 ? Color.secondary : .red)
                Toggle("Failures / skipped only", isOn: $store.failuresOnly).toggleStyle(.checkbox)
                Spacer()
                Button("Compare baseline…") { store.importBaseline() }
                Button("Export…") { store.export() }.disabled(store.results.isEmpty)
            }.font(.callout).padding(18)
            if !BenchComparison.all(store.results).isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(BenchComparison.all(store.results)) { comparison in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(comparison.model).font(.headline)
                                Text("A: \(comparison.a.filter { $0.status == .failed }.count)/\(comparison.a.count) failed · B: \(comparison.b.filter { $0.status == .failed }.count)/\(comparison.b.count) failed").font(.caption)
                                Text("\(comparison.newFailures) new failures in B · \(comparison.paired.count) matched pairs").font(.caption).foregroundStyle(comparison.newFailures > 0 ? .red : .secondary)
                                let a95 = BenchStatistics(comparison.a.compactMap { $0.metrics["latency_ms"] }).p95
                                let b95 = BenchStatistics(comparison.b.compactMap { $0.metrics["latency_ms"] }).p95
                                Text("p95: A \(a95.map { String(format: "%.0f", $0) } ?? "?") ms · B \(b95.map { String(format: "%.0f", $0) } ?? "?") ms").font(.caption).monospacedDigit()
                                Text(comparison.tokenSavingsPercent.map { String(format: "B input-token savings: %.1f%% on passing pairs", $0) } ?? "Token savings unavailable").font(.caption).foregroundStyle(.secondary)
                            }.padding(12).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 12)
                }.fixedSize(horizontal: false, vertical: true)
            }
            if let baseline = store.baselineReport, baseline.settings != store.report.settings {
                Text("Baseline uses different workload settings. Percentage comparisons are hidden.").font(.caption).foregroundStyle(.orange).padding(.bottom, 8)
            }
            if store.results.isEmpty {
                Spacer()
                Image(systemName: "chart.bar.xaxis").font(.system(size: 38)).foregroundStyle(.tertiary)
                Text(store.running ? "Running the first test…" : "Run a suite or compare two prompts.").foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                VSplitView {
                    List(selection: $store.selected) {
                        ForEach(store.displayed) { result in
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: symbol(result.status)).foregroundStyle(color(result.status)).frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(result.suite).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(headlineMetric(result)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            }.padding(.vertical, 4).tag(result.id)
                        }
                    }.frame(minHeight: 190)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let result = store.selectedResult { resultDetail(result) }
                            else { Text("Select a result to inspect its measurements.").foregroundStyle(.secondary) }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 210)
                }
                HStack {
                    Toggle("Include prompt inputs and outputs in export", isOn: $store.includeText).toggleStyle(.checkbox)
                    Spacer()
                    Text("Saved runs contain metrics only.").foregroundStyle(.secondary)
                }.font(.caption).padding(14)
            }
        }
    }
    private func resultDetail(_ result: BenchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.name).font(.headline)
            Text(result.detail).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !result.samples.isEmpty {
                Chart {
                    ForEach(Array(result.samples.enumerated()), id: \.offset) { index, value in
                        LineMark(x: .value("Interval", index), y: .value("Milliseconds", value)).foregroundStyle(accent)
                    }
                    RuleMark(y: .value("60 Hz budget", 16.667)).foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .annotation(position: .top, alignment: .trailing) { Text("16.67 ms").font(.caption2) }
                }.chartYAxisLabel("ms").frame(height: 135)
            }
            let baseline = store.baselineReport?.settings == store.report.settings ? store.baselineReport?.results.first { $0.suite == result.suite && $0.name == result.name } : nil
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 5) {
                ForEach(result.metrics.keys.sorted(), id: \.self) { key in
                    GridRow {
                        Text(key.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.secondary)
                        Text(String(format: "%.3f", result.metrics[key]!)).monospacedDigit()
                        if let old = baseline?.metrics[key], old != 0 {
                            Text(String(format: "%+.1f%% vs baseline", (result.metrics[key]! / old - 1) * 100)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }.font(.caption)
            if let input = result.input { Text("Input").font(.headline); Text(input).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
            if let output = result.output { Text("Output").font(.headline); Text(output).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
        }
    }
    private func symbol(_ status: BenchStatus) -> String { switch status { case .passed: return "checkmark.circle.fill"; case .failed: return "xmark.circle.fill"; case .skipped: return "minus.circle"; case .cancelled: return "stop.circle" } }
    private func color(_ status: BenchStatus) -> Color { switch status { case .passed: return .green; case .failed: return .red; case .skipped: return .orange; case .cancelled: return .secondary } }
    private func headlineMetric(_ result: BenchResult) -> String {
        if let fps = result.metrics["prepared_fps"] { return String(format: "%.1f frames/s", fps) }
        if let ms = result.metrics["latency_ms"] { return String(format: "%.0f ms", ms) }
        return result.status.rawValue
    }
}
