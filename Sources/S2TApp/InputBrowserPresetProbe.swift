import AppKit
import ApplicationServices
import S2TCore

@MainActor enum InputBrowserPresetProbe {
    private struct Fixture: Decodable {
        struct Node: Decodable {
            let id: Int
            let role, subrole: String
            let editable, childrenComplete: Bool
            let frame: CGRect?
            let parent: Int?
            let children: [Int]
            let classes: [String]
        }
        let preset: String?
        let editor: Int
        let expected, main, bar: CGRect
        let nodes: [Node]
    }

    static func run(url: URL) throws {
        try verifyAccessibilityActivation()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let expectedPreset = fixture.preset.flatMap(InputTargetPreset.init(rawValue:)) ?? .t3Code
        let pid: pid_t = 2_820_000
        let app = AXUIElementCreateApplication(pid), window = AXUIElementCreateApplication(pid + 1)
        let web = AXUIElementCreateApplication(pid + 2)
        let elements = Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, AXUIElementCreateApplication(pid + 100 + pid_t($0.id))) })
        let nodes = Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })
        var bundle = "net.imput.helium", origin = "http://localhost:49531/"
        var markers = true, removeMarker = false, changeOrigin = false
        var markerReads = 0, originReads = 0
        let attachmentIDs = Set(fixture.nodes.filter { node in
            guard let frame = node.frame else { return false }
            return frame.minX == fixture.expected.minX + fixture.bar.minX && frame.width == fixture.bar.width
                && frame.minY == fixture.expected.minY + fixture.bar.minY
        }.map(\.id))
        var moveAttachment = false, removeAttachment = false
        var attachmentReads = [Int: Int]()
        var scale: CGFloat = 1
        var requests = Set<String>()
        var accessibilityReady = expectedPreset != .codex
        var activationScheduled = false
        var activationRequests = [String]()
        let reader = FocusedInputReader(attribute: { element, name in
            requests.insert(name)
            if CFEqual(element, app) {
                if name == kAXFocusedWindowAttribute { return window }
                if name == kAXFocusedUIElementAttribute { return accessibilityReady ? elements[fixture.editor] : nil }
                return nil
            }
            let isWindow = CFEqual(element, window), isWeb = CFEqual(element, web)
            let id = elements.first(where: { CFEqual($0.value, element) })?.key
            let node = id.flatMap { nodes[$0] }
            switch name {
            case kAXRoleAttribute: return (isWindow ? "AXWindow" : isWeb ? "AXWebArea" : node?.role ?? "") as CFString
            case kAXSubroleAttribute: return (node?.subrole ?? "") as CFString
            case kAXParentAttribute:
                if isWeb { return window }
                return node.flatMap { $0.parent.flatMap { elements[$0] } ?? web }
            case "AXURL":
                guard isWeb else { return nil }
                originReads += 1
                return (changeOrigin && originReads > 1 ? "http://localhost:49532/" : origin) as CFString
            case "AXDOMClassList":
                guard let node else { return [] as CFArray }
                if !node.classes.isEmpty { markerReads += 1 }
                return (markers && !(removeMarker && markerReads > 1) ? node.classes : []) as CFArray
            case "AXEditable": return (node?.editable ?? false) ? kCFBooleanTrue : kCFBooleanFalse
            case kAXPositionAttribute:
                var point = node?.frame?.applying(CGAffineTransform(scaleX: scale, y: scale)).origin ?? .zero
                if let id, attachmentIDs.contains(id) {
                    attachmentReads[id, default: 0] += 1
                    if moveAttachment && attachmentReads[id, default: 0] > 1 { point.x += 5 }
                }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = node?.frame?.applying(CGAffineTransform(scaleX: scale, y: scale)).size ?? CGSize(width: 4000, height: 3000)
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            // Cold Chromium exposes neither the focused editor nor its web
            // descendants until accessibility activation completes.
            guard accessibilityReady else { return [] }
            if CFEqual(element, window) { return [web] }
            if CFEqual(element, web) { return fixture.nodes.filter { $0.parent == nil }.compactMap { elements[$0.id] } }
            guard let id = elements.first(where: { CFEqual($0.value, element) })?.key, let node = nodes[id] else { return [] }
            return node.childrenComplete ? node.children.filter { !removeAttachment || !attachmentIDs.contains($0) }.compactMap { elements[$0] } : nil
        }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, applicationBundleID: { _ in bundle },
        caretBounds: { _ in nil }, enableAccessibility: { app in
            guard expectedPreset == .codex else { return }
            FocusedInputReader.enableApplicationAccessibility(app, setAttribute: { _, name, value in
                activationRequests.append(name)
                guard value as? Bool == true else { return .illegalArgument }
                if name == "AXEnhancedUserInterface" {
                    activationScheduled = true
                    // Chromium schedules activation, then returns AppKit's error.
                    return .notImplemented
                }
                return .attributeUnsupported
            })
        })
        let routes = expectedPreset == .codex ? [("com.openai.codex", "file:///local-ui")] : [("net.imput.helium", "http://localhost:49531/"),
            ("com.google.Chrome", "http://127.0.0.1:6333/"), ("com.apple.Safari", "https://development.example.test/") ,
            ("com.t3tools.t3code", "file:///local-ui")]
        if expectedPreset == .codex {
            bundle = "com.openai.codex"; origin = "file:///local-ui"
            reader.prepareAccessibility(pid: pid)
            reader.prepareAccessibility(pid: pid)
            try check(requests.isEmpty, "Accessibility warm-up inspected a field before targeting")
            try check(reader.read(pid: pid) == nil, "Unexposed Codex editor produced guessed geometry")
            try check(activationScheduled, "Cold Codex did not request Chromium accessibility")
            accessibilityReady = true
        }
        for (browser, address) in routes {
            bundle = browser; origin = address; markers = expectedPreset == .t3Code && browser != "com.t3tools.t3code"
            for zoom in [CGFloat(0.75), 1, 1.5] {
                scale = zoom
                let transform = CGAffineTransform(scaleX: zoom, y: zoom)
                let result = reader.read(pid: pid)
                try check(result == fixture.expected.applying(transform) && reader.usedPreset == expectedPreset,
                    "Recorded composer missed its preset in \(browser): \(String(describing: result)), preset \(String(describing: reader.usedPreset)), contour \(String(describing: reader.contour))")
                try check(reader.contour?.main.rect == fixture.main.applying(transform)
                    && reader.contour?.bars.first?.rect == fixture.bar.applying(transform), "Recorded attachment became its surrounding wrapper")
            }
        }
        scale = 1
        bundle = "test.unfamiliar-editor"; origin = "https://unfamiliar.example.test/"; markers = false
        for zoom in [CGFloat(0.75), 1, 1.5] {
            scale = zoom
            let transform = CGAffineTransform(scaleX: zoom, y: zoom)
            try check(reader.read(pid: pid) == fixture.expected.applying(transform) && reader.usedPreset == nil,
                "Automatic detection failed without application or site identity")
            try check(reader.contour?.main.rect == fixture.main.applying(transform)
                && reader.contour?.bars.first?.rect == fixture.bar.applying(transform),
                "Automatic detection flattened the recorded attachment")
        }
        scale = 1
        moveAttachment = true; attachmentReads = [:]
        try check(reader.read(pid: pid) == nil, "Automatic attachment moved during sampling but survived validation")
        moveAttachment = false; removeAttachment = true
        try check(reader.read(pid: pid) == fixture.main.offsetBy(dx: fixture.expected.minX, dy: fixture.expected.minY)
            && reader.contour?.bars.isEmpty == true, "Automatic detection retained a removed attachment")
        removeAttachment = false
        print("PASS: automatic detection resolves the complete recorded contour without app names, site identity or CSS markers, and rejects stale attachments.")
        if expectedPreset == .codex {
            bundle = "com.openai.codex"; origin = "file:///local-ui"
            try check(activationRequests == ["AXManualAccessibility", "AXEnhancedUserInterface"],
                "Cold Codex activation was missing or repeated while sampling")
            scale = 1
            moveAttachment = true; attachmentReads = [:]
            try check(reader.read(pid: pid) == nil, "Codex header moved during sampling but survived validation")
            moveAttachment = false; removeAttachment = true
            let plain = reader.read(pid: pid)
            try check(plain == fixture.main.offsetBy(dx: fixture.expected.minX, dy: fixture.expected.minY)
                && reader.contour?.bars.isEmpty == true, "Removed Codex header survived the next read")
            removeAttachment = false
            _ = reader.read(pid: pid, disabledPresets: [InputTargetPreset.codex.rawValue])
            try check(reader.usedPreset == nil && reader.contour?.bars.first?.rect == fixture.bar, "Disabled Codex preset did not use automatic geometry")
            try check(requests.isDisjoint(with: [kAXValueAttribute, kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXTitleAttribute]), "Codex targeting read content")
            print("PASS: cold Codex activates its delayed Chromium tree once, then resolves its extended header, wide layout shell and transparent wrappers at three scales. Moved/removed headers and disabled presets remain validated. Geometry only, no field text or screen capture.")
            return
        }
        scale = 1; bundle = "net.imput.helium"; origin = "http://localhost:49531/"; markers = true
        _ = reader.read(pid: pid, disabledPresets: [InputTargetPreset.t3Code.rawValue])
        try check(reader.usedPreset == nil && reader.contour?.bars.first?.rect == fixture.bar, "Browser preset did not fall back to automatic geometry")
        markers = false
        _ = reader.read(pid: pid)
        try check(reader.usedPreset == nil, "An unrelated localhost page inherited the T3 preset")
        markers = true; removeMarker = true; markerReads = 0
        try check(reader.read(pid: pid) == nil, "Removed composer identity retained stale T3 geometry")
        removeMarker = false; changeOrigin = true; originReads = 0
        try check(reader.read(pid: pid) == nil, "Changing localhost ports retained stale T3 geometry")
        try check(requests.isDisjoint(with: [kAXValueAttribute, kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXTitleAttribute]),
            "Browser preset inspected field text or window titles")
        print("PASS: recorded live T3 hierarchy resolves its inset bar in Helium, Chrome, Safari and desktop at three scales; no fixed port, outer-wrapper rectangle or field-content reads.")
        print("PASS: disabled presets, unrelated localhost pages, disappearing markers and changing origins reject stale browser identities.")
    }

    private static func verifyAccessibilityActivation() throws {
        let app = AXUIElementCreateApplication(2_819_999)
        for result in [AXError.success, .attributeUnsupported, .notImplemented, .cannotComplete, .apiDisabled] {
            var writes = [String]()
            FocusedInputReader.enableApplicationAccessibility(app, setAttribute: { node, name, value in
                guard CFEqual(node, app), value as? Bool == true else { return .illegalArgument }
                writes.append(name)
                return name == "AXManualAccessibility" ? result : .notImplemented
            })
            let expected = result == .attributeUnsupported || result == .notImplemented
                ? ["AXManualAccessibility", "AXEnhancedUserInterface"] : ["AXManualAccessibility"]
            try check(writes == expected, "Accessibility activation changed a supported Electron request or ignored Chromium")
        }
    }

    private static func check(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "InputBrowserPreset", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
