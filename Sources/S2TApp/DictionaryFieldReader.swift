import AppKit
import ApplicationServices

/// Bounded text access is confined to the intended receiving editor.
final class DictionaryFieldReader {
    let root: AXUIElement
    private let attribute: (AXUIElement, String) -> CFTypeRef?
    private let children: (AXUIElement) -> [AXUIElement]
    private let rangeText: (AXUIElement, Int) -> String?
    private let fallbackFocus: () -> AXUIElement?

    init(pid: pid_t,
         attribute: @escaping (AXUIElement, String) -> CFTypeRef? = DictionaryFieldReader.systemAttribute,
         children: @escaping (AXUIElement) -> [AXUIElement] = DictionaryFieldReader.systemChildren,
         rangeText: @escaping (AXUIElement, Int) -> String? = DictionaryFieldReader.systemRangeText,
         fallbackFocus: (() -> AXUIElement?)? = nil) {
        root = AXUIElementCreateApplication(pid)
        self.attribute = attribute
        self.children = children
        self.rangeText = rangeText
        self.fallbackFocus = fallbackFocus ?? { FocusedInputReader.systemFocus(pid: pid) }
    }

    func prepare() {
        AXUIElementSetMessagingTimeout(root, 0.1)
        FocusedInputReader.enableApplicationAccessibility(root)
    }

    func focused() -> AXUIElement? {
        guard let focus = element(attribute(root, kAXFocusedUIElementAttribute)) ?? fallbackFocus() else { return nil }
        return editor(near: focus)
    }

    func editor(near focus: AXUIElement) -> AXUIElement? {
        var ancestor: AXUIElement? = focus
        var ancestry: [AXUIElement] = []
        for _ in 0..<8 {
            guard let node = ancestor else { break }
            if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
            ancestry.append(node)
            ancestor = element(attribute(node, kAXParentAttribute))
        }
        if eligible(focus) { return focus }
        let focusRole = attribute(focus, kAXRoleAttribute) as? String
        if [kAXStaticTextRole, kAXGroupRole].contains(focusRole ?? ""),
           let editor = ancestry.dropFirst().first(where: eligible) {
            return editor
        }
        let containers = [kAXGroupRole, kAXScrollAreaRole, kAXComboBoxRole]
        guard let focusRole, containers.contains(focusRole) else { return nil }
        var pending = [(focus, 0)]
        var candidates: [AXUIElement] = []
        var visited = 0
        while let (node, depth) = pending.popLast(), visited < 24 {
            visited += 1
            if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { continue }
            if eligible(node) { candidates.append(node); continue }
            if let role = attribute(node, kAXRoleAttribute) as? String, containers.contains(role) {
                let descendants = children(node)
                guard descendants.count <= 24, depth < 3 || descendants.isEmpty else { return nil }
                pending.append(contentsOf: descendants.map { ($0, depth + 1) })
            }
        }
        return pending.isEmpty && candidates.count == 1 ? candidates[0] : nil
    }

    private func eligible(_ field: AXUIElement) -> Bool {
        guard attribute(field, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole,
              attribute(field, kAXEnabledAttribute) as? Bool != false,
              let role = attribute(field, kAXRoleAttribute) as? String else { return false }
        if [kAXTextFieldRole, kAXTextAreaRole].contains(role) { return true }
        return [kAXComboBoxRole, kAXGroupRole].contains(role) && attribute(field, "AXEditable") as? Bool == true
    }

    func read(_ field: AXUIElement) -> String? {
        guard attribute(field, kAXEnabledAttribute) as? Bool != false else { return nil }
        return Self.readText(attribute: { attribute(field, $0) }, rangeText: { rangeText(field, $0) })
    }

    func sample(_ field: AXUIElement) -> String? {
        guard stillFocused(field), let text = read(field), stillFocused(field) else { return nil }
        return text
    }

    private func stillFocused(_ field: AXUIElement) -> Bool {
        guard let focus = element(attribute(root, kAXFocusedUIElementAttribute)) ?? fallbackFocus() else { return false }
        // The attached editor was already checked through its ancestors. Read its live
        // security attributes in read(), without traversing those ancestors every frame.
        if CFEqual(focus, field) { return true }
        return editor(near: focus).map { CFEqual($0, field) } ?? false
    }

    static func readText(attribute: (String) -> CFTypeRef?, rangeText: (Int) -> String? = { _ in nil }) -> String? {
        guard let role = attribute(kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole].contains(role)
                || ([kAXComboBoxRole, kAXGroupRole].contains(role) && attribute("AXEditable") as? Bool == true),
              attribute(kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        let count = attribute(kAXNumberOfCharactersAttribute) as? Int
        if let count, !(0...16_384).contains(count) { return nil }
        let raw = attribute(kAXValueAttribute)
        let rawValue = raw as? String ?? (raw as? NSAttributedString)?.string
        let value = rawValue?.isEmpty == false ? rawValue : count.flatMap { $0 > 0 ? rangeText($0) : nil } ?? rawValue
        guard let value, value.utf8.count <= 16_384 else { return nil }
        return value
    }

    func selection(_ field: AXUIElement) -> NSRange? {
        guard let value = attribute(field, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    func bounds(_ field: AXUIElement, range: NSRange) -> CGRect? {
        var axRange = CFRange(location: range.location, length: range.length)
        if let parameter = AXValueCreate(.cfRange, &axRange) {
            var value: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(field, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 { return rect }
            }
        }
        guard let position = attribute(field, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = attribute(field, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func systemAttribute(_ field: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(field, 0.075)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func systemChildren(_ field: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(field, 0.075)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(field, kAXChildrenAttribute as CFString, &count) == .success, count > 0, count <= 24 else { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(field, kAXChildrenAttribute as CFString, 0, count, &values) == .success else { return [] }
        return values as? [AXUIElement] ?? []
    }

    static func systemRangeText(_ field: AXUIElement, _ count: Int) -> String? {
        AXUIElementSetMessagingTimeout(field, 0.075)
        var range = CFRange(location: 0, length: count)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success else { return nil }
        return value as? String
    }
}
