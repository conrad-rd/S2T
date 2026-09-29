import AppKit

struct PromptAttachmentSnapshot: Sendable {
    let field: CFHashCode
    let names: Set<String>
    let images: Int
    let busy: Bool
}

enum PromptAttachmentVerifier {
    static func snapshot(pid: pid_t, names: [String]) async -> PromptAttachmentSnapshot? {
        await Task.detached(priority: .utility) { read(pid: pid, names: names) }.value
    }

    private static func read(pid: pid_t, names: [String]) -> PromptAttachmentSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.18
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        func value(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
            guard !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(node, 0.025)
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
            return result
        }
        func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
            guard let result = value(node, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
            return (result as! AXUIElement)
        }
        func frame(_ node: AXUIElement) -> CGRect? {
            guard let position = value(node, kAXPositionAttribute), let size = value(node, kAXSizeAttribute),
                  CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var point = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
            return CGRect(origin: point, size: dimensions)
        }
        guard let field = element(app, kAXFocusedUIElementAttribute),
              let role = value(field, kAXRoleAttribute) as? String,
              ["AXTextArea", "AXTextField", "AXComboBox"].contains(role),
              (value(field, kAXSubroleAttribute) as? String) != "AXSecureTextField",
              let editor = frame(field), editor.width > 0, editor.height > 0 else { return nil }
        var root = field
        for _ in 0..<4 {
            guard let parent = element(root, kAXParentAttribute), let bounds = frame(parent),
                  let role = value(parent, kAXRoleAttribute) as? String,
                  ["AXGroup", "AXScrollArea", "AXLayoutArea"].contains(role),
                  bounds.contains(editor), bounds.height <= max(280, editor.height * 3),
                  bounds.width <= max(600, editor.width * 1.5) else { break }
            root = parent
        }
        guard !CFEqual(root, field) else { return nil }
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0, imageCount = 0, found = Set<String>(), busy = false
        while let (node, depth) = pending.popLast() {
            guard visited < 160, ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled else { return nil }
            visited += 1
            let role = value(node, kAXRoleAttribute) as? String ?? ""
            if (value(node, kAXSubroleAttribute) as? String) == "AXSecureTextField" { continue }
            if !CFEqual(node, field), ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) { continue }
            if ["AXProgressIndicator", "AXBusyIndicator"].contains(role) { busy = true }
            if ["AXImage", "AXAttachment", "AXButton"].contains(role) {
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    if let text = value(node, attribute) as? String {
                        for name in names where text.contains(name) { found.insert(name) }
                    }
                }
                if role == "AXAttachment" || (role == "AXImage" && frame(node).map({ $0.width >= 32 && $0.height >= 24 }) == true) { imageCount += 1 }
            }
            var count: CFIndex = 0
            let status = AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count)
            if status == .attributeUnsupported { continue }
            guard status == .success, count <= 160 else { return nil }
            if count == 0 { continue }
            guard depth < 7, let children = value(node, kAXChildrenAttribute) as? [AXUIElement], children.count == count else { return nil }
            pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
        guard let current = element(app, kAXFocusedUIElementAttribute), CFEqual(current, field) else { return nil }
        return PromptAttachmentSnapshot(field: CFHash(field), names: found, images: imageCount, busy: busy)
    }
}
