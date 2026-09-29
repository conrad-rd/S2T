import AppKit
import ApplicationServices
import S2TCore

@MainActor enum InputSearchProbe {
    static func run(url: URL) throws {
        struct Fixture: Decodable { let editor: Int; let expected: CGRect; let nodes: [ComposerNode] }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let pid: pid_t = 2_970_000
        let app = AXUIElementCreateApplication(pid), window = AXUIElementCreateApplication(pid + 1)
        let elements = Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, AXUIElementCreateApplication(pid + 100 + pid_t($0.id))) })
        let nodes = Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })
        var bundle = "com.apple.Safari", scale: CGFloat = 1
        var requested = Set<String>(), boundaryReads = 0, moves = false
        let reader = FocusedInputReader(attribute: { element, name in
            requested.insert(name)
            if CFEqual(element, app) {
                if name == kAXFocusedUIElementAttribute { return elements[fixture.editor] }
                if name == kAXFocusedWindowAttribute { return window }
                return nil
            }
            let isWindow = CFEqual(element, window)
            let node = elements.first(where: { CFEqual($0.value, element) }).flatMap { nodes[$0.key] }
            let bounds = (node?.frame ?? CGRect(x: 8, y: 47, width: 1784, height: 1114))
                .applying(CGAffineTransform(scaleX: scale, y: scale))
            switch name {
            case kAXRoleAttribute: return (isWindow ? "AXWindow" : node?.role ?? "") as CFString
            case kAXSubroleAttribute: return (node?.subrole ?? "") as CFString
            case kAXParentAttribute: return isWindow ? nil : node?.parent.flatMap { elements[$0] } ?? window
            case kAXPositionAttribute:
                var point = bounds.origin
                if node?.frame == fixture.expected {
                    boundaryReads += 1
                    if moves && boundaryReads > 1 { point.x += 8 }
                }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = bounds.size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            guard let node = elements.first(where: { CFEqual($0.value, element) }).flatMap({ nodes[$0.key] }) else { return [] }
            return node.childrenComplete ? node.children.compactMap { elements[$0] } : nil
        }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, applicationBundleID: { _ in bundle }, enableAccessibility: { _ in })
        for appID in ["com.apple.Safari", "test.unfamiliar-browser"] {
            bundle = appID
            for zoom in [CGFloat(0.75), 1, 1.5, 2] {
                scale = zoom
                let target = reader.read(pid: pid)
                try check(target == fixture.expected.applying(CGAffineTransform(scaleX: scale, y: scale)),
                    "Address container mismatch for \(appID): \(String(describing: target))")
                try check(reader.usedPreset == nil, "Address field bypassed the universal detector")
                try check(reader.targetKind == .input && abs(reader.cornerRadius - 26 * scale) < 0.001 && reader.cornerStyle == .circular, "Compact native row lost its anchored capsule outline")
            }
        }
        scale = 1; bundle = "com.apple.Safari"
        try check(reader.read(pid: pid, disabledPresets: [InputTargetPreset.safari.rawValue]) == fixture.expected,
            "Disabled Safari preset lost its automatic container")
        moves = true; boundaryReads = 0
        try check(reader.read(pid: pid) == nil, "Moved address container survived geometry validation")
        try check(requested.isDisjoint(with: [kAXValueAttribute, kAXTitleAttribute, kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute]),
            "Native search detection requested field content")
        print("PASS: measured native address field includes its button, rejects the wider toolbar, scales, validates movement and works with an unfamiliar app identity. No field text or screen capture.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "InputSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
