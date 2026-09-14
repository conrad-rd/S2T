import AppKit

@MainActor enum PromptImageInsertion {
    struct Result {
        let sentCount: Int
        let issue: String?
        let clipboardChange: Int
    }

    static func insert(_ images: [URL], recipient: pid_t?, board: NSPasteboard,
                       currentRecipient: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                       canPost: () -> Bool = { CGPreflightPostEventAccess() },
                       postPaste: @MainActor (pid_t) -> Bool = postPaste,
                       waitForPaste: () async throws -> Void = { try await Task.sleep(nanoseconds: 750_000_000) }) async throws -> Result {
        var sent = 0
        var clipboardChange = board.changeCount
        func result(_ issue: String? = nil) -> Result {
            Result(sentCount: sent, issue: issue, clipboardChange: clipboardChange)
        }
        try Task.checkCancellation()
        guard !images.isEmpty else { return result() }
        guard let recipient, recipient != ProcessInfo.processInfo.processIdentifier, canPost() else {
            return result("Couldn't paste screenshots. Attach the saved files from Reference images.")
        }
        guard !TextInsertion.menuIsOpen, currentRecipient() == recipient else {
            return result("Couldn't paste screenshots because focus changed. Use Reference images.")
        }
        var items: [NSPasteboardItem] = []
        for url in images {
            try Task.checkCancellation()
            guard let png = try? Data(contentsOf: url), !png.isEmpty else {
                return result("Couldn't read a reference image. Check the saved files in Reference images.")
            }
            let item = NSPasteboardItem()
            item.setData(Data(), forType: ClipboardMonitor.outputType)
            item.setData(png, forType: .png)
            item.setString(url.absoluteString, forType: .fileURL)
            items.append(item)
        }
        try Task.checkCancellation()
        guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, board.changeCount == clipboardChange else {
            return result("Couldn't paste screenshots because focus or the clipboard changed. Use Reference images.")
        }
        board.clearContents()
        guard board.writeObjects(items) else {
            clipboardChange = board.changeCount
            return result("Couldn't copy screenshots for attachment. Use Reference images.")
        }
        clipboardChange = board.changeCount
        guard postPaste(recipient) else { return result("Couldn't paste screenshots. Use Reference images.") }
        sent = images.count
        try await waitForPaste()
        try Task.checkCancellation()
        return result()
    }

    private static func postPaste(_ recipient: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        source.localEventsSuppressionInterval = 0
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: TextInsertion.eventMarker)
            event.postToPid(recipient)
        }
        return true
    }
}
