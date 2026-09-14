import AppKit
import S2TCore

@MainActor enum ClipboardProbe {
    static func run() async throws {
        try verifyPersistence()
        try verifyRelaunch()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board)
        defer { monitor.stop() }
        board.setString("https://youtu.be/fixture", forType: .string)
        monitor.start()
        guard monitor.snapshot().entries.count == 1 else { throw failure("Initial clipboard was not captured") }
        board.clearContents()
        board.setString("fixture copied text", forType: .string)
        for _ in 0..<50 {
            if monitor.itemCount == 2 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let snapshot = monitor.snapshot()
        guard snapshot.entries.first?.text == "fixture copied text", snapshot.entries.count == 2 else { throw failure("Clipboard change was not captured") }
        for text in ["S2T original transcript", "S2T finished dictation", "Copy last dictation"] {
            guard TextInsertion.copy(text, to: board) else { throw failure("S2T copy failed") }
            monitor.poll()
            guard monitor.itemCount == 2 else { throw failure("S2T copy entered history") }
        }
        guard monitor.snapshot().entries.count == 2,
              snapshot.context(for: "this YouTube video").items.first?.value == "https://youtu.be/fixture" else { throw failure("Dictation overwrote its clipboard context") }
        monitor.clear()
        guard monitor.snapshot().entries.isEmpty else { throw failure("Clear recaptured the current clipboard") }
        monitor.stop()
        board.clearContents()
        board.setString("must not capture while disabled", forType: .string)
        guard monitor.snapshot().entries.isEmpty else { throw failure("Disabled monitor read the clipboard") }
        monitor.start()
        guard monitor.snapshot().entries.count == 1 else { throw failure("Monitor did not resume") }

        let state = AppState(preview: true, clipboardMonitor: monitor)
        let previous = state.clipboardContextEnabled
        state.clipboardContextEnabled = true
        monitor.start()
        defer { state.clipboardContextEnabled = previous }
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.menuNeedsUpdate(controller.menu)
        let historyItem = controller.menu.items.first { $0.identifier?.rawValue == "clipboard.history" }!
        let historyMenu = historyItem.submenu!
        controller.menuNeedsUpdate(historyMenu)
        guard let historyView = historyMenu.items.compactMap({ $0.view as? ClipboardHistoryView }).first,
              historyView.textView.string.contains("must not capture while disabled") else { throw failure("History submenu did not show remembered text") }
        board.clearContents()
        board.setString("latest fixture link https://example.com/new", forType: .string)
        monitor.poll()
        controller.refreshStatus()
        guard historyView.textView.string.contains("https://example.com/new"), historyItem.title.hasSuffix("2") else { throw failure("Open history did not refresh in place") }
        let fakeKey = "sk-or-v1-" + String(repeating: "a", count: 40)
        board.clearContents()
        board.setString(fakeKey, forType: .string)
        monitor.poll()
        controller.refreshStatus()
        guard !historyView.textView.string.contains(fakeKey), historyView.textView.string.contains("API key · ••••aaaa") else { throw failure("History exposed a raw key") }
        state.clearClipboardHistory()
        controller.refreshStatus()
        guard historyView.textView.string.contains("No remembered items"), historyItem.title.hasSuffix("0") else { throw failure("Cleared history remained visible") }
        let dictation = controller.menu.items.first { $0.identifier?.rawValue == "dictation" }!.submenu!
        controller.menuNeedsUpdate(dictation)
        let settings = dictation.items.first { $0.identifier?.rawValue == "clipboard" }!.submenu!
        controller.menuNeedsUpdate(settings)
        guard let toggle = settings.items.first(where: { $0.identifier?.rawValue == "clipboard.enabled" }) as? ActionMenuItem else { throw failure("Missing clipboard setting") }
        guard let historyToggle = historyMenu.items.first(where: { $0.identifier?.rawValue == "clipboard.enabled" }) as? ActionMenuItem,
              historyToggle.title == "Enable clipboard history", historyToggle.state == .on else { throw failure("Missing enabled history toggle in the history menu") }
        historyToggle.invoke()
        guard !state.clipboardContextEnabled,
              !monitor.isRunning, historyToggle.state == .off,
              toggle.state == (state.clipboardContextEnabled ? .on : .off) else { throw failure("Clipboard setting did not update in place") }
        board.clearContents()
        board.setString("copy after disabling from history menu", forType: .string)
        guard monitor.snapshot().entries.isEmpty else { throw failure("History menu toggle did not stop capture") }
        guard historyView.textView.string.contains("Clipboard history is off") else { throw failure("Disabled history kept content visible") }
        toggle.invoke()
        guard state.clipboardContextEnabled, historyToggle.state == .on, toggle.state == .on else { throw failure("Clipboard toggles did not stay synchronized") }
        state.phase = .recording
        controller.refreshStatus()
        guard !toggle.isEnabled, !historyToggle.isEnabled else { throw failure("Clipboard setting changes during dictation") }
        print("PASS: clipboard capture, retained history before transcript copy, automatic/manual copy exclusion, clear, stop/resume, live history previews, masked keys, and menu metadata.")
        print("Used an isolated pasteboard. No general clipboard reads or writes, visible menus, provider calls, or screen capture.")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ClipboardProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func verifyPersistence() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("clipboard.enc")
        func store() -> ClipboardHistoryStore { ClipboardHistoryStore(url: url, key: { Data(repeating: 42, count: 32) }) }
        board.setString("persistent fixture text", forType: .string)
        let first = ClipboardMonitor(pasteboard: board, persistence: store())
        first.start()
        let original = first.entries
        guard try store().load().history.entries == original, original.count == 1 else { throw failure("Clipboard copy was not saved immediately.") }
        first.stop()
        guard first.entries == original else { throw failure("Stopping deleted clipboard history.") }
        let reopened = ClipboardMonitor(pasteboard: board, persistence: store())
        guard reopened.entries == original else { throw failure("Launch did not restore clipboard history.") }
        reopened.start()
        guard reopened.entries == original else { throw failure("Launch refreshed the previous copy's timestamp.") }
        reopened.clear()
        reopened.stop()
        let cleared = ClipboardMonitor(pasteboard: board, persistence: store())
        cleared.start()
        guard cleared.entries.isEmpty else { throw failure("Relaunch resurrected cleared clipboard content.") }
        cleared.stop()

        let state = AppState(preview: true, clipboardMonitor: first)
        let enabled = state.clipboardContextEnabled
        defer { state.clipboardContextEnabled = enabled }
        state.clipboardContextEnabled = false
        guard first.entries == original else { throw failure("Disabling capture deleted history.") }

        let failing = FailingClipboardStore(backing: store())
        let retry = ClipboardMonitor(pasteboard: board, persistence: failing)
        failing.canSave = false
        board.clearContents()
        board.setString("unsaved fixture", forType: .string)
        retry.start()
        guard retry.persistenceError != nil, retry.itemCount == 1 else { throw failure("Write failure lost history or was hidden.") }
        failing.canSave = true
        retry.poll()
        guard retry.persistenceError == nil, try store().load().history.entries == retry.entries else { throw failure("Failed write was not retried.") }
        retry.stop()

        let savedBytes = try Data(contentsOf: url)
        failing.canLoad = false
        let locked = ClipboardMonitor(pasteboard: board, persistence: failing)
        board.clearContents()
        board.setString("copy while store unavailable", forType: .string)
        locked.start()
        guard locked.persistenceError != nil, try Data(contentsOf: url) == savedBytes else { throw failure("Failed load overwrote saved history.") }
        failing.canLoad = true
        locked.poll()
        guard locked.persistenceError == nil,
              locked.entries.map(\.text) == ["copy while store unavailable", "unsaved fixture"],
              try store().load().history.entries == locked.entries else { throw failure("Recovery did not merge saved and pending copies.") }
        locked.stop()
        print("PASS: immediate encrypted saves, stop/disable preservation, restored timestamps, durable clear, write retry and failed-load protection.")
    }

    private static func verifyRelaunch() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("cross-process clipboard fixture", forType: .string)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("clipboard.enc")
        for phase in ["write", "read"] {
            let process = Process()
            process.executableURL = Bundle.main.executableURL
            process.arguments = ["--clipboard-relaunch-fixture", url.path, board.name.rawValue, phase]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw failure("Clipboard persistence fixture failed during \(phase).") }
        }
        print("PASS: separate app processes save on copy, quit, relaunch, and retain exact entries and dates.")
    }

    static func relaunchFixture(url: URL, boardName: String, reading: Bool) throws {
        let store = ClipboardHistoryStore(url: url, key: { Data(repeating: 42, count: 32) })
        let board = NSPasteboard(name: NSPasteboard.Name(boardName))
        let monitor = ClipboardMonitor(pasteboard: board, persistence: store)
        let original = monitor.entries
        guard original.count == (reading ? 1 : 0) else { throw failure("Unexpected restored fixture count.") }
        monitor.start()
        guard monitor.entries.first?.text == "cross-process clipboard fixture",
              !reading || monitor.entries == original else { throw failure("Relaunch changed fixture text or dates.") }
        monitor.stop()
        guard try store.load().history.entries == monitor.entries else { throw failure("Quit did not retain fixture history.") }
    }
}

private final class FailingClipboardStore: ClipboardHistoryPersistence {
    let backing: ClipboardHistoryStore
    var canLoad = true
    var canSave = true
    init(backing: ClipboardHistoryStore) { self.backing = backing }
    func load(at date: Date) throws -> ClipboardArchive {
        guard canLoad else { throw CocoaError(.fileReadNoPermission) }
        return try backing.load(at: date)
    }
    func save(_ archive: ClipboardArchive) throws {
        guard canSave else { throw CocoaError(.fileWriteNoPermission) }
        try backing.save(archive)
    }
}
