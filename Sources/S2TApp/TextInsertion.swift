import AppKit

@MainActor enum TextInsertion {
    static var menuIsOpen = false
    static let eventMarker: Int64 = 0x5332545041535445

    @MainActor final class Target {
        let app: NSRunningApplication
        var restoreFromS2T = false
        var restoreStart = false
        var field: AXUIElement?
        var selection: CFRange?
        private var tracking: Task<Void, Never>?

        init(app: NSRunningApplication, restoreFromS2T: Bool = false) {
            self.app = app
            self.restoreFromS2T = restoreFromS2T
        }

        func trackSelection() {
            stopTracking()
            tracking = Task { [weak self] in
                while !Task.isCancelled, self != nil {
                    await self?.refreshSelection()
                    do { try await Task.sleep(nanoseconds: 40_000_000) }
                    catch { return }
                }
            }
        }

        func refreshSelection() async {
            let pid = app.processIdentifier
            guard !menuIsOpen, let field,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let range = await Task.detached { selectionInFocusedField(field, pid: pid) }.value
            guard !Task.isCancelled, !menuIsOpen,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let range else { return }
            selection = range
        }

        func stopTracking() { tracking?.cancel(); tracking = nil }
        deinit { tracking?.cancel() }
    }

    enum Outcome: String {
        case textSent, permissionRequired, noTarget, unavailable
        var hint: String? {
            switch self {
            case .textSent: return nil
            case .permissionRequired: return "Allow Accessibility access to insert dictation. Your text is available in Last dictation."
            case .noTarget: return "Select a text field and retry. Your text is available in Last dictation."
            case .unavailable: return "Couldn't insert dictation. Your text is available in Last dictation."
            }
        }
    }

    static var diagnosticOutput: ((String) -> Void)?

    static func captureTarget(previousApp: NSRunningApplication? = nil) -> Target? {
        if let app = NSWorkspace.shared.frontmostApplication, !isS2T(app) { return Target(app: app) }
        guard let previousApp, !previousApp.isTerminated, !isS2T(previousApp) else { return nil }
        return Target(app: previousApp, restoreFromS2T: true)
    }

    static func copy(_ text: String, to board: NSPasteboard = .general) -> Bool {
        guard !text.isEmpty else { return false }
        if board.string(forType: .string) == text, board.data(forType: ClipboardMonitor.outputType) != nil { return true }
        board.clearContents()
        board.setData(Data(), forType: ClipboardMonitor.outputType)
        return board.setString(text, forType: .string) && board.string(forType: .string) == text
    }

    static func rememberStart(_ target: Target?) async -> Target? {
        guard let target else { return nil }
        target.restoreStart = true
        let pid = target.app.processIdentifier
        let captured = await Task.detached { focusedSelection(pid: pid) }.value
        guard !Task.isCancelled else { return nil }
        target.field = captured?.field
        target.selection = captured?.range
        if target.field != nil { target.trackSelection() }
        return target
    }

    static func insert(_ text: String, into target: Target?, pasteboard: NSPasteboard = .general) async throws -> Outcome {
        try Task.checkCancellation()
        guard !text.isEmpty else { return .unavailable }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        var waitedForMenu = false
        while menuIsOpen {
            waitedForMenu = true
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if waitedForMenu { try await Task.sleep(nanoseconds: 150_000_000) }
        try Task.checkCancellation()
        var destination: (field: AXUIElement, range: CFRange)?
        if let target, target.restoreStart {
            await target.refreshSelection()
            target.stopTracking()
            guard let field = target.field, let range = target.selection else { return .noTarget }
            destination = (field, range)
        }
        let returningFromS2T = NSWorkspace.shared.frontmostApplication.map(isS2T) == true
        if target?.restoreStart == true || returningFromS2T {
            guard let app = target?.app, !app.isTerminated else { return .noTarget }
            let pid = app.processIdentifier
            if destination == nil {
                destination = await Task.detached { focusedSelection(pid: pid) }.value
            }
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                NSApp.yieldActivation(to: app)
                app.activate(options: [])
                for _ in 0..<20 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .noTarget }
        }
        try Task.checkCancellation()
        guard let recipient = NSWorkspace.shared.frontmostApplication, !isS2T(recipient), !recipient.isTerminated else { return .noTarget }
        let pid = recipient.processIdentifier
        if let target, target.restoreStart, target.app.processIdentifier != pid { return .noTarget }
        let command = await Task.detached { () -> AXUIElement? in
            let root = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(root, 0.2)
            guard let menu = element(root, kAXMenuBarAttribute) else { return nil }
            var pending = [(menu, 0)]
            var visited = 0
            while let (item, depth) = pending.popLast(), visited < 250 {
                visited += 1
                if (value(item, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "v",
                   (value(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0 { return item }
                if depth < 4, let children = value(item, kAXChildrenAttribute) as? [AXUIElement] {
                    pending.append(contentsOf: children.prefix(100).reversed().map { ($0, depth + 1) })
                }
            }
            return nil
        }.value
        try Task.checkCancellation()
        guard let command else { return .unavailable }
        guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .noTarget }
        if let destination {
            guard try await restore(destination, pid: pid) else { return .noTarget }
        }
        try Task.checkCancellation()
        guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .noTarget }
        // Check the destination after all activation and menu work, immediately before the paste.
        let ready = await Task.detached { focusedSelection(pid: pid) }.value
        try Task.checkCancellation()
        if let destination {
            guard let ready, CFEqual(ready.field, destination.field), equal(ready.range, destination.range) else { return .noTarget }
        } else if let ready {
            guard try await restoreSelection(ready.range, read: {
                guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
                return await Task.detached { selectionInFocusedField(ready.field, pid: pid) }.value
            }, write: { _ in false }) else { return .noTarget }
        }
        guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return .noTarget }
        let result = pasteBatch(text, to: pasteboard) {
            AXUIElementPerformAction(command, kAXPressAction as CFString) == .success
        }
        if result == .textSent {
            diagnosticOutput?("native_paste_action")
            // AXPress can enqueue the recipient's paste. Keep text available before an image attachment replaces it.
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return result
    }

    private static func restore(_ destination: (field: AXUIElement, range: CFRange), pid: pid_t) async throws -> Bool {
        let field = destination.field
        let alreadyFocused = await Task.detached { selectionInFocusedField(field, pid: pid) != nil }.value
        try Task.checkCancellation()
        guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        if !alreadyFocused {
            let requested = await Task.detached { () -> Bool in
                AXUIElementSetMessagingTimeout(field, 0.2)
                if let window = element(field, kAXWindowAttribute) { _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
                return AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
            }.value
            guard requested else { return false }
            // Field editors can select all on the next run-loop turn after accepting AX focus.
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        return try await restoreSelection(destination.range, read: {
            guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return nil }
            return await Task.detached { selectionInFocusedField(field, pid: pid) }.value
        }, write: { range in
            guard !menuIsOpen, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
            return await Task.detached {
                guard selectionInFocusedField(field, pid: pid) != nil else { return false }
                var range = range
                guard let value = AXValueCreate(.cfRange, &range) else { return false }
                return AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, value) == .success
            }.value
        })
    }

    static func restoreSelection(_ range: CFRange, read: () async -> CFRange?, write: (CFRange) async -> Bool) async throws -> Bool {
        try Task.checkCancellation()
        guard let current = await read() else { return false }
        if !equal(current, range) {
            try Task.checkCancellation()
            guard await write(range) else { return false }
        }
        // A successful AX write is only an acknowledgement, not proof that the editor kept it.
        for _ in 0..<2 {
            try await Task.sleep(nanoseconds: 25_000_000)
            guard let actual = await read(), equal(actual, range) else { return false }
        }
        return true
    }

    nonisolated private static func equal(_ lhs: CFRange, _ rhs: CFRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }

    nonisolated private static func selectedRange(_ field: AXUIElement) -> CFRange? {
        guard let raw = value(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let axValue = raw as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= Int.max - range.length else { return nil }
        return range
    }

    nonisolated private static func focusedSelection(pid: pid_t) -> (field: AXUIElement, range: CFRange)? {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let field = element(root, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(field, 0.2)
        guard value(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let range = selectedRange(field),
              let after = element(root, kAXFocusedUIElementAttribute), CFEqual(field, after) else { return nil }
        return (field, range)
    }

    nonisolated private static func selectionInFocusedField(_ field: AXUIElement, pid: pid_t) -> CFRange? {
        guard let current = focusedSelection(pid: pid), CFEqual(current.field, field) else { return nil }
        return current.range
    }

    static func pasteBatch(_ text: String, to board: NSPasteboard, perform: () -> Bool) -> Outcome {
        guard !text.isEmpty else { return .unavailable }
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        guard copy(text, to: board) else { return .unavailable }
        let change = board.changeCount
        guard perform() else {
            if board.changeCount == change {
                board.clearContents()
                let items = saved.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                board.writeObjects(items)
            }
            return .unavailable
        }
        return .textSent
    }

    nonisolated private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    nonisolated private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(parent, attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func isS2T(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier || app.bundleIdentifier == Bundle.main.bundleIdentifier
    }
}
