import AppKit
import ApplicationServices
import S2TCore

@MainActor enum InputUniversalProbe {
    static func run() throws {
        let pid: pid_t = 2_990_000
        let app = AXUIElementCreateApplication(pid)
        let elements = (0..<22).map { AXUIElementCreateApplication(pid + 1 + pid_t($0)) }
        // Window -> web root -> fourteen transparent wrappers -> two small
        // inputs. Neither input overlaps the discovery grid's sample points.
        let window = CGRect(x: -900, y: 80, width: 800, height: 600)
        let first = CGRect(x: -830, y: 261, width: 135, height: 22)
        let second = CGRect(x: -590, y: 261, width: 135, height: 22)
        var focused: Int? = 16
        var rootFocus = 1
        var focusReads = 0
        var changesFocus = false
        var secure = false
        var hitOnly = false
        var hidesWindowBounds = false
        var calls = 0
        var names = Set<String>()
        var contentBranchesRead = false
        var bundle = "test.universal.native"
        func rect(_ id: Int) -> CGRect {
            id == 16 ? first : id == 17 ? second : id == 18 ? CGRect(x: -800, y: 300, width: 1, height: 1) : window
        }
        func role(_ id: Int) -> String {
            id == 0 ? "AXWindow" : id == 1 ? "AXWebArea" : id >= 16 ? "AXTextField" : "AXGroup"
        }
        let reader = FocusedInputReader(attribute: { element, name in
            calls += 1; names.insert(name)
            if CFEqual(element, app) {
                if name == kAXFocusedWindowAttribute { return elements[0] }
                if name == kAXFocusedUIElementAttribute { return elements[rootFocus] }
                return nil
            }
            guard let id = elements.firstIndex(where: { CFEqual(element, $0) }) else { return nil }
            if id == 0 && hidesWindowBounds && [kAXPositionAttribute, kAXSizeAttribute].contains(name) { return nil }
            switch name {
            case kAXRoleAttribute: return role(id) as CFString
            case kAXSubroleAttribute: return (id == 16 && secure ? "AXSecureTextField" : "") as CFString
            case kAXParentAttribute: return id == 0 ? nil : elements[id >= 16 ? 15 : id - 1]
            case kAXFocusedAttribute:
                if id == focused {
                    focusReads += 1
                    return changesFocus && focusReads > 1 ? kCFBooleanFalse : kCFBooleanTrue
                }
                return kCFBooleanFalse
            case kAXPositionAttribute:
                var origin = rect(id).origin
                return AXValueCreate(.cgPoint, &origin)
            case kAXSizeAttribute:
                var size = rect(id).size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            calls += 1
            guard let id = elements.firstIndex(where: { CFEqual(element, $0) }) else { return nil }
            if id >= 16 { contentBranchesRead = true; return [] }
            if hitOnly { return [] }
            return id == 15 ? [elements[16], elements[17], elements[18]] : [elements[id + 1]]
        }, fallbackFocus: { _ in nil }, hitTest: { _, point in
            if point == CGPoint(x: second.midX, y: second.midY) { return elements[17] }
            if hitOnly { return point.x < window.midX ? elements[16] : elements[17] }
            return nil
        }, applicationBundleID: { _ in bundle }, enableAccessibility: { _ in })

        for identity in ["test.universal.native", "test.universal.browser", "test.universal.messenger"] {
            bundle = identity
            calls = 0
            try check(reader.read(pid: pid, anchor: CGPoint(x: second.midX, y: second.midY)) == first,
                "Deep focused field was missed or an old click overrode focus")
            try check(reader.usedPreset == nil && reader.targetKind == .input, "A detected field was diverted away from its outline")
            try check(calls < 900, "Discovery exceeded its metadata budget")
        }
        focused = 17
        try check(reader.read(pid: pid) == second, "Changed descendant focus retained the previous field")
        focused = nil
        try check(reader.read(pid: pid) == nil, "Two equal fields were guessed without focus or click evidence")
        try check(reader.read(pid: pid, anchor: CGPoint(x: second.midX, y: second.midY)) == second,
            "Recent click did not disambiguate fields")
        // Reset the cache by changing the anchor before exercising hit tests.
        hitOnly = true; focused = 16
        try check(reader.read(pid: pid, anchor: CGPoint(x: second.midX, y: second.midY + 1)) == first,
            "Hit-test discovery returned a clicked field before checking explicit focus")
        rootFocus = 16; changesFocus = true; focusReads = 0
        try check(reader.read(pid: pid) == nil, "Focus changed during geometry sampling but the target survived")
        changesFocus = false; secure = true
        try check(reader.read(pid: pid) == nil, "Secure focused input was accepted")
        secure = false; hidesWindowBounds = true
        try check(reader.read(pid: pid) == first, "Missing window geometry discarded an explicitly focused field with usable bounds")
        try check(!contentBranchesRead, "Discovery traversed editor contents")
        try check(names.isDisjoint(with: [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute]), "Discovery read content")
        print("PASS: identity-independent discovery finds small deeply wrapped inputs, ranks explicit focus above old clicks, rejects ambiguity, stale focus and secure fields, and skips editor contents. Synthetic AX metadata only.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "UniversalInput", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
