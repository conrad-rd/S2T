import AppKit

/// Menu discovery must never keep a completed dictation waiting on an unresponsive app.
/// All reads run off the main thread, have a shared deadline, and never open menus.
enum PasteCommandSearch {
    static let budget: TimeInterval = 0.3
    private static let lock = NSLock()
    private static var cached: [pid_t: (AXUIElement, TimeInterval)] = [:]

    static func find(pid: pid_t) -> AXUIElement? {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let saved = cached[pid]
        cached = cached.filter { now - $0.value.1 < 60 }
        lock.unlock()
        let deadline = now + budget
        func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0, !Task.isCancelled else { return nil }
            AXUIElementSetMessagingTimeout(element, Float(min(0.025, remaining)))
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        let result = search(root: AXUIElementCreateApplication(pid),
            cached: saved.flatMap { now - $0.1 < 60 ? $0.0 : nil }, deadline: deadline, read: read)
        // Discovery's short read timeout must not shorten the existing native Paste action timeout.
        if let result { AXUIElementSetMessagingTimeout(result, 0.2) }
        lock.lock()
        if let result {
            if cached.count >= 8 { cached.removeAll() }
            cached[pid] = (result, now)
        } else { cached.removeValue(forKey: pid) }
        lock.unlock()
        return result
    }

    static func search(root: AXUIElement, cached: AXUIElement? = nil, deadline: TimeInterval,
                       now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                       read: (AXUIElement, String) -> CFTypeRef?) -> AXUIElement? {
        func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            guard now() < deadline, !Task.isCancelled else { return nil }
            return read(node, name)
        }
        func isPaste(_ node: AXUIElement) -> Bool {
            (value(node, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "v"
                && (value(node, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0
        }
        if let cached, isPaste(cached) { return cached }
        guard let raw = value(root, kAXMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        var pending = [(raw as! AXUIElement, 0)]
        var visited = 0
        while let (item, depth) = pending.popLast(), visited < 250, now() < deadline, !Task.isCancelled {
            visited += 1
            if isPaste(item) { return item }
            if depth < 4, let children = value(item, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(100).reversed().map { ($0, depth + 1) })
            }
        }
        return nil
    }
}
