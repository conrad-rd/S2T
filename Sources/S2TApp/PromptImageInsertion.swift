import AppKit

@MainActor enum PromptImageInsertion {
    enum Confirmation { case confirmed, absent, unknown, notSent }
    struct Result {
        let sentCount: Int
        let issue: String?
        let clipboardChange: Int
        var confirmation: Confirmation = .unknown
        var targetChanged = false
        var recheck: (@MainActor () async -> Confirmation)?
        var clipboardWasRead: (@MainActor () -> Bool)?
        /// When the recipient had the screenshots: read from the clipboard, or the wait ran out.
        var completedAt = ProcessInfo.processInfo.systemUptime
        /// Finishes confirmation after hand-over. Nil when the result is already final.
        var confirm: (@MainActor () async throws -> Result)?
        var canReleaseClipboard: Bool { confirmation == .confirmed || sentCount == 0 }
    }

    /// The prompt text needs this long on the clipboard before screenshots replace it.
    static let textSettle = 0.25

    static func insert(_ images: [URL], recipient: pid_t?, board: NSPasteboard,
                       observe: @escaping @MainActor (pid_t, [String]) async -> PromptAttachmentSnapshot? = PromptAttachmentVerifier.snapshot,
                       currentRecipient: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                       destinationIsCurrent: @escaping @MainActor () async -> Bool = { true },
                       nativePaste: (@MainActor () async -> AXError)? = nil,
                       canPost: () -> Bool = { CGPreflightPostEventAccess() },
                       postPaste: @MainActor (pid_t) -> Bool = postPaste,
                       waitForPaste: (() async throws -> Void)? = nil,
                       textPastedAt: Double? = nil) async throws -> Result {
        let handed = try await handOver(images, recipient: recipient, board: board, observe: observe, currentRecipient: currentRecipient,
            destinationIsCurrent: destinationIsCurrent, nativePaste: nativePaste, canPost: canPost, postPaste: postPaste,
            waitForPaste: waitForPaste, textPastedAt: textPastedAt)
        return try await handed.confirm?() ?? handed
    }

    /// Pastes the screenshots and returns once the recipient has read them. The slower
    /// Accessibility confirmation runs later through `confirm`, so delivery can finish first.
    static func handOver(_ images: [URL], recipient: pid_t?, board: NSPasteboard,
                         observe: @escaping @MainActor (pid_t, [String]) async -> PromptAttachmentSnapshot? = PromptAttachmentVerifier.snapshot,
                         currentRecipient: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                         destinationIsCurrent: @escaping @MainActor () async -> Bool = { true },
                         nativePaste: (@MainActor () async -> AXError)? = nil,
                         canPost: () -> Bool = { CGPreflightPostEventAccess() },
                         postPaste: @MainActor (pid_t) -> Bool = postPaste,
                         waitForPaste: (() async throws -> Void)? = nil,
                         textPastedAt: Double? = nil) async throws -> Result {
        var sent = 0
        var confirmation = Confirmation.notSent
        var targetChanged = false
        var clipboardChange = board.changeCount
        var recheck: (@MainActor () async -> Confirmation)?
        var payload: PromptClipboardPayload?
        func result(_ issue: String? = nil) -> Result {
            Result(sentCount: sent, issue: issue, clipboardChange: clipboardChange, confirmation: confirmation, targetChanged: targetChanged,
                recheck: recheck, clipboardWasRead: payload.map { payload in { payload.wasRead } })
        }
        try Task.checkCancellation()
        guard !images.isEmpty else { return result() }
        guard let recipient, recipient != ProcessInfo.processInfo.processIdentifier, nativePaste != nil || canPost() else {
            return result("Couldn't paste screenshots. Attach the saved files from Reference images.")
        }
        guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, await destinationIsCurrent() else {
            return result("Couldn't paste screenshots because focus changed. Use Reference images.")
        }
        let names = images.map(\.lastPathComponent)
        let baseline = await observe(recipient, names)
        try Task.checkCancellation()
        guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, board.changeCount == clipboardChange, await destinationIsCurrent() else {
            return result("Attachment preparation stopped because focus or the clipboard changed.")
        }
        if let baseline, baseline.names.isSuperset(of: names) {
            confirmation = .confirmed
            return result()
        }
        let loading = Task.detached(priority: .userInitiated) { try images.map { try Data(contentsOf: $0) } }
        let data: [Data]
        do { data = try await withTaskCancellationHandler { try await loading.value } onCancel: { loading.cancel() } }
        catch { try Task.checkCancellation(); return result("Couldn't read a reference image. Check the saved files in Reference images.") }
        guard data.allSatisfy({ !$0.isEmpty }) else { return result("A reference image is empty. Use Reference images.") }
        let contents = PromptClipboardPayload(images: images, data: data)
        payload = contents
        var items: [NSPasteboardItem] = []
        for index in images.indices {
            let item = NSPasteboardItem()
            item.setData(Data(), forType: ClipboardMonitor.outputType)
            contents.register(item, at: index)
            item.setDataProvider(contents, forTypes: [.png, .fileURL])
            items.append(item)
        }
        // The Accessibility read and file loading above overlap the text's clipboard settle time.
        if let textPastedAt {
            let remaining = textPastedAt + textSettle - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }
        try Task.checkCancellation()
        guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, board.changeCount == clipboardChange, await destinationIsCurrent() else {
            return result("Couldn't paste screenshots because focus or the clipboard changed. Use Reference images.")
        }
        board.clearContents()
        guard board.writeObjects(items) else {
            clipboardChange = board.changeCount
            return result("Couldn't copy screenshots for attachment. Use Reference images.")
        }
        clipboardChange = board.changeCount
        let pasted: Bool
        if let nativePaste {
            let response = await nativePaste()
            if response == .actionUnsupported || response == .notImplemented {
                let matches = await destinationIsCurrent()
                try Task.checkCancellation()
                guard matches, !TextInsertion.menuIsOpen, currentRecipient() == recipient,
                      board.changeCount == clipboardChange else {
                    return result("Screenshot paste stopped because focus or the clipboard changed.")
                }
                pasted = canPost() && postPaste(recipient)
            } else { pasted = response == .success || response == .cannotComplete }
        } else { pasted = postPaste(recipient) }
        guard pasted else { return result("Couldn't paste screenshots. Use Reference images.") }
        sent = images.count
        if let baseline {
            recheck = {
                guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, await destinationIsCurrent(),
                      let current = await observe(recipient, names), currentRecipient() == recipient else { return .unknown }
                return Self.confirmation(before: baseline, after: current, names: names)
            }
        }
        confirmation = .unknown
        if let waitForPaste { try await waitForPaste() }
        else {
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            while !contents.wasRead, ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
                guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, board.changeCount == clipboardChange else { break }
            }
        }
        try Task.checkCancellation()
        var handed = result()
        handed.completedAt = ProcessInfo.processInfo.systemUptime
        let settles = waitForPaste == nil && contents.wasRead
        handed.confirm = {
            // Give the recipient a moment to show the attachments before reading them back.
            if settles { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            guard !TextInsertion.menuIsOpen, currentRecipient() == recipient, board.changeCount == clipboardChange, await destinationIsCurrent() else {
                let matchesDestination = await destinationIsCurrent()
                targetChanged = currentRecipient() != recipient || !matchesDestination
                return result("Attachment confirmation stopped because focus or the clipboard changed.")
            }
            if let baseline, let after = await observe(recipient, names) {
                guard after.field == baseline.field else {
                    targetChanged = true
                    return result("The input changed while attaching screenshots. Your prompt is retained in Last dictation.")
                }
                confirmation = Self.confirmation(before: baseline, after: after, names: names)
            }
            return result()
        }
        return handed
    }

    private static func confirmation(before: PromptAttachmentSnapshot, after: PromptAttachmentSnapshot, names: [String]) -> Confirmation {
        guard before.field == after.field else { return .unknown }
        if after.names.isSuperset(of: names) || after.images - before.images >= names.count { return .confirmed }
        if !after.busy, after.images == before.images, after.names == before.names { return .absent }
        return .unknown
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

private final class PromptClipboardPayload: NSObject, NSPasteboardItemDataProvider {
    private let images: [URL]
    private let data: [Data]
    private var indices: [ObjectIdentifier: Int] = [:]
    private var read = Set<Int>()
    private let lock = NSLock()

    init(images: [URL], data: [Data]) { self.images = images; self.data = data }
    func register(_ item: NSPasteboardItem, at index: Int) { indices[ObjectIdentifier(item)] = index }
    var wasRead: Bool { lock.lock(); defer { lock.unlock() }; return read.count == images.count }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let index = indices[ObjectIdentifier(item)] else { return }
        if type == .png { item.setData(data[index], forType: type) }
        else if type == .fileURL { item.setString(images[index].absoluteString, forType: type) }
        else { return }
        lock.lock(); read.insert(index); lock.unlock()
    }
}
