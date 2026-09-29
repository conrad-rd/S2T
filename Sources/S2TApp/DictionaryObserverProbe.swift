import AppKit
import S2TCore

/// Exercises the production watcher against real Accessibility IPC and a separate native editor.
@MainActor enum DictionaryObserverProbe {
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-dictionary-ipc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--dictionary-editor-fixture", directory.path]
        let learner = DictionaryLearner(frontmostPID: { process.processIdentifier }, presentsWindows: false)
        defer {
            learner.stop()
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: directory)
        }
        try process.run()
        let reader = DictionaryFieldReader(pid: process.processIdentifier)
        let field = try await waitForField(reader)
        let file = DictionaryFile(url: directory.appendingPathComponent("dictionary.md"))
        var watching = false
        var status = ""
        learner.start(output: "Ask conrad today.", file: file, recipient: process.processIdentifier,
            expectedField: field, insertionSelection: NSRange(location: 0, length: 0), insertionBaseline: "",
            onStatus: { status = $0; if $0.hasPrefix("Watching for") { watching = true } }, onError: { status = $0 })
        for _ in 0..<80 {
            if watching { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard watching else { throw ServiceError.message("Native watcher failed to attach: " + status) }
        try Data().write(to: directory.appendingPathComponent("correct"))
        let correction = DictionaryCorrection(original: "conrad", replacement: "Konrad", context: "Ask Konrad today.")
        for _ in 0..<120 {
            if try file.contains(correction) {
                print("PASS: separate native editor → real Accessibility IPC → production watcher → persisted Konrad correction. No providers, user dictionary or foreground activation.")
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw ServiceError.message("Real native correction was not persisted: " + status + "\nGenerated fixture dictionary:\n" + (try file.read()))
    }

    private static func waitForField(_ reader: DictionaryFieldReader) async throws -> AXUIElement {
        await Task.detached { reader.prepare() }.value
        for _ in 0..<200 {
            if let field = await Task.detached(operation: { reader.focused() }).value { return field }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw ServiceError.message("The generated native editor was not exposed through Accessibility.")
    }

    static func editor(directory: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "S2T dictionary verification"
        let editor = NSTextView(frame: NSRect(x: 10, y: 10, width: 340, height: 70))
        editor.isRichText = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.string = "Ask conrad today."
        window.contentView = editor
        window.orderBack(nil)
        window.makeKey()
        window.makeFirstResponder(editor)
        var corrected = false
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            if !corrected, FileManager.default.fileExists(atPath: directory.appendingPathComponent("correct").path) {
                corrected = true
                editor.insertText("Konrad", replacementRange: NSRange(location: 4, length: 6))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in app.terminate(nil) }
        withExtendedLifetime((window, editor, timer)) { app.run() }
    }
}
