import AppKit
import S2TCore

@MainActor enum InsertionProbe {
    static func run(fixtureURL: URL) async throws {
        guard AXIsProcessTrusted() else { throw failure("S2T Accessibility permission is missing.") }
        defer { TextInsertion.menuIsOpen = false }
        let previousApp = NSWorkspace.shared.frontmostApplication
        let history = AppFocusHistory()
        let board = NSPasteboard(name: NSPasteboard.Name("com.s2t.insertion-fixture.\(UUID().uuidString)"))
        board.setString("unrelated copied text", forType: .string)
        let originalClipboardChange = NSPasteboard.general.changeCount
        let process = Process()
        process.executableURL = fixtureURL.appendingPathComponent("Contents/MacOS/PasteEditor")
        process.environment = ProcessInfo.processInfo.environment.merging(["S2T_TEST_PASTEBOARD": board.name.rawValue]) { _, new in new }
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            if let previousApp, previousApp.bundleIdentifier != "com.raycast.macos" { previousApp.activate(options: []) }
        }

        try await Task.sleep(nanoseconds: 500_000_000)
        if let fixtureApp = NSRunningApplication(processIdentifier: process.processIdentifier) {
            NSApp.yieldActivation(to: fixtureApp)
            fixtureApp.activate(options: [])
            for _ in 0..<40 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        let root = AXUIElementCreateApplication(process.processIdentifier)
        guard let editor = find("probe.editor", in: root), let search = find("probe.search", in: root), let readOnly = find("probe.readOnlyEditor", in: root) else { throw failure("Fixture fields not found.") }
        TextInsertion.diagnosticOutput = { print("method: \($0)") }
        defer { TextInsertion.diagnosticOutput = nil }
        print("fixture pid=\(process.processIdentifier)")
        var failures = 0
        let cases: [(String, AXUIElement, Bool)] = CommandLine.arguments.contains("--start-only") ? [] : [("native editor without AX writes", readOnly, false), ("native editor", editor, false), ("missing initial target", editor, true), ("search selection", search, false)]
        for (name, element, missingCapture) in cases {
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, "before selected after" as CFString)
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try await Task.sleep(nanoseconds: 100_000_000)
            var range = CFRange(location: 7, length: 8)
            if let value = AXValueCreate(.cfRange, &range) { AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) }

            guard let focused = TextInsertion.captureTarget(), focused.app.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus. No paste sent.") }
            guard stringValue(element) == "before selected after" else { throw failure("Fixture failed to reset \(name). No paste sent.") }
            let target = missingCapture ? nil : focused
            let result = try await TextInsertion.insert("S2T test", into: target, pasteboard: board)
            try await Task.sleep(nanoseconds: 150_000_000)
            let matches = stringValue(element) == "before S2T test after"
            print("\(name): \(matches ? "PASS" : "FAIL"), outcome=\(result.rawValue), fixture text=\(stringValue(element) ?? "nil")")
            if !matches { failures += 1 }
        }
        AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
        AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var originalRange = CFRange(location: 7, length: 8)
        if let range = AXValueCreate(.cfRange, &originalRange) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }
        let origin = await TextInsertion.rememberStart(TextInsertion.captureTarget())
        AXUIElementSetAttributeValue(search, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let searchBefore = stringValue(search)
        let restored = try await TextInsertion.insert("Original destination", into: origin, pasteboard: board)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard restored == .textSent, stringValue(editor) == "before Original destination after", stringValue(search) == searchBefore else { throw failure("Starting field and selection were not restored") }
        print("Restore starting field and selection after focus change: PASS")
        guard failures == 0 else { throw failure("\(failures) insertion cases failed.") }

        for destination in [editor, search] {
            for remembersStart in [false, true] {
                for movesAway in [false, true] {
                    let existing = "Grüße 👩🏽‍💻 existing text"
                    AXUIElementSetAttributeValue(destination, kAXValueAttribute as CFString, existing as CFString)
                    AXUIElementSetAttributeValue(destination, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    try await Task.sleep(nanoseconds: 150_000_000)
                    var caret = CFRange(location: 0, length: 0)
                    if let range = AXValueCreate(.cfRange, &caret) { AXUIElementSetAttributeValue(destination, kAXSelectedTextRangeAttribute as CFString, range) }
                    let initial = TextInsertion.captureTarget()
                    let target = remembersStart ? await TextInsertion.rememberStart(initial) : initial
                    caret.location = existing.utf16.count
                    if let range = AXValueCreate(.cfRange, &caret) { AXUIElementSetAttributeValue(destination, kAXSelectedTextRangeAttribute as CFString, range) }
                    try await Task.sleep(nanoseconds: 250_000_000)
                    if movesAway && remembersStart {
                        AXUIElementSetAttributeValue(destination === editor ? search : editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                        try await Task.sleep(nanoseconds: 150_000_000)
                    }
                    let result = try await TextInsertion.insert(" appended", into: target, pasteboard: board)
                    guard result == .textSent, stringValue(destination) == existing + " appended" else {
                        throw failure("Latest caret was lost: start=\(remembersStart), away=\(movesAway), search=\(destination === search), actual=\(stringValue(destination) ?? "nil")")
                    }
                }
            }
        }
        print("Existing text preserved at latest UTF-16 caret, native editor/search, current/start destination, focus changes: PASS")

        AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
        AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await Task.sleep(nanoseconds: 100_000_000)
        var selected = CFRange(location: 7, length: 8)
        if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }
        guard let beforeStart = TextInsertion.captureTarget(), beforeStart.app.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before Start check.") }
        let startWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        startWindow.isReleasedWhenClosed = false
        startWindow.title = "S2T Start verification"
        startWindow.center()
        startWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { startWindow.close() }
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let startTarget = TextInsertion.captureTarget(previousApp: history.previousApp), startTarget.restoreFromS2T else { throw failure("Start window did not become active.") }

        let startResult = try await TextInsertion.insert("S2T test", into: startTarget, pasteboard: board)
        try await Task.sleep(nanoseconds: 150_000_000)
        let startMatches = stringValue(editor) == "before S2T test after"
        print("Start return: \(startMatches ? "PASS" : "FAIL"), outcome=\(startResult.rawValue)")
        guard startMatches else { throw failure("Start return failed.") }

        AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
        AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        try await Task.sleep(nanoseconds: 100_000_000)
        if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before completion check.") }
        let previewPreferences = UserDefaults(suiteName: "com.s2t.preview")!
        let oldPaste = previewPreferences.object(forKey: "pasteToApp")
        previewPreferences.set(false, forKey: "pasteToApp")
        defer {
            if let oldPaste { previewPreferences.set(oldPaste, forKey: "pasteToApp") }
            else { previewPreferences.removeObject(forKey: "pasteToApp") }
        }
        let state = AppState(preview: true, outputPasteboard: board, insertText: { try await TextInsertion.insert($0, into: $1, pasteboard: board) })
        let oldMode = state.mode
        let initialProvider = state.processingProvider
        defer { state.cancel(); state.mode = oldMode; state.processingProvider = initialProvider }
        state.processingProvider = .openRouter
        state.mode = .verbatim
        state.rawTranscript = "S2T test"
        state.retry()
        for _ in 0..<300 {
            if state.phase == .complete { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let completeMatches = state.phase == .complete && stringValue(editor) == "before S2T test after" && board.string(forType: .string) == "S2T test"
        print("Full completion with old paste preference off: \(completeMatches ? "PASS" : "FAIL")")
        guard completeMatches else { throw failure("Full completion did not insert text: phase=\(state.phase), editor=\(stringValue(editor) ?? "nil"), clipboard=\(board.string(forType: .string) ?? "nil")") }

        AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
        AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before processing failure check.") }
        let oldProvider = state.processingProvider
        defer { state.processingProvider = oldProvider }
        state.processingProvider = .cerebras
        state.cerebrasKey = ""
        state.mode = .clean
        state.rawTranscript = "S2T test"
        state.retry()
        for _ in 0..<300 {
            if state.phase == .complete || state.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        let fallbackMatches = stringValue(editor) == "before S2T test after" && board.string(forType: .string) == "S2T test"
        print("Processing failure still inserts original: \(fallbackMatches ? "PASS" : "FAIL")")
        guard fallbackMatches else { throw failure("Processing failure blocked transcript delivery.") }
        for cancelPending in [false, true] {
            board.clearContents()
            board.setString("unrelated copied text", forType: .string)
            AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
            AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before menu delivery check.") }
            TextInsertion.menuIsOpen = true
            state.mode = .verbatim
            state.rawTranscript = "S2T test"
            state.retry()
            for _ in 0..<300 {
                if state.isWaitingToPaste { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard state.isWaitingToPaste, board.string(forType: .string) == "unrelated copied text", stringValue(editor) == "before selected after" else { throw failure("Menu-open delivery did not preserve clipboard and wait.") }
            if cancelPending { state.cancel() }
            TextInsertion.menuIsOpen = false
            for _ in 0..<300 {
                if !state.isWaitingToPaste { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            let expected = cancelPending ? "before selected after" : "before S2T test after"
            guard stringValue(editor) == expected, !state.isWaitingToPaste,
                  board.string(forType: .string) == (cancelPending ? "unrelated copied text" : "S2T test") else { throw failure("Menu dismissal or pending-paste cancellation failed.") }
            print("\(cancelPending ? "Cancel pending paste" : "Insert after menu dismissal"): PASS")
        }
        let savedPreferences = previewPreferences.dictionaryRepresentation()
        defer {
            for key in ["processingProvider", "writingMode", "fallbackModel", "cerebrasModel", "transcriptionMode"] {
                previewPreferences.set(savedPreferences[key], forKey: key)
            }
        }
        for provider in ProcessingProvider.allCases {
            for response in [200, 401, 402, 408, 206] {
                board.clearContents()
                board.setString("unrelated copied text", forType: .string)
                AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
                AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }

                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before pipeline check.") }
                let pipeline = AppState(preview: true, api: DictationAPI(transport: DeliveryTransport(status: response), codex: ProviderProbeCodex(fails: response != 200)), outputPasteboard: board, insertText: { try await TextInsertion.insert($0, into: $1, pasteboard: board) })
                pipeline.processingProvider = provider
                pipeline.transcriptionMode = .fast
                pipeline.mode = .clean
                pipeline.assemblyKey = "fixture-assembly"
                pipeline.routerKey = "fixture-router"
                pipeline.cerebrasKey = "fixture-cerebras"
                pipeline.processingModel = provider.defaultModel
                pipeline.processRecording(WaveAudio.encode(samples: Array(repeating: 120, count: 16000), sampleRate: 16000))
                for _ in 0..<300 {
                    if !pipeline.rawTranscript.isEmpty { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                guard board.string(forType: .string) == "unrelated copied text" else { throw failure("Clipboard changed while processing.") }
                for _ in 0..<300 {
                    if pipeline.phase == .complete || pipeline.phase == .failed { break }
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                let expected = response == 200 ? "Processed test" : "S2T test"
                guard pipeline.phase == .complete, board.string(forType: .string) == expected,
                      stringValue(editor) == "before \(expected) after",
                      (pipeline.processingFailureModel != nil) == (response != 200) else { throw failure("\(provider.title) pipeline status \(response) did not deliver the expected text.") }
                pipeline.cancel()
                print("\(provider.title) transcription to selected text, status \(response): PASS")
            }
        }
        for text in ["Grüße 日本語 👩🏽‍💻 e\u{301}", String(repeating: "Long dictation 🦊. ", count: 120), "First line\nSecond line\twith a tab"] {
            AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "before selected after" as CFString)
            AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if let range = AXValueCreate(.cfRange, &selected) { AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, range) }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else { throw failure("Fixture lost focus before Unicode check.") }
            let outcome = try await TextInsertion.insert(text, into: TextInsertion.captureTarget(), pasteboard: board)
            try await Task.sleep(nanoseconds: 200_000_000)
            guard outcome == .textSent, stringValue(editor) == "before \(text) after" else { throw failure("Unicode or long-text insertion failed.") }
            print("Unicode/long/multiline insertion, \(text.utf16.count) UTF-16 units: PASS")
        }
        guard NSPasteboard.general.changeCount == originalClipboardChange else { throw failure("System clipboard changed during verification.") }
        print("System clipboard untouched throughout delivery, processing and cancellation: PASS")



    }

    private static func stringValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        return value as? String
    }

    private static func find(_ identifier: String, in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value)
        if value as? String == identifier { return root }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let result = find(identifier, in: child) { return result }
        }
        return nil
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "InsertionProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}


private struct DeliveryTransport: HTTPTransport {
    let status: Int
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let transcription = url.host == "sync.assemblyai.com"
        if !transcription { try await Task.sleep(nanoseconds: 200_000_000) }
        if !transcription && status == 408 { throw URLError(.timedOut) }
        let json = transcription ? #"{"text":"S2T test"}"# : status == 206
            ? #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#
            : #"{"choices":[{"finish_reason":"stop","message":{"content":"Processed test"}}]}"#
        return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: transcription || status == 206 ? 200 : status, httpVersion: nil, headerFields: nil)!)
    }
}
