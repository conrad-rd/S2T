import AppKit
import S2TCore

@MainActor enum RecentRecordingsProbe {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "RecentRecordingsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-transcripts-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.enc")
        func store(_ file: URL) -> TranscriptHistoryStore { TranscriptHistoryStore(file: file, key: { Data(repeating: 5, count: 32) }) }
        let history = RecentRecordings(store: store(file))
        let first = UUID(), second = UUID()
        let firstDate = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 60)
        history.record(id: first, text: "First complete transcript\nwith a second line.", appName: "Example editor", bundleID: "example.editor", date: firstDate)
        history.record(id: second, text: "Second transcript with Unicode: Grüße 日本語", appName: nil, bundleID: nil, date: firstDate.addingTimeInterval(10))
        history.record(id: first, text: "Updated first transcript", appName: nil, bundleID: nil)
        history.record(id: UUID(), text: "  \n", appName: nil, bundleID: nil)
        let restored = RecentRecordings(store: store(file))
        try require(restored.entries == history.entries && restored.entries.count == 2, "History must survive restart, reject empty text and deduplicate retries")
        let retried = restored.entries.first { $0.id == first }
        try require(retried?.appName == "Example editor" && retried?.bundleID == "example.editor", "Retry lost known application")
        try require(retried?.date == firstDate && restored.entries.first?.id == second,
                    "Retry changed the original recording date or displaced a newer recording")
        try require(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["history.enc"], "History wrote something besides transcript data")
        let corrupt = directory.appendingPathComponent("corrupt.json")
        let bytes = Data("invalid archive".utf8)
        try bytes.write(to: corrupt)
        let broken = RecentRecordings(store: store(corrupt))
        broken.record(id: UUID(), text: "New transcript", appName: nil, bundleID: nil)
        try require(RecentRecordings(store: store(corrupt)).entries.count == 1 && broken.error != nil, "Corrupt history prevented new durable entries")
        let board = NSPasteboard(name: .init("s2t-recent-probe-" + UUID().uuidString))
        let suite = "com.s2t.recent-probe." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite); board.clearContents() }
        let state = AppState(preview: true, previewPreferences: preferences, outputPasteboard: board)
        defer { state.cancel() }
        for index in 1...3 { state.recentRecordings.record(id: UUID(), text: "Full transcript \(index)\nSecond line", appName: "Example app", bundleID: nil, date: firstDate.addingTimeInterval(Double(index))) }
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        controller.statusItem.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        guard let copy = controller.menu.items.first(where: { $0.identifier?.rawValue == "result.copy" }) as? ActionMenuItem,
              copy.isEnabled else { throw NSError(domain: "RecentRecordingsProbe", code: 2) }
        copy.invoke()
        try require(board.string(forType: .string) == "Full transcript 3\nSecond line", "Copy last dictation selected the wrong saved transcript")
        controller.appearanceWindow.showRecentRecordings()
        let window = controller.appearanceWindow
        window.window?.contentView?.layoutSubtreeIfNeeded()
        try require(window.showingRecentRecordings && !window.recentRecordingsPane.isHidden && window.window?.isVisible == false, "Hidden transcript page failed to open")
        window.refresh()
        try require(window.showingRecentRecordings && !window.recentRecordingsPane.isHidden, "State refresh hid history")
        window.sidebar.selectAppearance()
        try require(!window.showingRecentRecordings && window.recentRecordingsPane.isHidden, "Appearance navigation failed")
        print("PASS: encrypted persistence, restart, retry identity/date/application preservation, chronological order, Unicode, corruption preservation, one last-dictation copy on isolated clipboard and hidden history navigation. No audio or screen capture.")
    }
}
