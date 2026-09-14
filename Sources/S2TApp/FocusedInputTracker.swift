import AppKit
import ApplicationServices
import S2TCore

// Reads roles, geometry and site identity. Terminal carets use selection offsets, never text contents.
final class FocusedInputReader {
    private var enabledPID: pid_t?
    private var deadline: TimeInterval = 0
    private var windowBounds: CGRect?
    private(set) var cornerRadius: CGFloat = 12
    private(set) var cornerStyle: InputCornerStyle = .continuous
    private var capsuleBoundary = false
    private(set) var usedPreset: InputTargetPreset?
    private var presetBoundary: AXUIElement?
    private let applicationBundleID: (pid_t) -> String
    private let caretBounds: (AXUIElement) -> CGRect?
    private let automaticResolver: (Int, [Int: ComposerNode]) -> CGRect?
    private struct CachedEditor {
        let pid: pid_t
        let window: AXUIElement
        let editor: AXUIElement
        let anchor: CGPoint?
        let discoveredAt: TimeInterval
    }
    private var cached: CachedEditor?
    private let attribute: (AXUIElement, String) -> CFTypeRef?
    private let children: (AXUIElement) -> [AXUIElement]?
    private let fallbackFocus: (pid_t) -> AXUIElement?
    private let hitTest: (AXUIElement, CGPoint) -> AXUIElement?
    private let enableAccessibility: (AXUIElement) -> Void

    init(attribute: @escaping (AXUIElement, String) -> CFTypeRef? = FocusedInputReader.systemAttribute,
         children: @escaping (AXUIElement) -> [AXUIElement]? = FocusedInputReader.systemChildren,
         fallbackFocus: @escaping (pid_t) -> AXUIElement? = FocusedInputReader.systemFocus,
         hitTest: @escaping (AXUIElement, CGPoint) -> AXUIElement? = FocusedInputReader.elementAtPosition,
         applicationBundleID: @escaping (pid_t) -> String = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier ?? "" },
         caretBounds: @escaping (AXUIElement) -> CGRect? = FocusedInputReader.systemCaretBounds,
         automaticResolver: @escaping (Int, [Int: ComposerNode]) -> CGRect? = { ComposerTargeting.resolve(editor: $0, nodes: $1) },
         enableAccessibility: @escaping (AXUIElement) -> Void = {
             AXUIElementSetAttributeValue($0, "AXManualAccessibility" as CFString, kCFBooleanTrue)
         }) {
        self.applicationBundleID = applicationBundleID
        self.caretBounds = caretBounds
        self.automaticResolver = automaticResolver
        self.attribute = attribute
        self.children = children
        self.fallbackFocus = fallbackFocus
        self.hitTest = hitTest
        self.enableAccessibility = enableAccessibility
    }

    func read(pid: pid_t, anchor: CGPoint? = nil, disabledPresets: Set<String> = []) -> CGRect? {
        usedPreset = nil
        cornerStyle = .continuous
        presetBoundary = nil
        let started = ProcessInfo.processInfo.systemUptime
        let overallDeadline = started + 1.0
        deadline = started + 0.25
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        if enabledPID != pid {
            enableAccessibility(app)
            enabledPID = pid
            cached = nil
        }
        let window = element(query(app, kAXFocusedWindowAttribute))
        windowBounds = window.flatMap(frame)
        let focused = focusedElement(in: app, pid: pid)
        if let focused, query(focused, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
        var editor = focused.flatMap { editorNear($0) }
        if editor == nil, let cached, cached.pid == pid, cached.anchor == anchor,
           let window, CFEqual(window, cached.window), started - cached.discoveredAt < 0.8,
           let bounds = frame(cached.editor), windowBounds?.intersects(bounds) == true {
            editor = cached.editor
        }
        if editor == nil, let windowBounds {
            deadline = started + 0.65
            editor = discover(in: app, window: windowBounds, anchor: anchor)
            if let editor, let window {
                cached = CachedEditor(pid: pid, window: window, editor: editor, anchor: anchor, discoveredAt: started)
            }
        }
        deadline = overallDeadline - 0.1
        guard let editor, let input = frame(editor), query(editor, kAXEnabledAttribute) as? Bool != false else {
            cached = nil
            return nil
        }
        let context = presetContext(around: editor, bundleID: applicationBundleID(pid))
        if context.webArea != nil { cornerStyle = .circular }
        let preset = context.preset.flatMap { disabledPresets.contains($0.rawValue) ? nil : $0 }
        var terminal: InputOutlineTarget?
        if preset == .terminal, let caret = caretBounds(editor) {
            var viewport = input
            var current = element(query(editor, kAXParentAttribute))
            for _ in 0..<12 {
                guard let node = current else { break }
                let role = query(node, kAXRoleAttribute) as? String ?? ""
                if role == "AXScrollArea", let bounds = frame(node) { viewport = viewport.intersection(bounds); break }
                if role == "AXWindow" || role == "AXApplication" { break }
                current = element(query(node, kAXParentAttribute))
            }
            if let windowBounds { viewport = viewport.intersection(windowBounds) }
            terminal = InputTargetPreset.terminalTarget(viewport: viewport, caret: caret)
        }
        let result: CGRect?
        if let terminal {
            usedPreset = .terminal
            cornerRadius = terminal.cornerRadius
            cornerStyle = terminal.cornerStyle
            result = terminal.frame
        } else {
            result = composer(around: editor, input: input, preset: preset)
        }
        deadline = overallDeadline
        if let window {
            guard let latestWindow = element(query(app, kAXFocusedWindowAttribute)), CFEqual(window, latestWindow) else {
                cached = nil
                return nil
            }
        }
        let latest = focusedElement(in: app, pid: pid)
        if let focused {
            guard let latest, CFEqual(latest, focused) else { cached = nil; return nil }
        } else if latest != nil {
            cached = nil
            return nil
        }
        guard frame(editor) == input, query(editor, kAXSubroleAttribute) as? String != "AXSecureTextField" else { return nil }
        if let presetBoundary, frame(presetBoundary) != result { return nil }
        if let webArea = context.webArea, siteURL(webArea)?.host?.lowercased() != context.host {
            return nil
        }
        if let result, usedPreset == nil {
            let subrole = query(editor, kAXSubroleAttribute) as? String ?? ""
            let isCapsule = subrole == "AXSearchField" || capsuleBoundary
            let insets = [input.minX - result.minX, result.maxX - input.maxX,
                          input.minY - result.minY, result.maxY - input.maxY]
            let inset = insets.filter { $0 > 0 && $0.isFinite }.min() ?? 8
            cornerRadius = InputOutlineGeometry.radius(for: result.size, contentInset: inset, capsule: isCapsule)
        }
        return result
    }

    private func siteURL(_ webArea: AXUIElement) -> URL? {
        let value = query(webArea, "AXURL")
        if let url = value as? URL { return url }
        return (value as? String).flatMap(URL.init(string:))
    }

    private func presetContext(around editor: AXUIElement, bundleID: String) -> (preset: InputTargetPreset?, webArea: AXUIElement?, host: String?) {
        var current: AXUIElement? = editor
        var seen = [AXUIElement]()
        var inToolbar = false
        var reachedWindow = false
        for _ in 0..<24 {
            guard let node = current, !seen.contains(where: { CFEqual($0, node) }) else { break }
            seen.append(node)
            let role = query(node, kAXRoleAttribute) as? String ?? ""
            if role == "AXWebArea" {
                let url = siteURL(node)
                return (InputTargetPreset.match(bundleID: bundleID, webURL: url, inWebContent: true), node, url?.host?.lowercased())
            }
            if role == "AXToolbar" { inToolbar = true }
            if role == "AXWindow" { reachedWindow = true; break }
            if role == "AXApplication" { break }
            current = element(query(node, kAXParentAttribute))
        }
        let preset = InputTargetPreset.match(bundleID: bundleID, webURL: nil, inWebContent: false)
        if preset == .safari && (!inToolbar || !reachedWindow) { return (nil, nil, nil) }
        return (preset, nil, nil)
    }

    static func systemCaretBounds(_ editor: AXUIElement) -> CGRect? {
        guard let value = systemAttribute(editor, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length == 0,
              let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(editor, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(result as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private func editable(_ node: AXUIElement, role: String) -> Bool {
        if query(node, "AXEditable") as? Bool == true { return true }
        guard role == "AXComboBox",
              let ancestor = element(query(node, "AXEditableAncestor")) else { return false }
        return CFEqual(ancestor, node)
    }

    private func editorNear(_ start: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = start
        var visited = [AXUIElement]()
        for depth in 0..<12 {
            guard let node = current, ProcessInfo.processInfo.systemUptime < deadline,
                  !visited.contains(where: { CFEqual($0, node) }) else { return nil }
            visited.append(node)
            let role = query(node, kAXRoleAttribute) as? String ?? ""
            let subrole = query(node, kAXSubroleAttribute) as? String ?? ""
            if subrole == "AXSecureTextField" { return nil }
            if InputOutlineGeometry.isInput(role: role, subrole: subrole, editable: editable(node, role: role)),
               query(node, kAXEnabledAttribute) as? Bool != false { return node }
            guard ["AXStaticText", "AXButton", "AXGroup", "AXLayoutArea", "AXUnknown", "AXScrollArea", "AXToolbar", "AXForm", "AXComboBox"].contains(role) else { return nil }
            if depth < 4, ComposerTargeting.containerRoles.contains(role),
               let bounds = frame(node), bounds.height < (windowBounds?.height ?? 1800) * 0.4,
               let editor = uniqueEditor(inside: node) { return editor }
            current = element(query(node, kAXParentAttribute))
        }
        return nil
    }

    private func discover(in app: AXUIElement, window: CGRect, anchor: CGPoint?) -> AXUIElement? {
        var elements = [AXUIElement]()
        var candidates = [DiscoveredInput]()
        for point in InputDiscovery.samplePoints(in: window, anchor: anchor) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard let hit = hitTest(app, point), let editor = editorNear(hit), let bounds = frame(editor),
                  bounds.width >= 24, bounds.height >= 8, window.intersects(bounds),
                  !elements.contains(where: { CFEqual($0, editor) }) else { continue }
            if let anchor, point == anchor { return editor }
            let id = elements.count
            elements.append(editor)
            let isFocused = query(editor, kAXFocusedAttribute) as? Bool == true
            candidates.append(DiscoveredInput(id: id, frame: bounds, boundary: bounds, focused: isFocused))
            if isFocused { return editor }
        }
        guard let id = InputDiscovery.choose(candidates, window: window, anchor: nil) else { return nil }
        return elements[id]
    }

    static func elementAtPosition(_ app: AXUIElement, _ point: CGPoint) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(app, 0.025)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var owner: pid_t = 0, requested: pid_t = 0
        guard AXUIElementGetPid(app, &requested) == .success, AXUIElementGetPid(element, &owner) == .success,
              owner == requested else { return nil }
        return element
    }

    private func focusedElement(in app: AXUIElement, pid: pid_t) -> AXUIElement? {
        element(query(app, kAXFocusedUIElementAttribute)) ?? fallbackFocus(pid)
    }

    private func uniqueEditor(inside root: AXUIElement) -> AXUIElement? {
        var queue = [(root, 0)]
        var seen = [AXUIElement]()
        var match: AXUIElement?
        while !queue.isEmpty, seen.count < 32, ProcessInfo.processInfo.systemUptime < deadline {
            let (node, depth) = queue.removeFirst()
            if seen.contains(where: { CFEqual($0, node) }) { continue }
            seen.append(node)
            let role = query(node, kAXRoleAttribute) as? String ?? ""
            let subrole = query(node, kAXSubroleAttribute) as? String ?? ""
            let editable = editable(node, role: role)
            if subrole == "AXSecureTextField" { return nil }
            if InputOutlineGeometry.isInput(role: role, subrole: subrole, editable: editable),
               query(node, kAXEnabledAttribute) as? Bool != false, let bounds = frame(node), bounds.width > 1, bounds.height > 1 {
                if match != nil { return nil }
                match = node
                continue
            }
            guard depth < 5, ComposerTargeting.containerRoles.contains(role), let descendants = children(node), descendants.count <= 32 else { continue }
            queue.append(contentsOf: descendants.map { ($0, depth + 1) })
        }
        return queue.isEmpty ? match : nil
    }

    static func systemFocus(pid: pid_t) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.04)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success, owner == pid else { return nil }
        return element
    }

    private func frame(_ node: AXUIElement) -> CGRect? {
        guard let position = query(node, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = query(node, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    private func composer(around editor: AXUIElement, input: CGRect, preset: InputTargetPreset?) -> CGRect? {
        capsuleBoundary = false
        var elements = [AXUIElement]()
        var nodes = [Int: ComposerNode]()
        var parentIDs = [Int: Int]()
        var childIDs = [Int: [Int]]()
        var complete = [Int: Bool]()

        func register(_ element: AXUIElement) -> Int? {
            if let id = elements.firstIndex(where: { CFEqual($0, element) }) { return id }
            guard elements.count < 192, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let id = elements.count
            elements.append(element)
            let role = query(element, kAXRoleAttribute) as? String ?? ""
            let subrole = query(element, kAXSubroleAttribute) as? String ?? ""
            let editable = editable(element, role: role)
            nodes[id] = ComposerNode(id: id, role: role, subrole: subrole, editable: editable,
                                     frame: id == 0 ? input : frame(element), parent: nil)
            return id
        }
        guard let editorID = register(editor) else { return nil }
        if let preset, let target = preset.resolve(editor: editorID, nodes: nodes) {
            usedPreset = preset
            cornerRadius = target.cornerRadius
            cornerStyle = target.cornerStyle
            return target.frame
        }
        var ancestors = [Int]()
        var current = editorID
        var path: Set<Int> = [editorID]
        for _ in 0..<24 {
            guard let parent = element(query(elements[current], kAXParentAttribute)), let id = register(parent),
                  path.insert(id).inserted, let metadata = nodes[id],
                  ComposerTargeting.containerRoles.contains(metadata.role), !metadata.subrole.contains("Navigation") else { break }
            parentIDs[current] = id
            ancestors.append(id)
            current = id
        }
        var expanded = Set<Int>()
        capsuleBoundary = ancestors.contains { nodes[$0]?.subrole == "AXLandmarkSearch" }
        func expand(_ id: Int, depth: Int) {
            guard id != editorID, expanded.insert(id).inserted, let metadata = nodes[id] else { return }
            let nearbyAccessory = ComposerTargeting.accessoryRoles.contains(metadata.role) && metadata.frame.map {
                $0.height <= max(input.height * 2, input.width * 0.35)
                    && $0.intersects(input.insetBy(dx: input.width * -0.15, dy: max(input.height * 2, input.width * 0.25) * -1))
            } == true
            if (!ComposerTargeting.containerRoles.contains(metadata.role) && !nearbyAccessory)
                || (!path.contains(id) && InputOutlineGeometry.isInput(role: metadata.role, subrole: metadata.subrole, editable: metadata.editable)) {
                complete[id] = true
                return
            }
            guard depth < 8, ProcessInfo.processInfo.systemUptime < deadline,
                  let descendants = children(elements[id]) else { complete[id] = false; return }
            complete[id] = descendants.count <= 32
            for child in descendants.prefix(32) {
                guard let childID = register(child) else { complete[id] = false; break }
                childIDs[id, default: []].append(childID)
                if parentIDs[childID] == nil { parentIDs[childID] = id }
                if !path.contains(childID) { expand(childID, depth: depth + 1) }
            }
            // Some native containers omit their focused descendant from AXChildren.
            if let knownChild = parentIDs.first(where: { $0.value == id && path.contains($0.key) })?.key,
               childIDs[id]?.contains(knownChild) != true {
                childIDs[id, default: []].append(knownChild)
            }
        }
        func snapshot() -> [Int: ComposerNode] {
            nodes.mapValues { node in
                ComposerNode(id: node.id, role: node.role, subrole: node.subrole, editable: node.editable,
                             frame: node.frame, parent: parentIDs[node.id], children: childIDs[node.id] ?? [],
                             childrenComplete: node.id == editorID || complete[node.id] == true)
            }
        }
        if let preset, preset.usesComposerBoundary {
            for id in ancestors {
                guard let bounds = nodes[id]?.frame, preset.acceptsBoundary(bounds, editor: input) else { continue }
                expand(id, depth: 0)
                if let target = preset.resolve(editor: editorID, nodes: snapshot()) {
                    usedPreset = preset
                    cornerRadius = target.cornerRadius
                    cornerStyle = target.cornerStyle
                    if let node = nodes.values.first(where: { $0.frame == target.frame }) { presetBoundary = elements[node.id] }
                    return target.frame
                }
            }
        }
        var result: CGRect? = input
        for id in ancestors {
            if let best = result, best != input, let bounds = nodes[id]?.frame {
                let largeWidth = max(best.width * 1.8, (windowBounds?.width ?? best.width) * 0.9)
                let largeHeight = max(best.height * 3, (windowBounds?.height ?? best.height) * 0.4)
                if bounds.width > largeWidth || bounds.height > largeHeight { break }
            }
            expand(id, depth: 0)
            result = automaticResolver(editorID, snapshot())
        }
        if let result {
            let controls = nodes.values.compactMap { node -> CGRect? in
                guard !path.contains(node.id), ComposerTargeting.controlRoles.contains(node.role),
                      let bounds = node.frame, result.contains(bounds) else { return nil }
                return bounds
            }
            capsuleBoundary = capsuleBoundary || InputOutlineGeometry.isCapsule(
                field: result, editor: input, role: nodes[editorID]?.role ?? "", controls: controls)
        }
        return result
    }

    private func query(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        return attribute(node, name)
    }

    static func systemChildren(_ node: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(node, 0.04)
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(node, kAXChildrenAttribute as CFString, &count) == .success else { return nil }
        if count == 0 { return [] }
        var values: CFArray?
        guard AXUIElementCopyAttributeValues(node, kAXChildrenAttribute as CFString, 0, min(33, count), &values) == .success else { return nil }
        return values as? [AXUIElement]
    }

    static func systemAttribute(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(node, 0.04)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

actor FocusedInputService {
    private let reader: FocusedInputReader

    init(reader: FocusedInputReader = FocusedInputReader()) { self.reader = reader }

    func read(pid: pid_t, anchor: CGPoint?, disabledPresets: Set<String> = []) async -> InputOutlineTarget? {
        if let frame = reader.read(pid: pid, anchor: anchor, disabledPresets: disabledPresets) {
            return InputOutlineTarget(frame: frame, cornerRadius: reader.cornerRadius, cornerStyle: reader.cornerStyle)
        }
        // AX trees can be briefly unavailable during layout. Confirm failure with
        // a fresh, focus-validated read before switching to the Bottom fallback.
        do { try await Task.sleep(nanoseconds: 80_000_000) }
        catch { return nil }
        guard !Task.isCancelled else { return nil }
        guard let frame = reader.read(pid: pid, anchor: anchor, disabledPresets: disabledPresets) else { return nil }
        return InputOutlineTarget(frame: frame, cornerRadius: reader.cornerRadius, cornerStyle: reader.cornerStyle)
    }
}

@MainActor final class FocusedInputTracker {
    private let reader = FocusedInputService()
    private var busy = false
    private var generation = 0
    private var mouseMonitor: Any?
    private var lastClick: (pid: pid_t, point: CGPoint, time: TimeInterval)?

    init() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let app = NSWorkspace.shared.frontmostApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      app.bundleIdentifier != "com.raycast.macos" else { return }
                let point = NSEvent.mouseLocation
                guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) else { return }
                self.lastClick = (app.processIdentifier, point, ProcessInfo.processInfo.systemUptime)
                self.generation += 1
            }
        }
    }

    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }

    func invalidate() { generation += 1 }

    func refresh(disabledPresets: Set<String> = [], completion: @escaping (InputOutlineTarget?, String?) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(nil, "Around Input needs Accessibility access. Using Bottom until access is allowed.")
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.raycast.macos" else {
            completion(nil, "Select a text field in your app. Using Bottom for now.")
            return
        }
        guard !busy else { return }
        busy = true
        let pid = app.processIdentifier
        let request = generation
        let reader = self.reader
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let click = lastClick.flatMap { click -> CGPoint? in
            guard click.pid == pid, ProcessInfo.processInfo.systemUptime - click.time < 60 else { return nil }
            return CGPoint(x: click.point.x, y: primaryTop - click.point.y)
        }
        Task { [weak self] in
            let target = await reader.read(pid: pid, anchor: click, disabledPresets: disabledPresets)
            guard let self else { return }
            self.busy = false
            guard request == self.generation else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                completion(nil, "Focus changed. Locating the active text field…")
                return
            }
            let screens = NSScreen.screens
            let converted = target.flatMap {
                InputOutlineGeometry.screenFrame(accessibilityFrame: $0.frame, primaryTop: screens.first?.frame.maxY ?? 0, screens: screens.map(\.frame))
            }
            completion(converted.flatMap { frame in target.map { InputOutlineTarget(frame: frame, cornerRadius: $0.cornerRadius, cornerStyle: $0.cornerStyle) } }, converted == nil ? "Could not identify the active input. Using Bottom for now." : nil)
        }
    }
}
