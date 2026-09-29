import AppKit

@MainActor enum PasteBatchProbe {
    static func run() async throws {
        try verifyBoundedMenuSearch()
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
        editor.string = "before selected after"
        editor.setSelectedRange(NSRange(location: 7, length: 8))
        var delayedPaste: Task<Bool, Never>?
        let queued = TextInsertion.pasteBatch(text, to: board) {
            delayedPaste = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                return editor.readSelection(from: board)
            }
            return true
        }
        let queuedChange = board.changeCount
        guard queued == .textSent, TextInsertion.copy(text, to: board),
              board.changeCount == queuedChange,
              await delayedPaste?.value == true,
              editor.string == "before " + text + " after" else {
            throw failure("Immediate dictation completion invalidated a queued native paste")
        }
        board.clearContents()
        board.setString("previous clipboard", forType: .string)
        guard TextInsertion.pasteBatch(text, to: board, perform: { false }) == .unavailable,
              board.string(forType: .string) == "previous clipboard" else { throw failure("Failed paste did not restore clipboard") }
        let unicodeText = String(repeating: "Grüße 日本語 👩🏽‍💻 e\u{301}\n", count: 25)
        editor.string = "before selected after"
        editor.setSelectedRange(NSRange(location: 7, length: 8))
        let priorChange = board.changeCount
        var posted = 0
        let direct = try await TextInsertion.sendUnicode(unicodeText, to: 123, pasteboard: board,
            canPost: { true }, post: { event, pid in
                precondition(pid == 123 && event.flags.isEmpty)
                precondition(board.changeCount == priorChange)
                precondition(event.getIntegerValueField(.eventSourceUserData) == TextInsertion.eventMarker)
                posted += 1
                if event.type == .keyDown, let native = NSEvent(cgEvent: event), let characters = native.characters {
                    editor.insertText(characters, replacementRange: editor.selectedRange())
                }
            })
        guard direct == .textSent, posted > 2,
              editor.string == "before " + unicodeText + " after",
              board.string(forType: .string) == unicodeText else { throw failure("Menu-independent Unicode delivery corrupted text or selection") }
        let afterDirect = board.changeCount
        var forbiddenPosts = 0
        for permission in [false, true] {
            let rejected = try await TextInsertion.sendUnicode("rejected", to: 123, pasteboard: board,
                canPost: { permission }, isCurrent: { false }, post: { _, _ in forbiddenPosts += 1 })
            guard rejected == (permission ? .noTarget : .permissionRequired) else { throw failure("Unicode permission/focus guard failed") }
        }
        let stopped = Task { @MainActor in
            try await TextInsertion.sendUnicode("cancelled", to: 123, pasteboard: board,
                canPost: { true }, post: { _, _ in forbiddenPosts += 1 })
        }
        stopped.cancel()
        do { _ = try await stopped.value; throw failure("Cancelled Unicode delivery continued") }
        catch is CancellationError { }
        guard forbiddenPosts == 0, board.changeCount == afterDirect else { throw failure("Rejected Unicode delivery changed clipboard or posted events") }
        print("Missing Paste-menu fallback: generated Unicode events preserve selected text, emoji, multiline content; clipboard changes only after delivery; permission, focus and cancellation guarded. No events posted to real apps: PASS")
        let state = AppState(preview: true)
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        controller.menuNeedsUpdate(controller.menu)
        controller.appearanceWindow.showDictation()
        guard controller.appearanceWindow.showingDictation else {
            throw failure("Dictation settings did not open")
        }
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
        pipeline.phase = .failed
        pipeline.retry()
        for _ in 0..<300 {
            if pipeline.phase == .complete || pipeline.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard pipeline.phase == .complete, editor.string == "before " + text + " after",
              requestedChange == board.changeCount else { throw failure("Completion changed the clipboard after the native paste request") }
        print("Batch paste: preserved existing Unicode text at restored caret, ignored writes and delayed select-all rejected, lost focus and cancellation guarded, one native editor operation, selection replacement, clipboard rollback and completion PASS. Isolated clipboard; no screen capture or real fields.")
    }
    private static func verifyBoundedMenuSearch() throws {
        let root = AXUIElementCreateApplication(2_990_000)
        let menu = AXUIElementCreateApplication(2_990_001)
        let items = (2...252).map { AXUIElementCreateApplication(2_990_000 + Int32($0)) }
        var clock = 0.0, reads = 0, delay = 0.025
        let paste = items[6]
        func read(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            clock += delay; reads += 1
            if CFEqual(node, root), name == kAXMenuBarAttribute { return menu }
            if CFEqual(node, menu), name == kAXChildrenAttribute { return items as CFArray }
            if CFEqual(node, paste) {
                if name == kAXMenuItemCmdCharAttribute { return "v" as CFString }
                if name == kAXMenuItemCmdModifiersAttribute { return NSNumber(value: 0) }
            }
            return nil
        }
        let missing = PasteCommandSearch.search(root: root, deadline: PasteCommandSearch.budget, now: { clock }, read: read)
        guard missing == nil, clock <= PasteCommandSearch.budget + delay, reads < 16 else {
            throw failure("An unresponsive Paste menu exceeded its whole-search deadline")
        }
        clock = 0; reads = 0; delay = 0.001
        guard let found = PasteCommandSearch.search(root: root, deadline: 0.3, now: { clock }, read: read), CFEqual(found, paste) else {
            throw failure("Bounded menu discovery lost an ordinary native Paste item")
        }
        reads = 0
        guard PasteCommandSearch.search(root: root, cached: found, deadline: 0.3, now: { clock }, read: read) != nil,
              reads == 2 else { throw failure("Repeated Paste discovery scanned the entire menu again") }
        var counter: UInt32 = 10
        let snapshot = DeliveryInteractionSnapshot(read: { _ in counter })
        guard snapshot.isUnchanged else { throw failure("Unchanged delivery interaction rejected") }
        counter += 1
        guard !snapshot.isUnchanged else { throw failure("A new physical interaction permitted focus restoration") }
        print("PASS: slow native menu discovery bounded to 300 ms; cached Paste uses two reads; new physical interaction invalidates focus restoration. Synthetic metadata and event counts only.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "PasteBatchProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

}
