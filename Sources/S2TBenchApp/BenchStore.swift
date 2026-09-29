import AppKit
import SwiftUI
import S2TCore
import S2TBenchCore

enum BenchPage: String, CaseIterable, Identifiable {
    case stress = "Stress tests", prompts = "Prompt lab", media = "Speech", results = "Results"
    var id: String { rawValue }
    var symbol: String { self == .stress ? "speedometer" : self == .prompts ? "text.alignleft" : self == .media ? "waveform.and.magnifyingglass" : "chart.xyaxis.line" }
}

@MainActor final class BenchStore: ObservableObject {
    @Published var page = BenchPage.stress
    @Published var running = false
    @Published var status = "Ready to find failures."
    @Published var results: [BenchResult] = []
    @Published var selected: UUID?
    @Published var history: [BenchReport] = []
    @Published var baselineReport: BenchReport?
    @Published var seconds = 10.0
    @Published var repetitions = 3
    @Published var seed = "42"
    @Published var animations = true
    @Published var inputs = true
    @Published var reliability = true
    @Published var provider = BenchProvider.local
    @Published var address = "http://127.0.0.1:11434/v1/chat/completions"
    @Published var models = ""
    @Published var host = ""
    @Published var key = ""
    @Published var promptA = WritingMode.defaultEditingInstruction
    @Published var promptB = PromptCorpus.compactPrompt
    @Published var maxTokens = 2048
    @Published var requestLimit = 144
    @Published var timeout = 90.0
    @Published var includeText = false
    @Published var failuresOnly = false
    @Published var installed: [LocalModel] = []
    @Published var mediaModels: [LocalModel] = []
    @Published var selectedMedia = Set<String>()
    @Published var customInput = ""
    @Published var customExpected = ""
    private var runTask: Task<Void, Never>?
    private var workerTask: Task<Void, Never>?
    private var workerEndpoint: String?
    private var workerError: String?
    private var activeReport: BenchReport?

    let directory: URL
    let engine: URL
    init(directory: URL? = nil, engine: URL? = nil, loadSaved: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T Bench")
        self.engine = engine ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/S2T.app/Contents/MacOS/S2T")
        if loadSaved {
            if let a = try? String(contentsOf: self.directory.appendingPathComponent("prompt-a.txt"), encoding: .utf8), a.utf8.count <= 65536 { promptA = a }
            if let b = try? String(contentsOf: self.directory.appendingPathComponent("prompt-b.txt"), encoding: .utf8), b.utf8.count <= 65536 { promptB = b }
            reloadHistory()
            loadInstalled()
        }
    }
    var modelIDs: [String] { Array(NSOrderedSet(array: models.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })) as? [String] ?? [] }
    var caseCount: Int { PromptCorpus.cases.count + (customInput.isEmpty ? 0 : 1) }
    var plannedRequests: Int { modelIDs.count * repetitions * caseCount * 2 }
    var failed: Int { results.filter { $0.status == .failed }.count }
    var displayed: [BenchResult] { failuresOnly ? results.filter { $0.status != .passed } : results }
    var selectedResult: BenchResult? { results.first { $0.id == selected } }
    var report: BenchReport { var report = activeReport ?? BenchReport(results: [], settings: [:]); report.results = results; return report }

    func preset(_ harsh: Bool) {
        seconds = harsh ? 30 : 10; repetitions = harsh ? 10 : 3
        requestLimit = harsh ? 480 : 144
    }
    func cancel() { runTask?.cancel(); workerTask?.cancel(); status = "Stopping the active test…" }
    func providerChanged() { key = ""; models = ""; host = ""; loadInstalled() }
    func loadInstalled() {
        let resources = engine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LocalModels/catalog.json")
        let root = localRoot
        let all = ((try? LocalModel.read(from: resources)) ?? []).filter { model in
            guard let data = try? Data(contentsOf: root.appendingPathComponent("models/\(model.id)/installed.json")),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
            return record["revision"] == model.revision
        }
        installed = all.filter { $0.category == "text" }
        mediaModels = all.filter { $0.category != "text" }
    }
    private var localRoot: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T/LocalModels") }

    func runStress() {
        let suites = [("animations", animations), ("inputs", inputs), ("reliability", reliability)].filter(\.1).map(\.0)
        guard !suites.isEmpty, let seedValue = UInt64(seed) else { status = "Select a suite and enter a numeric seed."; return }
        let duration = seconds, repeats = repetitions
        begin(settings: ["kind": "synthetic stress", "seed": seed, "seconds_per_workload": String(duration), "repetitions": String(repeats), "suites": suites.joined(separator: ",")]) { [self] in
            guard FileManager.default.isExecutableFile(atPath: engine.path) else { throw BenchError.message("The packaged S2T benchmark engine is missing. Rebuild S2T Bench.") }
            for suite in suites {
                try Task.checkCancellation()
                status = "Running \(suite)…"
                let output = try await BenchProcess.run(executable: engine,
                    arguments: ["--bench-suite", suite, "--seconds", String(duration), "--repeats", String(repeats), "--seed", String(seedValue)],
                    timeout: suite == "animations" ? duration * 8 + 480 : 600) { [weak self] line in
                        guard line.hasPrefix("S2TBENCH "), let data = String(line.dropFirst(9)).data(using: .utf8), let result = try? JSONDecoder().decode(BenchResult.self, from: data) else { return }
                        await self?.append(result)
                    }
                if output.code != 0 || output.timedOut {
                    append(BenchResult(suite: suite, name: "Engine process", status: .failed,
                        detail: output.timedOut ? "Hard deadline exceeded. The child process was stopped." : "Engine exited with code \(output.code). \(String(output.output.suffix(4000)))"))
                }
            }
        }
    }

    func runPrompts() {
        guard let seedValue = UInt64(seed) else { status = "Enter a numeric seed."; return }
        if !customInput.isEmpty && customExpected.isEmpty { status = "Add the expected result for the custom case."; return }
        guard customInput.utf8.count <= 65536, customExpected.utf8.count <= 65536 else { status = "Keep custom test input and expected output under 64 KB each."; return }
        var config = PromptRunConfiguration(provider: provider, address: address, host: host, models: modelIDs, key: key,
            baseline: promptA, candidate: promptB, repetitions: repetitions, requestLimit: requestLimit, maxTokens: maxTokens, timeout: timeout, seed: seedValue)
        var tests = PromptCorpus.cases
        if !customInput.isEmpty { tests.append(.init(id: "custom", name: "Custom exact-output case", input: customInput, exact: customExpected)) }
        let selectedModels = installed.filter { config.models.contains($0.id) }
        if provider == .managed {
            guard selectedModels.count == config.models.count, !selectedModels.isEmpty else { status = "Select at least one installed text model."; return }
            guard selectedModels.allSatisfy({ $0.memoryGB * 1_000_000_000 <= Double(ProcessInfo.processInfo.physicalMemory) }) else { status = "A selected model exceeds this Mac's memory budget."; return }
            config.address = "http://127.0.0.1/v1/chat/completions"
        }
        let corpus: PromptCorpus.Identity
        do {
            try config.validate()
            corpus = try PromptCorpus.identity(tests)
        } catch { status = error.localizedDescription; return }
        let settings = ["kind": "prompt comparison", "provider": provider.title, "models": models, "host": host,
            "prompt_a_sha256": BenchEndpoint.fingerprint(promptA), "prompt_b_sha256": BenchEndpoint.fingerprint(promptB),
            "prompt_a_bytes": String(promptA.utf8.count), "prompt_b_bytes": String(promptB.utf8.count),
            "corpus_sha256": corpus.sha256, "corpus_bytes": String(corpus.bytes), "corpus_schema": "1",
            "seed": seed, "repetitions": String(repetitions), "request_limit": String(requestLimit), "max_output_tokens": String(maxTokens),
            "timeout_seconds": String(timeout), "case_count": String(tests.count), "order": "seeded cases, alternating A/B pairs", "temperature": "0"]
        begin(settings: settings) { [self] in
            if config.provider == .managed { config.address = try await startWorker() + "/chat/completions" }
            status = "Comparing prompts across \(config.models.count) model(s)…"
            try await PromptBenchmark.run(config, cases: tests) { [weak self] result in await self?.append(result) }
        }
    }

    func begin(settings: [String: String], operation: @escaping @MainActor () async throws -> Void) {
        guard !running else { return }
        results = []; selected = nil; running = true; page = .results
        activeReport = BenchReport(results: [], settings: settings)
        runTask = Task {
            defer { workerTask?.cancel(); workerTask = nil; workerEndpoint = nil; running = false; runTask = nil; saveReport() }
            do {
                try await operation()
                try Task.checkCancellation()
                status = "Finished. \(failed) failed, \(results.filter { $0.status == .skipped }.count) skipped."
            } catch {
                let cancelled = Task.isCancelled
                append(BenchResult(suite: "run", name: cancelled ? "Cancelled" : "Run failed", status: cancelled ? .cancelled : .failed,
                    detail: cancelled ? "Stopped by the user. Completed results are retained; unfinished tests were not passed." : error.localizedDescription))
                status = cancelled ? "Cancelled. Partial results saved." : error.localizedDescription
            }
        }
    }
    func append(_ result: BenchResult) {
        results.append(result)
        if selected == nil || result.status == .failed { selected = result.id }
        status = "\(results.count) results · \(failed) failed · \(result.name)"
    }
    func startWorker() async throws -> String {
        let root = localRoot
        let python = root.appendingPathComponent("runtime/bin/python3")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { throw BenchError.message("Install a local text model in S2T first.") }
        let resources = engine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/LocalModels")
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_OFFLINE"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"; env["PYTHONUNBUFFERED"] = "1"
        workerEndpoint = nil; workerError = nil
        status = "Starting an isolated local worker…"
        workerTask = Task {
            do {
                _ = try await BenchProcess.run(executable: python, arguments: [resources.appendingPathComponent("worker.py").path, "serve", "--root", root.path], timeout: 7200, environment: env) { [weak self] line in
                    guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: String], let endpoint = object["endpoint"], (try? BenchEndpoint.local(endpoint)) != nil else { return }
                    await self?.receiveWorkerEndpoint(endpoint)
                }
                if !Task.isCancelled { workerError = "Local worker exited. Check the installed runtime in S2T." }
            } catch { if !Task.isCancelled { workerError = error.localizedDescription } }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 45
        while workerEndpoint == nil {
            try Task.checkCancellation()
            if let workerError { throw BenchError.message(workerError) }
            if ProcessInfo.processInfo.systemUptime > deadline { throw BenchError.message("Local worker did not start within 45 seconds.") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return workerEndpoint!
    }

    private func receiveWorkerEndpoint(_ endpoint: String) { workerEndpoint = endpoint }

    func saveDrafts() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(promptA.utf8).write(to: directory.appendingPathComponent("prompt-a.txt"), options: .atomic)
            try Data(promptB.utf8).write(to: directory.appendingPathComponent("prompt-b.txt"), options: .atomic)
            status = "Benchmark prompt drafts saved."
        } catch { status = error.localizedDescription }
    }
    func loadS2TInstructions() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("S2T")
        let file = [InstructionsFile.filename, InstructionsFile.legacyFilename].map(folder.appendingPathComponent)
            .first { FileManager.default.fileExists(atPath: $0.path) } ?? folder.appendingPathComponent(InstructionsFile.filename)
        do {
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 65536 else { throw BenchError.message("Instructions exceed 64 KB.") }
            promptA = try String(contentsOf: file, encoding: .utf8); status = "Loaded S2T's current instructions into A."
        } catch { status = error.localizedDescription }
    }
    func saveReport() {
        guard !results.isEmpty else { return }
        do {
            let runs = directory.appendingPathComponent("Runs")
            try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)
            try report.encoded(includeText: false).write(to: runs.appendingPathComponent(report.id.uuidString + ".json"), options: .atomic)
            reloadHistory()
        } catch { status += " Could not save report: \(error.localizedDescription)" }
    }
    func reloadHistory() {
        history = BenchReportHistory.load(from: directory.appendingPathComponent("Runs"))
    }
    func show(_ report: BenchReport) { guard !running else { return }; activeReport = report; results = report.results; selected = results.first?.id; page = .results; status = "Saved run from \(report.created.formatted())." }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "S2T-benchmark.json"; panel.allowedContentTypes = [.json]
        panel.begin { [weak self] answer in
            guard answer == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do { try self.report.encoded(includeText: self.includeText).write(to: url, options: .atomic); self.status = "Exported benchmark report." }
                catch { self.status = error.localizedDescription }
            }
        }
    }
    func importBaseline() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.begin { [weak self] answer in
            guard answer == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { self?.baselineReport = try BenchReport.decode(Data(contentsOf: url)); self?.status = "Baseline loaded for matching result comparisons." }
                catch { self?.status = error.localizedDescription }
            }
        }
    }
}
