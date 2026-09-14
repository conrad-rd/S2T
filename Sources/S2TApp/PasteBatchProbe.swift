import AppKit

@MainActor enum PasteBatchProbe {
    static func run() async throws {
        let board = NSPasteboard(name: .init("S2T.PasteBatch.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let existing = "Grüße 👩🏽‍💻 existing text"
        let end = CFRange(location: existing.utf16.count, length: 0)
        editor.string = existing
        editor.setSelectedRange(NSRange(location: 0, length: existing.utf16.count))
        let restored = try await TextInsertion.restoreSelection(end, read: {
            let range = editor.selectedRange()
            return CFRange(location: range.location, length: range.length)
        }, write: { range in
            editor.setSelectedRange(NSRange(location: range.location, length: range.length))
            return true
        })
        guard restored, TextInsertion.pasteBatch(" appended", to: board, perform: { editor.readSelection(from: board) }) == .textSent,
              editor.string == existing + " appended" else { throw failure("Caret restoration replaced existing Unicode text") }
        let ignored = try await TextInsertion.restoreSelection(end, read: { CFRange(location: 0, length: existing.utf16.count) }, write: { _ in true })
        guard !ignored else { throw failure("An ignored selection write was accepted") }
        var reads = 0
        let delayedReset = try await TextInsertion.restoreSelection(end, read: {
            reads += 1
            return reads < 3 ? end : CFRange(location: 0, length: existing.utf16.count)
        }, write: { _ in true })
        guard !delayedReset else { throw failure("A deferred select-all was accepted") }
        var unexpectedWrites = 0
        let lostFocus = try await TextInsertion.restoreSelection(end, read: { nil }, write: { _ in
            unexpectedWrites += 1
            return true
        })
        guard !lostFocus, unexpectedWrites == 0 else { throw failure("Missing focused field was accepted") }
        let cancelled = Task {
            try await TextInsertion.restoreSelection(end, read: { end }, write: { _ in true })
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw failure("Cancelled restoration continued")
        } catch is CancellationError { }
        let text = String(repeating: "First second third. Grüße 日本語 👩🏽‍💻\n", count: 100)
        editor.string = "before selected after"
        editor.setSelectedRange(NSRange(location: 7, length: 8))
        var calls = 0
        let outcome = TextInsertion.pasteBatch(text, to: board) {
            calls += 1
            return editor.readSelection(from: board)
        }
        guard outcome == .textSent, calls == 1, editor.string == "before " + text + " after",
              board.string(forType: .string) == text,
              board.data(forType: ClipboardMonitor.outputType) != nil else { throw failure("Whole-text selection replacement failed") }
        let deliveredChange = board.changeCount
        guard TextInsertion.copy(text, to: board), board.changeCount == deliveredChange else { throw failure("Completion rewrote the in-flight clipboard") }
        board.clearContents()
        board.setString("previous clipboard", forType: .string)
        guard TextInsertion.pasteBatch(text, to: board, perform: { false }) == .unavailable,
              board.string(forType: .string) == "previous clipboard" else { throw failure("Failed paste did not restore clipboard") }
        let state = AppState(preview: true)
        let saved = state.pasteAtStart
        defer { state.pasteAtStart = saved }
        state.pasteAtStart = true
        guard AppState(preview: true).pasteAtStart else { throw failure("Start destination was not persisted") }
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        controller.menuNeedsUpdate(controller.menu)
        guard let settings = controller.menu.items.first(where: { $0.identifier?.rawValue == "dictation" })?.submenu else { throw failure("Dictation menu missing") }
        controller.menuNeedsUpdate(settings)
        guard let row = settings.items.first(where: { $0.identifier?.rawValue == "dictation.pasteAtStart" }), row.state == .on else { throw failure("Destination option missing or unchecked") }
        editor.string = "before selected after"
        editor.setSelectedRange(NSRange(location: 7, length: 8))
        var requestedChange = -1
        let pipeline = AppState(preview: true, outputPasteboard: board, insertText: { output, _ in
            TextInsertion.pasteBatch(output, to: board) {
                requestedChange = board.changeCount
                return editor.readSelection(from: board)
            }
        })
        let oldMode = pipeline.mode
        defer { pipeline.cancel(); pipeline.mode = oldMode }
        pipeline.mode = .verbatim
        pipeline.rawTranscript = text
        pipeline.retry()
        for _ in 0..<300 {
            if pipeline.phase == .complete || pipeline.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard pipeline.phase == .complete, editor.string == "before " + text + " after",
              requestedChange == board.changeCount else { throw failure("Completion changed the clipboard after the native paste request") }
        print("Batch paste: preserved existing Unicode text at restored caret, ignored writes and delayed select-all rejected, lost focus and cancellation guarded, one native editor operation, selection replacement, clipboard rollback, completion, destination persistence and menu metadata PASS. Isolated clipboard; no screen capture or real fields.")
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "PasteBatchProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

}
