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
    private(set) var contour: InputContour?
    private(set) var targetKind: InputOutlineTarget.Kind = .input
    private(set) var usedPreset: InputTargetPreset?
    private(set) var geometryChangedDuringRead = false
    /// The editor and window behind the last successful read, for pixel measurement.
    private(set) var measuredEditor: (element: AXUIElement, frame: CGRect, window: CGRect)?
    private var sourceBoundaries: [(AXUIElement, CGRect)] = []
    private let applicationBundleID: (pid_t) -> String
    private let caretBounds: (AXUIElement) -> CGRect?
    private let automaticResolver: (Int, [Int: ComposerNode], InputCornerStyle) -> InputOutlineTarget?
    private struct CachedEditor {
        let pid: pid_t
        let window: AXUIElement
        let editor: AXUIElement
        let anchor: CGPoint?
        let focus: AXUIElement?
        let discoveredAt: TimeInterval
    }
    private var cached: CachedEditor?
    private let attribute: (AXUIElement, String) -> CFTypeRef?
    private let metadata: ((AXUIElement) -> [String: CFTypeRef]?)?
    private struct ElementKey: Hashable {
        let element: AXUIElement
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }
    private var snapshot = [ElementKey: [String: CFTypeRef]]()
    private var samplesMetadata = false
    private static let metadataNames = [kAXRoleAttribute, kAXSubroleAttribute, kAXParentAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute, "AXEditable"]
    private let children: (AXUIElement) -> [AXUIElement]?
    private let fallbackFocus: (pid_t) -> AXUIElement?
    private let hitTest: (AXUIElement, CGPoint) -> AXUIElement?
    private let enableAccessibility: (AXUIElement) -> Void

    init(attribute: ((AXUIElement, String) -> CFTypeRef?)? = nil,
         children: @escaping (AXUIElement) -> [AXUIElement]? = FocusedInputReader.systemChildren,
         fallbackFocus: @escaping (pid_t) -> AXUIElement? = FocusedInputReader.systemFocus,
         hitTest: @escaping (AXUIElement, CGPoint) -> AXUIElement? = FocusedInputReader.elementAtPosition,
         applicationBundleID: @escaping (pid_t) -> String = { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier ?? "" },
         caretBounds: @escaping (AXUIElement) -> CGRect? = FocusedInputReader.systemCaretBounds,
         automaticResolver: @escaping (Int, [Int: ComposerNode], InputCornerStyle) -> InputOutlineTarget? = { ComposerTargeting.resolveTarget(editor: $0, nodes: $1, cornerStyle: $2) },
         enableAccessibility: @escaping (AXUIElement) -> Void = {
             FocusedInputReader.enableApplicationAccessibility($0)
         }) {
        self.applicationBundleID = applicationBundleID
        self.caretBounds = caretBounds
        self.automaticResolver = automaticResolver
        self.attribute = attribute ?? Self.systemAttribute
        self.metadata = attribute == nil ? Self.systemMetadata : nil
        self.children = children
        self.fallbackFocus = fallbackFocus
        self.hitTest = hitTest
        self.enableAccessibility = enableAccessibility
    }

    static func enableApplicationAccessibility(_ app: AXUIElement,
        setAttribute: (AXUIElement, String, CFTypeRef) -> AXError = {
            AXUIElementSetAttributeValue($0, $1 as CFString, $2)
        }) {
        let result = setAttribute(app, "AXManualAccessibility", kCFBooleanTrue)
        guard result == .attributeUnsupported || result == .notImplemented else { return }
        // Chromium exposes its web tree asynchronously through this attribute.
        // Its setter may return AppKit's notImplemented after accepting the request.
        _ = setAttribute(app, "AXEnhancedUserInterface", kCFBooleanTrue)
    }

    func prepareAccessibility(pid: pid_t) {
        guard enabledPID != pid else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        enableAccessibility(app)
        enabledPID = pid
        cached = nil
    }

    func read(pid: pid_t, anchor: CGPoint? = nil, disabledPresets: Set<String> = [], pinned: PromptDestination? = nil) -> CGRect? {
        snapshot.removeAll(keepingCapacity: true)
        samplesMetadata = true
        defer { snapshot.removeAll(keepingCapacity: true); samplesMetadata = false }
        usedPreset = nil
        cornerStyle = .continuous
        sourceBoundaries = []
        contour = nil
        targetKind = .input
        geometryChangedDuringRead = false
        measuredEditor = nil
        let started = ProcessInfo.processInfo.systemUptime
        let overallDeadline = started + 1.0
        deadline = started + 0.25
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        prepareAccessibility(pid: pid)
        let window = pinned?.window ?? element(query(app, kAXFocusedWindowAttribute))
        windowBounds = window.flatMap(frame)
        if let window, query(window, kAXMinimizedAttribute) as? Bool == true { return nil }
        let focused = pinned?.field ?? focusedElement(in: app, pid: pid)
        if let focused, query(focused, kAXSubroleAttribute) as? String == "AXSecureTextField" { return nil }
        var editor = focused.flatMap { editorNear($0) }
        if editor == nil, let cached, cached.pid == pid, cached.anchor == anchor, sameElement(cached.focus, focused),
           let window, CFEqual(window, cached.window), started - cached.discoveredAt < 0.8,
           query(cached.editor, kAXFocusedAttribute) as? Bool != false,
           let bounds = frame(cached.editor), windowBounds?.intersects(bounds) == true {
            editor = cached.editor
        }
        if editor == nil, pinned == nil, let windowBounds {
            deadline = started + 0.65
            editor = discover(in: app, root: window, window: windowBounds, anchor: anchor)
            if let editor, let window {
                cached = CachedEditor(pid: pid, window: window, editor: editor, anchor: anchor, focus: focused, discoveredAt: started)
            }
        }
        deadline = overallDeadline - 0.1
        guard let editor, let input = frame(editor), query(editor, kAXEnabledAttribute) as? Bool != false else {
            cached = nil
            return nil
        }
        let selectedFocused = pinned == nil ? query(editor, kAXFocusedAttribute) as? Bool : nil
        let context = presetContext(around: editor, bundleID: applicationBundleID(pid))
        if context.webArea != nil { cornerStyle = .circular }
        let preset = context.preset.flatMap { $0 == .safari || disabledPresets.contains($0.rawValue) ? nil : $0 }
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
            contour = terminal.contour
            result = terminal.frame
        } else {
            result = composer(around: editor, input: input, preset: preset)
        }
        deadline = overallDeadline
        // Validate with a new batched snapshot, independent of discovery.
        snapshot.removeAll(keepingCapacity: true)
        if let window {
            guard validateFrame(window, expected: windowBounds) else { return nil }
            if pinned == nil, !sameElement(element(query(app, kAXFocusedWindowAttribute)), window) {
                cached = nil
                return nil
            }
        }
        let latest = pinned?.field ?? focusedElement(in: app, pid: pid)
        if let focused {
            guard let latest, CFEqual(latest, focused) else { cached = nil; return nil }
        } else if latest != nil {
            cached = nil
            return nil
        }
        guard validateFrame(editor, expected: input), query(editor, kAXSubroleAttribute) as? String != "AXSecureTextField" else { return nil }
        if selectedFocused == true, query(editor, kAXFocusedAttribute) as? Bool != true { cached = nil; return nil }
        guard sourceBoundaries.allSatisfy({ validateFrame($0.0, expected: $0.1) }) else { return nil }
        if let webArea = context.webArea, siteOrigin(siteURL(webArea)) != context.origin { return nil }
        if let marker = context.marker, !InputTargetPreset.identifiesT3Composer(classes: composerClasses(marker)) { return nil }
        if let result, contour == nil {
            contour = InputContour(rect: CGRect(origin: .zero, size: result.size), radius: cornerRadius, style: cornerStyle)
        }
        if result != nil, usedPreset != .terminal, let windowBounds { measuredEditor = (editor, input, windowBounds) }
        return result
    }

    private func validateFrame(_ node: AXUIElement, expected: CGRect?) -> Bool {
        let current = frame(node)
        guard current == expected else {
            geometryChangedDuringRead = current != nil && expected != nil
            return false
        }
        return true
    }

    private func siteURL(_ webArea: AXUIElement) -> URL? {
        let value = query(webArea, "AXURL")
        if let url = value as? URL { return url }
        return (value as? String).flatMap(URL.init(string:))
    }

    private func composerClasses(_ node: AXUIElement) -> [String] {
        let classes = query(node, "AXDOMClassList") as? [String] ?? []
        return classes.count <= 256 ? classes : []
    }

    private func siteOrigin(_ url: URL?) -> String? {
        url.map { "\($0.scheme?.lowercased() ?? "")://\($0.host?.lowercased() ?? ""):\($0.port ?? 0)" }
    }

    private func presetContext(around editor: AXUIElement, bundleID: String) -> (preset: InputTargetPreset?, webArea: AXUIElement?, origin: String?, marker: AXUIElement?) {
        var current: AXUIElement? = editor
        var seen = [AXUIElement]()
        var inToolbar = false
        var reachedWindow = false
        var marker: AXUIElement?
        for _ in 0..<24 {
            guard let node = current, !seen.contains(where: { CFEqual($0, node) }) else { break }
            seen.append(node)
            let role = query(node, kAXRoleAttribute) as? String ?? ""
            if role == "AXWebArea" {
                let url = siteURL(node)
                let preset = marker == nil ? InputTargetPreset.match(bundleID: bundleID, webURL: url, inWebContent: true) : .t3Code
                return (preset, node, siteOrigin(url), marker)
            }
            if marker == nil, ComposerTargeting.containerRoles.contains(role),
               InputTargetPreset.identifiesT3Composer(classes: composerClasses(node)) { marker = node }
            if role == "AXToolbar" { inToolbar = true }
            if role == "AXWindow" { reachedWindow = true; break }
            if role == "AXApplication" { break }
            current = element(query(node, kAXParentAttribute))
        }
        let preset = InputTargetPreset.match(bundleID: bundleID, webURL: nil, inWebContent: false)
        if preset == .safari && (!inToolbar || !reachedWindow) { return (nil, nil, nil, nil) }
        return (preset, nil, nil, nil)
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
               query(node, kAXEnabledAttribute) as? Bool != false,
               let bounds = frame(node), bounds.width >= 24, bounds.height >= 8 { return node }
            guard ["AXStaticText", "AXButton", "AXGroup", "AXLayoutArea", "AXUnknown", "AXScrollArea", "AXToolbar", "AXForm", "AXComboBox"].contains(role) else { return nil }
            if depth < 4, ComposerTargeting.containerRoles.contains(role),
               let bounds = frame(node), bounds.height < (windowBounds?.height ?? 1800) * 0.4,
               let editor = uniqueEditor(inside: node) { return editor }
            current = element(query(node, kAXParentAttribute))
        }
        return nil
    }

    private func discover(in app: AXUIElement, root: AXUIElement?, window: CGRect, anchor: CGPoint?) -> AXUIElement? {
        var elements = [AXUIElement]()
        var candidates = [DiscoveredInput]()
        var anchored: Int?
        func collect(_ editor: AXUIElement, atAnchor: Bool = false) {
            guard let bounds = frame(editor), bounds.width >= 24, bounds.height >= 8, window.intersects(bounds),
                  query(editor, kAXEnabledAttribute) as? Bool != false else { return }
            if let id = elements.firstIndex(where: { CFEqual($0, editor) }) {
                if atAnchor { anchored = id }
                return
            }
            let id = elements.count
            elements.append(editor)
            candidates.append(DiscoveredInput(id: id, frame: bounds, boundary: bounds,
                focused: query(editor, kAXFocusedAttribute) as? Bool == true))
            if atAnchor { anchored = id }
        }
        // Inspect only structural metadata. This finds narrow fields between the
        // grid points and editors under transparent web/native wrappers.
        var queue = root.map { [($0, 0)] } ?? []
        var visited = Set<ElementKey>()
        let treeDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 0.2)
        while !queue.isEmpty, visited.count < 96, ProcessInfo.processInfo.systemUptime < treeDeadline {
            let (node, depth) = queue.removeFirst()
            guard visited.insert(ElementKey(element: node)).inserted else { continue }
            let role = query(node, kAXRoleAttribute) as? String ?? ""
            let subrole = query(node, kAXSubroleAttribute) as? String ?? ""
            if subrole == "AXSecureTextField" {
                if query(node, kAXFocusedAttribute) as? Bool == true { return nil }
                continue
            }
            if InputOutlineGeometry.isInput(role: role, subrole: subrole, editable: editable(node, role: role)) {
                collect(node)
                continue
            }
            guard depth < 24, ComposerTargeting.containerRoles.contains(role)
                || ["AXWindow", "AXWebArea", "AXSplitGroup", "AXTabGroup"].contains(role),
                let descendants = children(node) else { continue }
            let remaining = max(0, 96 - visited.count - queue.count)
            queue.append(contentsOf: descendants.prefix(remaining).map { ($0, depth + 1) })
        }
        if candidates.filter(\.focused).count == 1,
           let id = InputDiscovery.choose(candidates, window: window, anchor: nil) { return elements[id] }
        for point in InputDiscovery.samplePoints(in: window, anchor: anchor) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            guard let hit = hitTest(app, point), let editor = editorNear(hit) else { continue }
            collect(editor, atAnchor: anchor == point)
        }
        let focused = candidates.filter(\.focused)
        if focused.count > 1 { return nil }
        if let focused = focused.first { return elements[focused.id] }
        if let anchored { return elements[anchored] }
        guard let id = InputDiscovery.choose(candidates, window: window, anchor: anchor) else { return nil }
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
               query(node, kAXEnabledAttribute) as? Bool != false, let bounds = frame(node), bounds.width >= 24, bounds.height >= 8 {
                if match != nil { return nil }
                match = node
                continue
            }
            guard depth < 24, ComposerTargeting.containerRoles.contains(role), let descendants = children(node), descendants.count <= 32 else { continue }
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
            guard depth < 24, ProcessInfo.processInfo.systemUptime < deadline,
                  let descendants = children(elements[id]) else { complete[id] = false; return }
            complete[id] = descendants.count <= 32
            for child in descendants.prefix(32) {
                guard let childID = register(child) else { complete[id] = false; break }
                childIDs[id, default: []].append(childID)
                if parentIDs[childID] == nil { parentIDs[childID] = id }
                expand(childID, depth: depth + 1)
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
        func accept(_ target: InputOutlineTarget) -> CGRect? {
            targetKind = target.kind
            cornerRadius = target.cornerRadius
            cornerStyle = target.cornerStyle
            contour = target.contour
            let absolute = target.contour.offsetBy(dx: target.frame.minX, dy: target.frame.minY)
            for part in absolute.parts {
                let tolerance = max(2, target.cornerRadius / 4)
                let measured = nodes.values.first(where: { node in
                    guard let rect = node.frame else { return false }
                    guard abs(rect.minX - part.rect.minX) < 0.001 && abs(rect.width - part.rect.width) < 0.001 else { return false }
                    switch part.corners {
                    case .all: return abs(rect.minY - part.rect.minY) < 0.001 && abs(rect.height - part.rect.height) < 0.001
                    case .bottom: return abs(rect.maxY - part.rect.maxY) <= tolerance
                        && rect.minY <= part.rect.minY + tolerance && rect.maxY > part.rect.minY
                    case .top: return abs(rect.minY - part.rect.minY) <= tolerance
                        && rect.maxY >= part.rect.maxY - tolerance && rect.minY < part.rect.maxY
                    }
                })
                let viewport = measured == nil && usedPreset == nil && part.corners == .all
                    ? nodes.values.first(where: { node in
                        guard path.contains(node.id), node.role == "AXScrollArea", let rect = node.frame else { return false }
                        return rect.intersection(input) == part.rect
                    }) : nil
                if let source = measured ?? viewport, let rect = source.frame {
                    sourceBoundaries.append((elements[source.id], rect))
                }
            }
            guard sourceBoundaries.count == absolute.parts.count else { return nil }
            return target.frame
        }
        var result = automaticResolver(editorID, snapshot(), cornerStyle)
        for id in ancestors {
            if let best = result?.frame, best != input, let bounds = nodes[id]?.frame {
                let largeWidth = max(best.width * 1.8, (windowBounds?.width ?? best.width) * 0.9)
                let largeHeight = max(best.height * 3, (windowBounds?.height ?? best.height) * 0.4)
                if bounds.width > largeWidth || bounds.height > largeHeight { break }
            }
            expand(id, depth: 0)
            result = automaticResolver(editorID, snapshot(), cornerStyle)
        }
        guard let result else { return nil }
        // Manual tuning may refine a shape, but every app shares the same
        // boundary selection. A preset cannot replace it with a smaller field.
        if let preset, preset != .terminal, let calibrated = preset.resolve(editor: editorID, nodes: snapshot()),
           calibrated.frame == result.frame,
           calibrated.contour.parts.map(\.rect) == result.contour.parts.map(\.rect),
           calibrated.contour.parts.map(\.corners) == result.contour.parts.map(\.corners) {
            usedPreset = preset
            return accept(calibrated)
        }
        return accept(result)
    }

    private func query(_ node: AXUIElement, _ name: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        guard samplesMetadata, Self.metadataNames.contains(name) else { return attribute(node, name) }
        let key = ElementKey(element: node)
        if snapshot[key] == nil, let values = metadata?(node) { snapshot[key] = values }
        if let value = snapshot[key]?[name] {
            return CFGetTypeID(value) == CFNullGetTypeID() ? nil : value
        }
        let value = attribute(node, name)
        snapshot[key, default: [:]][name] = value ?? kCFNull
        return value
    }

    static func systemMetadata(_ node: AXUIElement) -> [String: CFTypeRef]? {
        AXUIElementSetMessagingTimeout(node, 0.04)
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, metadataNames as CFArray, [], &values) == .success,
              let values = values as? [CFTypeRef], values.count == metadataNames.count else { return nil }
        return Dictionary(uniqueKeysWithValues: zip(metadataNames, values).map { name, value in
            let missing = CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError
            return (name, missing ? kCFNull as CFTypeRef : value)
        })
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

    private func sameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case let (a?, b?): return CFEqual(a, b)
        case (nil, nil): return true
        default: return false
        }
    }
}

actor FocusedInputService {
    enum ReadResult: Sendable {
        case found(InputOutlineTarget)
        case geometryChanging
        case unavailable

        var target: InputOutlineTarget? {
            if case let .found(target) = self { return target }
            return nil
        }
    }
    private let reader: FocusedInputReader
    private let surfaces: InputSurfaceCapture?
    private struct Geometry: Equatable { let editor: CGRect; let source: CGRect; let window: CGRect }
    private struct Measurement {
        let pid: pid_t
        let editor: AXUIElement
        let geometry: Geometry
        /// Nil when the pixels were inconclusive, so the accessibility boundary stays in use.
        let surface: InputOutlineTarget?
        let measuredAt: TimeInterval
    }
    /// Fields can animate or open attached lists without moving. Settled fields are checked again at this interval.
    private static let remeasureInterval: TimeInterval = 1
    private var measurement: Measurement?
    private var lastGeometry: Geometry?
    /// Whether the last read used the painted field rather than the accessibility estimate.
    private(set) var usedPixels = false

    init(reader: FocusedInputReader = FocusedInputReader(), measuresPixels: Bool = true) {
        self.reader = reader
        surfaces = measuresPixels ? InputSurfaceCapture() : nil
    }

    func prepareAccessibility(pid: pid_t) { reader.prepareAccessibility(pid: pid) }

    /// Replaces the accessibility estimate with the painted field when the pixels are unambiguous.
    private func measured(_ target: InputOutlineTarget, pid: pid_t) async -> InputOutlineTarget {
        usedPixels = false
        guard let surfaces, target.kind == .input, let editor = reader.measuredEditor else { return target }
        let geometry = Geometry(editor: editor.frame, source: target.frame, window: editor.window)
        defer { lastGeometry = geometry }
        if let measurement, measurement.pid == pid, CFEqual(measurement.editor, editor.element) {
            let fresh = ProcessInfo.processInfo.systemUptime - measurement.measuredAt < Self.remeasureInterval
            guard let surface = measurement.surface else {
                if (measurement.geometry == geometry && fresh) || lastGeometry != geometry { return target }
                return await measure(target, pid: pid, editor: editor.element, geometry: geometry, surfaces: surfaces)
            }
            if measurement.geometry == geometry && fresh { return surface }
            if measurement.geometry == geometry {
                // A failed recheck keeps the last good shape instead of flickering to the estimate.
                let recheck = await measure(target, pid: pid, editor: editor.element, geometry: geometry, surfaces: surfaces, fallback: surface)
                return recheck
            }
            // While the field moves or grows, keep the measured insets and measure again once it settles.
            if lastGeometry != geometry { return Self.transfer(surface, from: measurement.geometry.source, to: target.frame) }
        }
        return await measure(target, pid: pid, editor: editor.element, geometry: geometry, surfaces: surfaces)
    }

    private func measure(_ target: InputOutlineTarget, pid: pid_t, editor: AXUIElement, geometry: Geometry,
                         surfaces: InputSurfaceCapture, fallback: InputOutlineTarget? = nil) async -> InputOutlineTarget {
        // Accessibility may report only the text box. Leave room for the full painted field,
        // including toolbars below the text and wide search bars.
        let source = target.frame.union(geometry.editor)
        let margin = max(96, source.height)
        let region = CGRect(x: geometry.window.minX, y: source.minY - margin, width: geometry.window.width, height: source.height + margin * 2)
        var surface: InputOutlineTarget?
        let started = ProcessInfo.processInfo.systemUptime
        if let frame = await surfaces.capture(pid: pid, window: geometry.window, region: region) {
            let captured = ProcessInfo.processInfo.systemUptime
            defer { InputSurfaceDetector.trace?(String(format: "capture %.0fms, measure %.0fms", (captured - started) * 1000, (ProcessInfo.processInfo.systemUptime - captured) * 1000)) }
            let scale = frame.scale
            let local = geometry.editor.intersection(frame.region).offsetBy(dx: -frame.region.minX, dy: -frame.region.minY)
            let pixels = CGRect(x: local.minX * scale, y: local.minY * scale, width: local.width * scale, height: local.height * scale)
            var edges = InputSurfaceDetector.Edges()
            if frame.region.minY <= geometry.window.minY + 0.5 { edges.insert(.top) }
            if frame.region.minX <= geometry.window.minX + 0.5 { edges.insert(.left) }
            if frame.region.maxY >= geometry.window.maxY - 0.5 { edges.insert(.bottom) }
            if frame.region.maxX >= geometry.window.maxX - 0.5 { edges.insert(.right) }
            if !local.isNull, let found = InputSurfaceDetector.detect(in: frame.bitmap, editor: pixels, scale: scale, windowEdges: edges) {
                let rect = CGRect(x: frame.region.minX + found.rect.minX / scale, y: frame.region.minY + found.rect.minY / scale,
                                  width: found.rect.width / scale, height: found.rect.height / scale)
                var measured = Self.surface(rect, radius: found.radius / scale, corners: found.corners,
                                            style: found.capsule || found.corners != .all ? .circular : target.cornerStyle)
                if !found.bars.isEmpty {
                    var contour = measured.contour.offsetBy(dx: rect.minX, dy: rect.minY)
                    contour.bars = found.bars.map { bar in
                        var part = bar
                        part.rect = CGRect(x: frame.region.minX + bar.rect.minX / scale, y: frame.region.minY + bar.rect.minY / scale,
                                           width: bar.rect.width / scale, height: bar.rect.height / scale)
                        part.radius = bar.radius / scale
                        return part
                    }
                    measured = InputOutlineTarget(contour: contour)
                }
                surface = measured
            }
        }
        let result = surface ?? fallback
        measurement = Measurement(pid: pid, editor: editor, geometry: geometry, surface: result,
                                  measuredAt: ProcessInfo.processInfo.systemUptime)
        usedPixels = result != nil
        return result ?? target
    }

    private static func transfer(_ surface: InputOutlineTarget, from source: CGRect, to current: CGRect) -> InputOutlineTarget {
        let rect = CGRect(x: current.minX + surface.frame.minX - source.minX, y: current.minY + surface.frame.minY - source.minY,
                          width: current.width + surface.frame.width - source.width,
                          height: current.height + surface.frame.height - source.height)
        guard rect.width > 8, rect.height > 8 else {
            return self.surface(current, radius: min(surface.cornerRadius, current.height / 2), corners: .all, style: surface.cornerStyle)
        }
        // Parts keep their measured offsets from the moving edges nearest to them.
        let scaleX = rect.width / surface.frame.width
        var contour = surface.contour
        contour.main.rect = CGRect(origin: .zero, size: CGSize(width: rect.width, height: contour.main.rect.height + rect.height - surface.frame.height))
        contour.bars = contour.bars.map { bar in
            var part = bar
            let fromBottom = surface.frame.height - bar.rect.maxY
            part.rect = CGRect(x: bar.rect.minX * scaleX, y: rect.height - fromBottom - bar.rect.height,
                               width: bar.rect.width * scaleX, height: bar.rect.height)
            if bar.corners == .top { part.rect.origin.y = bar.rect.minY }
            return part
        }
        if contour.bars.contains(where: { $0.corners == .top }) {
            contour.main.rect.origin.y = surface.contour.main.rect.minY
        }
        return InputOutlineTarget(frame: rect, contour: contour)
    }

    private static func surface(_ rect: CGRect, radius: CGFloat, corners: InputContour.Corners, style: InputCornerStyle) -> InputOutlineTarget {
        var contour = InputContour(rect: CGRect(origin: .zero, size: rect.size), radius: radius, style: style)
        contour.main.corners = corners
        return InputOutlineTarget(frame: rect, contour: contour)
    }

    func read(pid: pid_t, anchor: CGPoint?, disabledPresets: Set<String> = [], primaryTop: CGFloat = 0, screens: [CGRect] = [], pinned: PromptDestination? = nil) async -> ReadResult {
        func inputTarget() async -> InputOutlineTarget? {
            guard let frame = reader.read(pid: pid, anchor: anchor, disabledPresets: disabledPresets, pinned: pinned) else { return nil }
            let estimate = InputOutlineTarget(frame: frame, contour: reader.contour ?? InputContour(rect: CGRect(origin: .zero, size: frame.size), radius: reader.cornerRadius, style: reader.cornerStyle), kind: reader.targetKind)
            let target = await measured(estimate, pid: pid)
            guard screens.isEmpty || target.onScreens(primaryTop: primaryTop, screens: screens) != nil else { return nil }
            return target
        }
        if let target = await inputTarget() { return .found(target) }
        // A moving input needs a fresh sample now. Missing AX trees retain the
        // short recovery interval before switching to the fallback indicator.
        if !reader.geometryChangedDuringRead {
            do { try await Task.sleep(nanoseconds: 80_000_000) }
            catch { return .unavailable }
        }
        guard !Task.isCancelled else { return .unavailable }
        if let target = await inputTarget() { return .found(target) }
        return reader.geometryChangedDuringRead ? .geometryChanging : .unavailable
    }
}

@MainActor final class FocusedInputTracker {
    static let refreshInterval: TimeInterval = 1.0 / 60
    private let reader = FocusedInputService()
    private var busy = false
    private var pendingRefresh: (() -> Void)?
    private var generation = 0
    private var mouseMonitor: Any?
    private var focusObserver: AXObserver?
    private var observedPID: pid_t?
    var onFocusChanged: (() -> Void)?
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
                self.onFocusChanged?()
            }
        }
    }

    deinit {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
    }

    private func observeFocus(pid: pid_t) {
        guard observedPID != pid else { return }
        if let focusObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes) }
        focusObserver = nil
        observedPID = nil
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let tracker = Unmanaged<FocusedInputTracker>.fromOpaque(context).takeUnretainedValue()
                tracker.generation += 1
                tracker.onFocusChanged?()
            }
        }, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, context)
        }
        focusObserver = observer
        observedPID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    func invalidate() { generation += 1; pendingRefresh = nil }

    func prepareAccessibility() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.raycast.macos" else { return }
        let pid = app.processIdentifier, reader = reader
        observeFocus(pid: pid)
        Task { await reader.prepareAccessibility(pid: pid) }
    }

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
        guard !busy else {
            pendingRefresh = { [weak self] in self?.refresh(disabledPresets: disabledPresets, completion: completion) }
            return
        }
        busy = true
        let pid = app.processIdentifier
        let request = generation
        let reader = self.reader
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrames = NSScreen.screens.map(\.frame)
        let click = lastClick.flatMap { click -> CGPoint? in
            guard click.pid == pid, ProcessInfo.processInfo.systemUptime - click.time < 60 else { return nil }
            return CGPoint(x: click.point.x, y: primaryTop - click.point.y)
        }
        Task { [weak self] in
            let result = await reader.read(pid: pid, anchor: click, disabledPresets: disabledPresets,
                primaryTop: primaryTop, screens: screenFrames)
            guard let self else { return }
            self.busy = false
            defer {
                let pending = self.pendingRefresh
                self.pendingRefresh = nil
                pending?()
            }
            guard request == self.generation else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                completion(nil, "Focus changed. Locating the active text field…")
                return
            }
            if case .geometryChanging = result { return }
            let screens = NSScreen.screens
            let converted = result.target?.onScreens(primaryTop: screens.first?.frame.maxY ?? 0, screens: screens.map(\.frame))
            let notice = converted == nil ? "Input unavailable. Using Bottom for now." : nil
            completion(converted, notice)
        }
    }

    func refreshPinned(_ task: Task<TextInsertion.Target?, Never>, disabledPresets: Set<String>, completion: @escaping (InputOutlineTarget?, String?) -> Void) {
        guard !busy else {
            pendingRefresh = { [weak self] in self?.refreshPinned(task, disabledPresets: disabledPresets, completion: completion) }
            return
        }
        busy = true
        let request = generation, reader = reader
        let top = NSScreen.screens.first?.frame.maxY ?? 0, screens = NSScreen.screens.map(\.frame)
        Task { [weak self] in
            let destination = await task.value?.promptDestination
            var result = FocusedInputService.ReadResult.unavailable
            if let destination {
                let visible = await Task.detached { PromptDestinationAccess.system.isVisible(destination) }.value
                if visible {
                    result = await reader.read(pid: destination.pid, anchor: nil, disabledPresets: disabledPresets,
                        primaryTop: top, screens: screens, pinned: destination)
                    let stillVisible = await Task.detached { PromptDestinationAccess.system.isVisible(destination) }.value
                    if !stillVisible { result = .unavailable }
                }
            }
            guard let self else { return }
            self.busy = false
            defer {
                let pending = self.pendingRefresh
                self.pendingRefresh = nil
                pending?()
            }
            guard request == self.generation else { return }
            if case .geometryChanging = result { return }
            completion(result.target?.onScreens(primaryTop: top, screens: screens), nil)
        }
    }
}
