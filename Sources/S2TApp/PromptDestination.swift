import AppKit
import CryptoKit

struct PromptDestination {
    let pid: pid_t
    let window: AXUIElement
    let field: AXUIElement
    let document: AXUIElement?
    let tab: AXUIElement?
    let selection: CFRange?
    var contentFingerprint: Data? = nil
    var bottomIdentity: BottomWindowIdentity { .init(pid: pid, element: window) }
}

final class PromptDestinationAccess: @unchecked Sendable {
    static let system = PromptDestinationAccess()
    typealias Attribute = (AXUIElement, String) -> CFTypeRef?
    private let attribute: Attribute
    private let children: (AXUIElement) -> [AXUIElement]
    private let action: (AXUIElement, String) -> Bool
    private let write: (AXUIElement, String, CFTypeRef) -> Bool

    init(attribute: @escaping Attribute = PromptDestinationAccess.read,
         children: @escaping (AXUIElement) -> [AXUIElement] = PromptDestinationAccess.readChildren,
         action: @escaping (AXUIElement, String) -> Bool = { AXUIElementPerformAction($0, $1 as CFString) == .success },
         write: @escaping (AXUIElement, String, CFTypeRef) -> Bool = { AXUIElementSetAttributeValue($0, $1 as CFString, $2) == .success }) {
        self.attribute = attribute; self.children = children; self.action = action; self.write = write
    }

    func capture(pid: pid_t, requireEditable: Bool = true) -> PromptDestination? {
        let app = AXUIElementCreateApplication(pid)
        guard let field = element(app, kAXFocusedUIElementAttribute) ?? element(app, kAXFocusedWindowAttribute),
              !requireEditable || editable(field),
              let window = element(field, kAXWindowAttribute) ?? element(app, kAXFocusedWindowAttribute),
              attribute(window, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
        let document = document(of: field)
        let tab = selectedTab(in: window)
        let selection = editable(field) ? range(field) : nil
        let fingerprint = contentFingerprint(field)
        guard let latest = element(app, kAXFocusedUIElementAttribute) ?? element(app, kAXFocusedWindowAttribute), CFEqual(latest, field),
              let latestWindow = element(app, kAXFocusedWindowAttribute), CFEqual(latestWindow, window) else { return nil }
        return .init(pid: pid, window: window, field: field, document: document, tab: tab, selection: selection, contentFingerprint: fingerprint)
    }

    func isCurrent(_ destination: PromptDestination, selection: Bool = false) -> Bool {
        let app = AXUIElementCreateApplication(destination.pid)
        guard editable(destination.field),
              let window = element(app, kAXFocusedWindowAttribute), CFEqual(window, destination.window),
              let field = element(app, kAXFocusedUIElementAttribute), CFEqual(field, destination.field),
              same(document(of: field), destination.document),
              destination.tab.map(isSelected) ?? true else { return false }
        if selection, !contentIsUnchanged(destination) { return false }
        if selection, let expected = destination.selection {
            guard let actual = range(field), actual.location == expected.location, actual.length == expected.length else { return false }
        }
        return true
    }

    func isVisible(_ destination: PromptDestination) -> Bool {
        guard attribute(destination.window, kAXMinimizedAttribute) as? Bool != true,
              attribute(destination.window, kAXRoleAttribute) as? String == kAXWindowRole else { return false }
        if let tab = destination.tab { return isSelected(tab) }
        if let document = destination.document {
            // The saved field must still belong to its page. Focus moving to another window of the same app,
            // to another app, or to browser chrome leaves that field on screen, so the overlay stays there.
            guard same(self.document(of: destination.field), document) else { return false }
            let app = AXUIElementCreateApplication(destination.pid)
            // A different page focused inside the saved window means the saved page is no longer shown.
            if let field = element(app, kAXFocusedUIElementAttribute),
               let window = element(field, kAXWindowAttribute), CFEqual(window, destination.window),
               let shown = self.document(of: field), !CFEqual(shown, document) { return false }
        }
        return true
    }

    func isContextCurrent(_ destination: PromptDestination) -> Bool {
        let app = AXUIElementCreateApplication(destination.pid)
        return same(element(app, kAXFocusedWindowAttribute), destination.window) && (destination.tab.map(isSelected) ?? true)
    }

    func restoreContext(_ destination: PromptDestination) -> Bool {
        guard selectContext(destination) else { return false }
        return editable(destination.field) ? restore(destination) : isContextCurrent(destination)
    }

    func restore(_ destination: PromptDestination) -> Bool {
        guard contentIsUnchanged(destination) else { return false }
        let app = AXUIElementCreateApplication(destination.pid)
        guard selectContext(destination) else { return false }
        guard editable(destination.field), same(document(of: destination.field), destination.document) else { return false }
        if !same(element(app, kAXFocusedUIElementAttribute), destination.field) {
            guard write(destination.field, kAXFocusedAttribute, kCFBooleanTrue) else { return false }
        }
        guard contentIsUnchanged(destination) else { return false }
        if var selected = destination.selection {
            let current = range(destination.field)
            if current?.location != selected.location || current?.length != selected.length {
                guard let value = AXValueCreate(.cfRange, &selected), write(destination.field, kAXSelectedTextRangeAttribute, value) else { return false }
            }
        }
        return isCurrent(destination, selection: true)
    }

    private func contentFingerprint(_ field: AXUIElement) -> Data? {
        guard let text = attribute(field, kAXValueAttribute) as? String else { return nil }
        return Data(SHA256.hash(data: Data(text.utf8)))
    }

    private func contentIsUnchanged(_ destination: PromptDestination) -> Bool {
        guard let expected = destination.contentFingerprint else { return false }
        return contentFingerprint(destination.field) == expected
    }

    private func selectContext(_ destination: PromptDestination) -> Bool {
        let app = AXUIElementCreateApplication(destination.pid)
        guard attribute(destination.window, kAXRoleAttribute) as? String == kAXWindowRole else { return false }
        if attribute(destination.window, kAXMinimizedAttribute) as? Bool == true {
            guard write(destination.window, kAXMinimizedAttribute, kCFBooleanFalse) else { return false }
        }
        if !same(element(app, kAXFocusedWindowAttribute), destination.window) {
            guard action(destination.window, kAXRaiseAction) else { return false }
        }
        if let tab = destination.tab, !isSelected(tab) {
            guard action(tab, kAXPressAction) else { return false }
        }
        return true
    }

    private func editable(_ field: AXUIElement) -> Bool {
        guard attribute(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              let role = attribute(field, kAXRoleAttribute) as? String else { return false }
        if [kAXTextFieldRole, kAXTextAreaRole].contains(role) { return true }
        return role == kAXComboBoxRole && (attribute(field, "AXEditable") as? Bool == true || same(element(field, "AXEditableAncestor"), field))
    }

    private func document(of field: AXUIElement) -> AXUIElement? {
        var node = field
        for _ in 0..<20 {
            let role = attribute(node, kAXRoleAttribute) as? String
            if role == "AXWebArea" { return node }
            if role == kAXWindowRole { break }
            guard let parent = element(node, kAXParentAttribute), !CFEqual(parent, node) else { break }
            node = parent
        }
        return nil
    }

    private func selectedTab(in window: AXUIElement) -> AXUIElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        var pending = [(window, 0, false)], visited = 0
        while let (node, depth, inTabs) = pending.popLast(), visited < 160, ProcessInfo.processInfo.systemUptime < deadline {
            visited += 1
            let role = attribute(node, kAXRoleAttribute) as? String ?? ""
            if ["AXWebArea", kAXTextAreaRole, kAXTextFieldRole, kAXMenuBarRole].contains(role) { continue }
            if (inTabs && role == kAXRadioButtonRole || attribute(node, kAXSubroleAttribute) as? String == "AXTabButton"), isSelected(node) { return node }
            if depth < 8 { pending.append(contentsOf: children(node).reversed().map { ($0, depth + 1, role == kAXTabGroupRole) }) }
        }
        return nil
    }

    private func isSelected(_ tab: AXUIElement) -> Bool {
        (attribute(tab, kAXSelectedAttribute) as? Bool) ?? ((attribute(tab, kAXValueAttribute) as? NSNumber)?.intValue == 1)
    }

    private func range(_ field: AXUIElement) -> CFRange? {
        guard let raw = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetType(raw as! AXValue) == .cfRange, AXValueGetValue(raw as! AXValue, .cfRange, &range),
              range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= Int.max - range.length else { return nil }
        return range
    }

    private func same(_ a: AXUIElement?, _ b: AXUIElement?) -> Bool {
        switch (a, b) { case let (a?, b?): return CFEqual(a, b); case (nil, nil): return true; default: return false }
    }
    private func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return value as! AXUIElement
    }
    private static func read(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node, 0.05)
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success ? result : nil
    }
    private static func readChildren(_ node: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(node, 0.05)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count) == .success, count > 0, count <= 160 else { return [] }
        return read(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}

@MainActor final class PromptDeliveryLease {
    private let target: PromptDestination
    private let previous: PromptDestination?
    private let foreground: NSRunningApplication?
    private var restored = false
    private let interaction = DeliveryInteractionSnapshot()
    var savedForegroundPID: pid_t? { foreground?.processIdentifier }

    private init(target: PromptDestination, previous: PromptDestination?, foreground: NSRunningApplication?) {
        self.target = target; self.previous = previous; self.foreground = foreground
    }

    static func prepare(_ destination: PromptDestination) async throws -> PromptDeliveryLease? {
        let foreground = NSWorkspace.shared.frontmostApplication
        // The common case needs no menu/window traversal, activation or focus writes.
        if foreground?.processIdentifier == destination.pid {
            let current = await Task.detached { PromptDestinationAccess.system.isCurrent(destination, selection: true) }.value
            try Task.checkCancellation()
            if current, NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid {
                return PromptDeliveryLease(target: destination, previous: nil, foreground: nil)
            }
        }
        let previous = await Task.detached { PromptDestinationAccess.system.capture(pid: destination.pid, requireEditable: false) }.value
        try Task.checkCancellation()
        let lease = PromptDeliveryLease(target: destination, previous: previous, foreground: foreground)
        guard let app = NSRunningApplication(processIdentifier: destination.pid), !app.isTerminated else { return nil }
        if foreground?.processIdentifier != destination.pid {
            NSApp.yieldActivation(to: app)
            app.activate(options: [])
            for _ in 0..<20 {
                try Task.checkCancellation()
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid { break }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid else { lease.restore(); return nil }
        do {
            for _ in 0..<4 {
                try Task.checkCancellation()
                guard lease.interaction.isUnchanged,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.pid else { lease.restore(); return nil }
                let interaction = lease.interaction
                let restored = await Task.detached {
                    guard interaction.isUnchanged else { return false }
                    return PromptDestinationAccess.system.restore(destination)
                }.value
                try await Task.sleep(nanoseconds: 50_000_000)
                let stable = await Task.detached { PromptDestinationAccess.system.isCurrent(destination, selection: true) }.value
                if restored && stable && lease.interaction.isUnchanged { return lease }
            }
        } catch { lease.restore(); throw error }
        lease.restore()
        return nil
    }

    @discardableResult func restore() -> Task<Void, Never>? {
        guard !restored else { return nil }
        restored = true
        guard previous != nil || foreground != nil else { return nil }
        let target = target, previous = previous, foreground = foreground
        return Task { @MainActor in
            guard interaction.isUnchanged else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return }
            let current = await Task.detached { PromptDestinationAccess.system.isCurrent(target) }.value
            guard current, interaction.isUnchanged,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return }
            if let previous, !CFEqual(previous.field, target.field) {
                _ = await Task.detached { [interaction] in
                    guard interaction.isUnchanged else { return false }
                    return PromptDestinationAccess.system.restoreContext(previous)
                }.value
            }
            if let foreground, !foreground.isTerminated, foreground.processIdentifier != target.pid,
               interaction.isUnchanged, NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid {
                if foreground.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                    NSApp.activate(ignoringOtherApps: true)
                } else { foreground.activate(options: []) }
            }
        }
    }
}

/// Physical event counts only: never reads keys, text, pointer coordinates or screen pixels.
struct DeliveryInteractionSnapshot: @unchecked Sendable {
    private static let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    private let read: (CGEventType) -> UInt32
    private let counts: [UInt32]
    init(read: @escaping (CGEventType) -> UInt32 = { CGEventSource.counterForEventType(.hidSystemState, eventType: $0) }) {
        self.read = read
        counts = Self.types.map(read)
    }
    var isUnchanged: Bool { Self.types.map(read) == counts }
}
