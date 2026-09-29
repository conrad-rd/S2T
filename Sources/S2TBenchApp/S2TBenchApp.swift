import AppKit
import SwiftUI
import S2TBenchCore

@main struct S2TBenchMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        if let i = CommandLine.arguments.firstIndex(of: "--verify-network"), CommandLine.arguments.count > i + 1 {
            app.setActivationPolicy(.prohibited)
            Task {
                do { try await BenchNetworkProbe.run(address: CommandLine.arguments[i + 1]); exit(0) }
                catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run(); return
        }
        if CommandLine.arguments.contains("--verify-bench") {
            app.setActivationPolicy(.prohibited)
            do {
                let store = BenchStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("s2t-bench-fixture-" + UUID().uuidString), loadSaved: false)
                defer { try? FileManager.default.removeItem(at: store.directory) }
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
                window.isReleasedWhenClosed = false
                let host = NSHostingView(rootView: BenchView(store: store))
                window.contentView = host
                for page in BenchPage.allCases {
                    store.page = page
                    if page == .results { store.append(.init(suite: "fixture", name: "A measured failure", status: .failed, detail: "Independent fixture", metrics: ["p99_ms": 58])) }
                    host.layoutSubtreeIfNeeded()
                    guard !window.isVisible, host.bounds.width >= 1040, host.bounds.height >= 720 else { throw BenchError.message("Benchmark window layout or hidden-state check failed.") }
                }
                let expectedBuiltInCases = 37
                guard PromptCorpus.cases.count == expectedBuiltInCases else {
                    throw BenchError.message("Benchmark fixture corpus changed; update its independent request-budget expectation.")
                }
                store.models = "test-one,\n test-two, test-one"
                store.repetitions = 4
                store.customInput = "Keep this fixed fixture sentence."
                store.customExpected = "Keep this fixed fixture sentence."
                // 2 unique models × 4 repetitions × (37 built-ins + 1 custom case) × 2 prompt variants.
                let expectedRequests = 608
                guard store.modelIDs == ["test-one", "test-two"], store.plannedRequests == expectedRequests else {
                    throw BenchError.message("Model selection or request budget failed: expected 608, got \(store.plannedRequests).")
                }
                store.key = "fixture-secret"; store.providerChanged()
                guard store.key.isEmpty else { throw BenchError.message("Provider switch retained a key.") }
                store.saveDrafts(); store.saveReport()
                let restored = BenchStore(directory: store.directory, loadSaved: true)
                guard restored.promptA == store.promptA, restored.history.count == 1, restored.history[0].results[0].status == .failed else { throw BenchError.message("Draft/report persistence failed.") }
                print("PASS: hidden benchmark window, page layouts, provider isolation, model deduplication, request counts, drafts and persisted failures. No screen capture.")
                window.close()
            } catch { fputs("Benchmark UI: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--run-suite"), CommandLine.arguments.count > i + 1 {
            app.setActivationPolicy(.prohibited)
            let suite = CommandLine.arguments[i + 1]
            let engine = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/S2T.app/Contents/MacOS/S2T")
            Task {
                do {
                    let output = try await BenchProcess.run(executable: engine, arguments: ["--bench-suite", suite] + Array(CommandLine.arguments.dropFirst(i + 2)), timeout: 1200) { line in print(line); fflush(stdout) }
                    let failed = output.output.split(separator: "\n").contains { line in
                        guard line.hasPrefix("S2TBENCH "), let result = try? JSONDecoder().decode(BenchResult.self, from: Data(line.dropFirst(9).utf8)) else { return false }
                        return result.status == .failed
                    }
                    exit(output.code == 0 && !output.timedOut && !failed ? 0 : 1)
                } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            }
            app.run(); return
        }
        if let argument = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("--") }) {
            fputs("Unknown or incomplete benchmark command: \(argument)\n", stderr)
            exit(2)
        }
        app.setActivationPolicy(.regular)
        let delegate = BenchAppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) { }
    }
}

@MainActor private final class BenchAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let store = BenchStore()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit S2T Bench", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""), editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "S2T Bench"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: BenchView(store: store))
        window.minSize = NSSize(width: 1040, height: 740)
        window.setFrameAutosaveName("S2TBenchmarkWindow")
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.running else { return .terminateNow }
        store.cancel()
        Task {
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while store.running && ProcessInfo.processInfo.systemUptime < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
            store.saveReport()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
