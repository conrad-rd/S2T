import AppKit
import ApplicationServices
import SwiftUI
import S2TCore

@MainActor enum InputPresetProbe {
    static func run() throws {
        try verifyReader()
        try verifyTerminal()
        try verifySettings()
        try verifyExactEdges()
        print("PASS: app/site preset routing, automatic fallback, disabled presets, URL/focus/geometry changes, content-read exclusion, terminal cursor geometry and settings persistence.")
        print("Uses injected Accessibility objects and isolated preferences. Live app/site compatibility is not verified.")
    }

    private static func verifyExactEdges() throws {
        let state = AppState(preview: true)
        state.phase = .recording
        state.glowStrength = 1.3
        for (name, field, radius) in [
            ("chatgpt", CGRect(x: 100.25, y: 200.75, width: 634.5, height: 57.25), CGFloat(28.625)),
            ("claude", CGRect(x: 100.25, y: 200.75, width: 502.5, height: 90), CGFloat(20))
        ] {
            let controller = InputOutlineWindowController(state: state)
            let panel = controller.prepare(field: field, cornerRadius: radius, cornerStyle: .circular)
            defer { panel.orderOut(nil) }
            guard let root = panel.contentView as? ProgressiveBackdropView,
                  let actual = root.profile?.inputOutline,
                  let host = root.subviews.first as? NSHostingView<InputOutline> else { throw failure("Missing live preset renderer") }
            let rect = actual.rect
            try check(panel.frame.minX + rect.minX == field.minX && panel.frame.minX + rect.maxX == field.maxX
                && panel.frame.maxY - rect.minY == field.maxY && panel.frame.maxY - rect.maxY == field.minY,
                "Live preset renderer added a margin")
            try check(actual.cornerRadius == radius && actual.cornerStyle == .circular
                && host.rootView.layout.outlineRect == rect && host.rootView.layout.cornerStyle == .circular,
                "Color and native blur disagree on the preset contour")
            try check(!panel.isVisible && panel.ignoresMouseEvents && !panel.canBecomeKey, "Preset check showed or activated a panel")
            let boundary = ChromaInputBoundary(rect: rect, radius: radius, cornerStyle: .circular)
            guard let map = actual.mask(size: panel.frame.size),
                  let bitmap = map.representations.first as? NSBitmapImageRep else { throw failure("Missing preset native map") }
            for angle in [Double.pi / 6, .pi / 4, .pi / 3] {
                for offset in [-1.5, 1.5] {
                    let point = CGPoint(x: rect.maxX - radius + (radius + offset) * cos(angle),
                                        y: rect.minY + radius - (radius + offset) * sin(angle))
                    try check(abs(boundary.distance(point) - offset) < 0.03, "Preset corner differs from its circular blueprint")
                    let x = Int(point.x / panel.frame.width * CGFloat(bitmap.pixelsWide))
                    let y = Int(point.y / panel.frame.height * CGFloat(bitmap.pixelsHigh))
                    let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1
                    try check(offset > 0 ? alpha > 0 : alpha == 0, "Native blur left a gap or entered the rounded field")
                }
            }
            for point in [CGPoint(x: rect.midX, y: rect.minY - 0.75), CGPoint(x: rect.midX, y: rect.maxY + 0.75),
                          CGPoint(x: rect.minX - 0.75, y: rect.midY), CGPoint(x: rect.maxX + 0.75, y: rect.midY)] {
                let x = Int(point.x / panel.frame.width * CGFloat(bitmap.pixelsWide))
                let y = Int(point.y / panel.frame.height * CGFloat(bitmap.pixelsHigh))
                try check((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0, "Native blur does not touch a straight field edge")
            }
            try check(controller.prepare(field: field, cornerRadius: radius, cornerStyle: .continuous) === panel
                && root.profile?.inputOutline?.cornerStyle == .continuous, "Preset change retained a cached circular contour")
            try check(controller.prepare(field: field, cornerRadius: radius, cornerStyle: .circular) === panel
                && root.profile?.inputOutline?.cornerStyle == .circular, "Preset change did not restore its circular contour")
            let sampleRect = CGRect(x: 100, y: 100, width: field.width, height: field.height)
            let sample = InputOutlineLayout()
            sample.outlineRect = sampleRect; sample.cornerRadius = radius; sample.cornerStyle = .circular
            let view = InputOutline(state: state, layout: sample, reduceMotionOverride: true,
                levelProvider: { 0.55 }, spectrumProvider: { [] }, timeOverride: 1, reduceTransparencyOverride: true)
            let size = CGSize(width: field.width + 200, height: field.height + 200)
            try GlowFixture.write(ZStack {
                InputOutlineBackdrop(rect: sampleRect, cornerRadius: radius, cornerStyle: .circular).path.fill(Color(white: 0.13))
                view
            }, size: size, name: "flush-" + name)
        }
        print("PASS: ChatGPT capsule and Claude circular corners match live hidden color/native geometry with zero exterior margin; generated blur touches all edges and excludes field interiors.")
    }

    private static func verifyReader() throws {
        let app = AXUIElementCreateApplication(2_600_000)
        let elements = (1...7).map { AXUIElementCreateApplication(pid_t(2_600_000 + $0)) }
        let editor = CGRect(x: 150, y: 420, width: 400, height: 30)
        let boundary = CGRect(x: 100, y: 400, width: 500, height: 70)
        let frames = [CGRect(x: 0, y: 0, width: 1200, height: 900), editor, boundary,
                      CGRect(x: 560, y: 420, width: 28, height: 28), CGRect(x: 0, y: 80, width: 1200, height: 800),
                      CGRect(x: 800, y: 100, width: 120, height: 30), CGRect(x: 20, y: 10, width: 1160, height: 60)]
        var bundle = "com.apple.Safari", host = "https://chatgpt.com/", secure = false
        var urlReads = 0, switchSite = false, switchFocus = false, moveEditor = false
        var positionReads = 0, focusReads = 0, automaticCalls = 0, primaryFocus = 1
        var requested = [String]()
        let reader = FocusedInputReader(attribute: { element, name in
            requested.append(name)
            if CFEqual(element, app) {
                if name == kAXFocusedWindowAttribute { return elements[0] }
                if name == kAXFocusedUIElementAttribute {
                    focusReads += 1
                    return switchFocus && focusReads > 1 ? elements[5] : elements[primaryFocus]
                }
                return nil
            }
            guard let id = elements.firstIndex(where: { CFEqual($0, element) }) else { return nil }
            switch name {
            case kAXRoleAttribute: return ["AXWindow", "AXTextArea", "AXGroup", "AXButton", "AXWebArea", "AXTextField", "AXToolbar"][id] as CFString
            case kAXSubroleAttribute: return (id == 1 && secure ? "AXSecureTextField" : "") as CFString
            case kAXParentAttribute:
                let parents = [nil, 2, 4, 2, 0, 6, 0] as [Int?]
                return parents[id].map { elements[$0] }
            case "AXURL":
                guard id == 4 else { return nil }
                urlReads += 1
                return (switchSite && urlReads > 1 ? "https://gemini.google.com/" : host) as CFString
            case kAXPositionAttribute:
                var point = frames[id].origin
                if id == 1 { positionReads += 1; if moveEditor && positionReads > 1 { point.x += 20 } }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = frames[id].size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in
            guard let id = elements.firstIndex(where: { CFEqual($0, element) }) else { return [] }
            return (id == 2 ? [1, 3] : []).map { elements[$0] }
        }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, applicationBundleID: { _ in bundle },
        caretBounds: { _ in nil }, automaticResolver: { editor, nodes, style in
            automaticCalls += 1
            return ComposerTargeting.resolveTarget(editor: editor, nodes: nodes, cornerStyle: style)
        }, enableAccessibility: { _ in })
        for (url, expected) in [("https://chatgpt.com/", InputTargetPreset.chatGPT), ("https://gemini.google.com/", .gemini),
                                ("https://claude.ai/", .claude), ("https://discord.com/", .discord),
                                ("https://web.whatsapp.com/", .whatsApp), ("https://web.telegram.org/", .telegram),
                                ("https://www.google.com/", .google)] {
            host = url; automaticCalls = 0
            try check(reader.read(pid: 2_600_000) == boundary && reader.usedPreset == expected && automaticCalls > 0,
                      "Website \(expected.title) failed to use the shared boundary with its matching corner calibration")
            try check(reader.cornerStyle == .circular, "Website preset lost its circular corner style")
            if expected == .claude { try check(reader.cornerRadius == 20, "Claude field corners no longer match its blueprint") }
        }
        for (identifier, expected) in [("com.apple.MobileSMS", InputTargetPreset.messages), ("com.t3tools.t3code", .t3Code), ("com.openai.codex", .codex)] {
            bundle = identifier; host = "file:///local-ui"; automaticCalls = 0
            try check(reader.read(pid: 2_600_000) == boundary && reader.usedPreset == expected && automaticCalls > 0,
                      "Native \(expected.title) bypassed shared detection or lost its matching corner calibration")
        }
        bundle = "com.apple.Safari"; host = "https://chatgpt.com/"; automaticCalls = 0
        try check(reader.read(pid: 2_600_000, disabledPresets: ["chatGPT"]) != nil && reader.usedPreset == nil && automaticCalls > 0,
                  "Turning off a preset did not restore automatic detection")
        host = "https://x.com/"; automaticCalls = 0
        try check(reader.read(pid: 2_600_000) == boundary && reader.usedPreset == nil && automaticCalls > 0,
            "An editor-only preset overrode the complete measured composer")
        primaryFocus = 5; automaticCalls = 0
        try check(reader.read(pid: 2_600_000) == frames[5] && reader.usedPreset == nil && automaticCalls > 0,
            "Native address field bypassed the shared detector")
        primaryFocus = 1
        host = "https://unrelated.test/"
        try check(reader.read(pid: 2_600_000) != nil && reader.usedPreset == nil, "Safari overrode an unrelated website")
        try check(reader.cornerStyle == .circular, "Automatic web input inherited native continuous corners")
        host = "https://chatgpt.com/"; secure = true
        try check(reader.read(pid: 2_600_000) == nil, "Preset accepted a secure field")
        secure = false; switchSite = true; urlReads = 0
        try check(reader.read(pid: 2_600_000) == nil, "Changed site retained the previous preset target")
        switchSite = false; switchFocus = true; focusReads = 0
        try check(reader.read(pid: 2_600_000) == nil, "Changed focus retained a preset target")
        switchFocus = false; moveEditor = true; positionReads = 0
        try check(reader.read(pid: 2_600_000) == nil, "Moving field retained stale preset geometry")
        try check(!requested.contains(kAXValueAttribute) && !requested.contains(kAXSelectedTextAttribute)
            && !requested.contains(kAXSelectedTextRangeAttribute) && !requested.contains(kAXTitleAttribute), "Preset read user text or window titles")
    }

    private static func verifyTerminal() throws {
        let app = AXUIElementCreateApplication(2_700_000), window = AXUIElementCreateApplication(2_700_001)
        let editor = AXUIElementCreateApplication(2_700_002)
        var caret: CGRect? = CGRect(x: 200, y: 600, width: 0, height: 20)
        let reader = FocusedInputReader(attribute: { element, name in
            if CFEqual(element, app) {
                if name == kAXFocusedWindowAttribute { return window }
                if name == kAXFocusedUIElementAttribute { return editor }
            }
            if name == kAXRoleAttribute { return (CFEqual(element, window) ? "AXWindow" : "AXTextArea") as CFString }
            if name == kAXParentAttribute, CFEqual(element, editor) { return window }
            if name == kAXPositionAttribute { var point = CGPoint(x: 100, y: 100); return AXValueCreate(.cgPoint, &point) }
            if name == kAXSizeAttribute { var size = CGSize(width: 900, height: 700); return AXValueCreate(.cgSize, &size) }
            return nil
        }, children: { _ in [] }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil },
        applicationBundleID: { _ in "com.apple.Terminal" }, caretBounds: { _ in caret }, enableAccessibility: { _ in })
        try check(reader.read(pid: 2_700_000) == CGRect(x: 100, y: 595, width: 900, height: 30) && reader.usedPreset == .terminal,
                  "Terminal selected scrollback instead of the cursor row")
        caret = CGRect(x: 400, y: 400, width: 0, height: 24)
        try check(reader.read(pid: 2_700_000)?.minY == 394, "Terminal did not follow its cursor")
        caret = nil
        _ = reader.read(pid: 2_700_000)
        try check(reader.usedPreset == nil, "Terminal claimed a preset without cursor geometry")
    }

    private static func verifySettings() throws {
        let state = AppState(preview: true)
        let saved = state.disabledInputPresets
        defer { state.disabledInputPresets = saved }
        state.disabledInputPresets = []
        let window = AppearanceWindowController(state: state, presentsWindows: false)
        defer { window.window?.close() }
        window.showDictation()
        try check(window.showingDictation && !window.dictationPane.isHidden && window.window?.isVisible == false,
                  "Input detection settings are not reachable in hidden Dictation settings")
        for preset in InputTargetPreset.allCases where preset != .safari {
            state.disabledInputPresets.insert(preset.rawValue)
            try check(state.disabledInputPresets.contains(preset.rawValue), "Preset exception did not persist")
            try check(AppState(preview: true).disabledInputPresets.contains(preset.rawValue), "Preset switch did not survive state reconstruction")
            state.disabledInputPresets.remove(preset.rawValue)
            try check(!AppState(preview: true).disabledInputPresets.contains(preset.rawValue), "Preset could not be re-enabled")
        }
    }

    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw failure(message) } }
    private static func failure(_ message: String) -> NSError { NSError(domain: "InputPresetProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
