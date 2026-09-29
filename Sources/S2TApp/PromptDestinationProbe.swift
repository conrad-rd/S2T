import AppKit
import S2TCore

@MainActor enum PromptDestinationProbe {
    static func run() async throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw ServiceError.message(message) } }
        let pid: pid_t = 2_960_000
        let app = AXUIElementCreateApplication(pid)
        let nodes = (1...11).map { AXUIElementCreateApplication(pid + Int32($0)) }
        let window = nodes[0], otherWindow = nodes[1], first = nodes[2], finish = nodes[3], later = nodes[4]
        let doc1 = nodes[5], doc2 = nodes[6], tabs = nodes[7], tab1 = nodes[8], tab2 = nodes[9], otherField = nodes[10]
        var focus = first, focusedWindow = window, selectedTab = tab1
        var caret = CFRange(location: 4, length: 0), closed = false, minimized = false, secure = false, rejectedFocus = false
        var fieldText = "Fixture destination", readsFieldText = false, actions = 0, hasTabs = true, appFocusMissing = false
        func same(_ a: AXUIElement, _ b: AXUIElement) -> Bool { CFEqual(a, b) }
        let access = PromptDestinationAccess(attribute: { node, name in
            if same(node, app) {
                if name == kAXFocusedUIElementAttribute { return appFocusMissing ? nil : focus }
                if name == kAXFocusedWindowAttribute { return focusedWindow }
                return nil
            }
            let field = [first, finish, later, otherField].contains { same(node, $0) }
            if name == kAXValueAttribute, field { readsFieldText = true; return fieldText as CFString }
            if closed && (same(node, window) || same(node, finish)) { return nil }
            switch name {
            case kAXRoleAttribute:
                if same(node, window) || same(node, otherWindow) { return kAXWindowRole as CFString }
                if field { return kAXTextAreaRole as CFString }
                if same(node, doc1) || same(node, doc2) { return "AXWebArea" as CFString }
                if same(node, tabs) { return kAXTabGroupRole as CFString }
                return kAXRadioButtonRole as CFString
            case kAXSubroleAttribute: return secure && same(node, finish) ? kAXSecureTextFieldSubrole as CFString : nil
            case kAXWindowAttribute: return same(node, otherField) ? otherWindow : field ? window : nil
            case kAXParentAttribute:
                if same(node, first) || same(node, otherField) { return doc1 }
                if same(node, finish) || same(node, later) { return doc2 }
                return window
            case kAXSelectedAttribute: return same(node, selectedTab) ? kCFBooleanTrue : kCFBooleanFalse
            case kAXSelectedTextRangeAttribute: var range = caret; return field ? AXValueCreate(.cfRange, &range) : nil
            case kAXMinimizedAttribute: return minimized ? kCFBooleanTrue : kCFBooleanFalse
            default: return nil
            }
        }, children: { node in
            if same(node, window) { return hasTabs ? [tabs, doc1, doc2] : [doc1, doc2] }
            if same(node, tabs) { return [tab1, tab2] }
            return []
        }, action: { node, name in
            actions += 1
            if name == kAXRaiseAction { focusedWindow = node }
            if name == kAXPressAction { selectedTab = node; focus = same(node, tab1) ? first : finish }
            return true
        }, write: { node, name, value in
            if rejectedFocus { return false }
            if name == kAXFocusedAttribute { focus = node }
            if name == kAXMinimizedAttribute, same(node, window) { minimized = false }
            if name == kAXSelectedTextRangeAttribute { AXValueGetValue(value as! AXValue, .cfRange, &caret) }
            return true
        })
        let started = access.capture(pid: pid)!
        focus = finish; selectedTab = tab2
        guard let destination = access.capture(pid: pid) else { throw ServiceError.message("Finish destination was not captured") }
        try check(!same(started.field, destination.field) && same(destination.field, finish), "Destination followed Start instead of Finish")
        focus = first; selectedTab = tab1; focusedWindow = otherWindow
        try check(!access.isCurrent(destination) && !access.isVisible(destination), "A different tab was accepted as the destination")
        try check(access.restore(destination) && same(focus, finish) && same(selectedTab, tab2) && same(focusedWindow, window), "Original window/tab/field were not restored")
        minimized = true
        try check(access.restore(destination) && !minimized, "A minimized destination window was not restored")
        try check(destination.bottomIdentity.pid == pid && same(destination.bottomIdentity.element, window), "Animation and delivery use different window identities")
        let savedActions = actions
        try check(access.restore(destination) && actions == savedActions, "Unchanged destination was unnecessarily raised or selected")
        focus = doc1; selectedTab = tab1
        guard let browsing = access.capture(pid: pid, requireEditable: false) else { throw ServiceError.message("Return tab was lost when it had no focused editor") }
        try check(access.restore(destination) && access.restoreContext(browsing) && same(selectedTab, tab1), "Delivery did not restore a browsing tab without a focused editor")
        try check(access.restore(destination), "Failed to return to fixture destination")

        let board = NSPasteboard(name: .init("com.s2t.destination." + UUID().uuidString))
        let target = TextInsertion.Target(app: NSRunningApplication.current)
        target.promptDestination = destination; target.promptAccess = access
        target.recipientIsForeground = { true }
        target.pasteCommand = Task { app }
        var recipient: AXUIElement?, pastes = 0
        target.performPaste = { _ in
            recipient = focus; pastes += 1
            return .success
        }
        let outcome = try await TextInsertion.insert("Complete prompt", into: target, pasteboard: board, trusted: { true })
        try check(outcome == .textSent && pastes == 1 && recipient.map { same($0, finish) } == true, "Atomic prompt paste did not address the frozen field")
        focus = later
        let change = board.changeCount
        let refused = try await TextInsertion.insert("Must not paste", into: target, pasteboard: board, trusted: { true })
        try check(refused == .destinationUnavailable && pastes == 1 && board.changeCount == change, "Same-process field change redirected text or touched the clipboard")
        rejectedFocus = true
        try check(!access.restore(destination), "Ignored focus restoration was accepted")
        rejectedFocus = false; focus = finish; secure = true
        try check(access.capture(pid: pid) == nil && !access.restore(destination), "Secure field was accepted")
        secure = false; closed = true
        try check(!access.restore(destination), "Closed destination rebound to a new window")
        closed = false; focus = finish

        // Pages without a tab strip, such as Electron composers, stay pinned while focus moves elsewhere.
        hasTabs = false; focusedWindow = window
        guard let page = access.capture(pid: pid), page.tab == nil, page.document.map({ same($0, doc2) }) == true else {
            throw ServiceError.message("Tab-less page destination was not captured")
        }
        focus = otherField; focusedWindow = otherWindow
        try check(access.isVisible(page), "Another window of the same app hid the saved field")
        appFocusMissing = true
        try check(access.isVisible(page), "A background app without a focused element hid the saved field")
        appFocusMissing = false; focus = first; focusedWindow = window
        try check(!access.isVisible(page), "A different page in the saved window kept the old field visible")
        focus = finish; closed = true
        try check(!access.isVisible(page), "A closed page stayed visible")
        closed = false; minimized = true
        try check(!access.isVisible(page), "A minimized window stayed visible")
        minimized = false; hasTabs = true; focus = finish; selectedTab = tab2
        let image = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-destination-" + UUID().uuidString + ".png")
        try Data([1, 2, 3]).write(to: image)
        let ambiguous = try await PromptImageInsertion.insert([image], recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, nativePaste: { .cannotComplete },
            canPost: { true }, postPaste: { _ in false }, waitForPaste: {})
        try check(ambiguous.sentCount == 1 && ambiguous.confirmation == .unknown && !ambiguous.canReleaseClipboard,
            "An ambiguous native paste timeout discarded the pending image clipboard")
        let imageChange = board.changeCount
        var imagePastes = 0
        let skipped = try await PromptImageInsertion.insert([image], recipient: pid, board: board,
            observe: { _, _ in focus = later; return nil }, currentRecipient: { pid },
            destinationIsCurrent: { access.isCurrent(destination) }, canPost: { true },
            postPaste: { _ in imagePastes += 1; return true }, waitForPaste: {})
        try check(skipped.sentCount == 0 && imagePastes == 0 && board.changeCount == imageChange, "Same-app focus change during attachment preparation pasted into the new field")
        focus = finish
        fieldText = "New user edits"
        let preserved = caret
        try check(!access.restore(destination) && caret.location == preserved.location && caret.length == preserved.length,
            "New field contents were overwritten by stale selection restoration")
        try check(!access.isCurrent(destination, selection: true), "Changed text passed the final delivery guard")
        try check(readsFieldText, "Destination did not capture a content fingerprint")
        print("Prompt destination: Finish field, window/tab/minimized restoration, shared animation identity, one atomic paste, changed/closed/secure fields, tab-less pages pinned across other windows and attachment focus races PASS. Injected AX metadata/actions and isolated clipboard; no real fields or posted events.")
    }
}
