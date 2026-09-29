import AppKit
import ApplicationServices
import SwiftUI
import S2TCore

@MainActor enum InputOutlineProbe {
    static func run() async throws {
        let initialPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try verifyBackdropMaps()
        try verifyGeneratedColor()
        try await verifyBackdropTransparency()
        try await verifySpeechLifecycle()
        try InputPresetProbe.run()
        try verifyReader()
        try verifyClippedEditor()
        try await verifyTransientReadRecovery()
        try verifyComposerReader()
        try verifyComposerSelectControls()
        try verifyGeneralReader()
        try verifyAttachmentReader()
        try verifyPinnedReader()
        try verifyWindowDiscovery()
        let state = previewState()
        let saved = state.glowAppearance
        defer { state.glowAppearance = saved }
        let menu = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(menu.statusItem) }
        menu.menuNeedsUpdate(menu.menu)
        try InputAppearanceActionsProbe.verify(state: state, menu: menu)
        let controller = InputOutlineWindowController(state: state)
        var first: NSPanel?
        for screen in NSScreen.screens {
            let field = CGRect(x: screen.frame.midX - 280, y: screen.frame.midY, width: 560, height: 72)
            let panel = controller.prepare(field: field)
            if first == nil { first = panel }
            guard panel === first, panel.frame == InputOutlineGeometry(field: field).windowFrame,
                  !panel.canBecomeKey, !panel.canBecomeMain, panel.ignoresMouseEvents,
                  !panel.isOpaque, !panel.isVisible,
                  panel.contentView is ProgressiveBackdropView,
                  panel.contentView?.subviews.first is NSHostingView<InputOutline> else { throw failure("Outline window: actual \(panel.frame), expected \(InputOutlineGeometry(field: field).windowFrame), key \(panel.canBecomeKey), main \(panel.canBecomeMain), clicks \(panel.ignoresMouseEvents), opaque \(panel.isOpaque), visible \(panel.isVisible), host \(String(describing: panel.contentView)).") }
            panel.alphaValue = 0
            panel.contentView?.layoutSubtreeIfNeeded()
            guard let backdrop = panel.contentView as? ProgressiveBackdropView else { throw failure("Missing input backdrop root.") }
            let source = backdrop.subviews.first
            for phase in [DictationPhase.recording, .transcribing, .processing, .complete, .failed] {
                state.phase = phase
                try await Task.sleep(nanoseconds: 30_000_000)
                guard panel === controller.prepare(field: field), !panel.isVisible,
                      panel.contentView === backdrop, backdrop.subviews.first === source else { throw failure("Phase update replaced or showed hidden window.") }
            }
            let resized = field.insetBy(dx: -20, dy: -18).offsetBy(dx: 30, dy: -50)
            guard controller.prepare(field: resized).frame == InputOutlineGeometry(field: resized).windowFrame else {
                throw failure("Outline did not follow a moved or expanded input.")
            }
            guard (panel.contentView as? ProgressiveBackdropView)?.profile?.inputOutline?.rect == InputOutlineGeometry(field: resized).outlineRect else {
                throw failure("Resizing left the native blur on the previous input geometry until the next animation frame.")
            }
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            panel.orderFrontRegardless()
            try await Task.sleep(nanoseconds: 100_000_000)
            guard panel.alphaValue == 0, BackdropWindowHosting.isEnabled(in: panel),
                  panel.value(forKey: "hostsLayersInWindowServer") as? Bool == true,
                  backdrop.isBackdropAttached,
                  backdrop.profile?.inputOutline?.rect == InputOutlineGeometry(field: resized).outlineRect else {
                panel.orderOut(nil)
                throw failure("Input backdrop did not retain WindowServer hosting or resized contour geometry.")
            }
            panel.orderOut(nil)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == initialPID else { throw failure("Foreground application changed.") }
        print("PASS: input selection, parent traversal, secure/non-input rejection, geometry-only reads, Appearance actions and persistence, hidden click-through windows, display moves, resizing and phase reuse.")
        print("No applications activated, menus opened, or screen pixels captured. Visible appearance and live app compatibility are separate checks.")
    }

    private static func previewState() -> AppState {
        let state = AppState(preview: true)
        state.glowAppearance = .aroundInput
        state.glowTuning = .init()
        state.glowMinimum = 0.3
        state.glowMaximum = 2
        state.glowWidth = 1
        state.glowStrength = 0.8
        return state
    }

    private static func verifyGeneratedColor() throws {
        let state = previewState()
        state.phase = .recording
        state.glowStrength = 1
        let layout = InputOutlineLayout()
        layout.outlineRect = CGRect(x: 400, y: 400, width: 560, height: 180)
        layout.cornerRadius = 70
        let size = CGSize(width: 1360, height: 980)
        let view = InputOutline(state: state, layout: layout, reduceMotionOverride: true,
            levelProvider: { 0.55 }, spectrumProvider: { [] }, timeOverride: 1.7, reduceTransparencyOverride: true)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw failure("Generated input color fixture could not render.") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        func alpha(_ x: Int, _ y: Int) -> CGFloat { bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        guard alpha(680, 397) > alpha(680, 375), alpha(680, 375) >= alpha(680, 350),
              alpha(680, 397) > 0, alpha(680, 1) == 0, alpha(680, 480) == 0 else {
            throw failure("Chroma input color must fade outward, clear padding and preserve the interior. Samples: \([397, 375, 350, 1, 480].map { alpha(680, $0) })")
        }
        let shape = InputOutlineBackdrop(rect: layout.outlineRect, cornerRadius: layout.cornerRadius).path
        try GlowFixture.write(ZStack { shape.fill(.white); view }, size: size, name: "input")
        state.phase = .processing
        for index in 0..<4 {
            var processing = view
            processing.reduceMotionOverride = false
            processing.timeOverride = Double(index) * 0.7
            try GlowFixture.write(ZStack { shape.fill(.white); processing }, size: size, name: "input-processing-\(index)")
        }
        print("PASS: generated input color has a broad soft shoulder, fading tail, thin edge and clear interior.")
    }

    private static func verifyBackdropTransparency() async throws {
        let state = previewState()
        let layout = InputOutlineLayout()
        layout.outlineRect = CGRect(x: 116, y: 116, width: 400, height: 64)
        layout.cornerRadius = 32
        let panel = BackdropWindowHosting.makePanel()
        panel.setFrame(CGRect(x: 100, y: 100, width: 632, height: 296), display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let outline = InputOutline(state: state, layout: layout, reduceTransparencyOverride: false)
        let root = ProgressiveBackdropView.hosting(AnyView(outline))
        panel.contentView = root
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let preparationDeadline = CACurrentMediaTime() + 2
        while root.profile?.inputOutline == nil, CACurrentMediaTime() < preparationDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let color = root.subviews.first as? NSHostingView<AnyView>, root.profile?.inputOutline != nil else {
            throw failure("Input outline did not submit its backdrop profile.")
        }
        var reduced = outline
        reduced.reduceTransparencyOverride = true
        color.rootView = AnyView(reduced)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard root.profile == nil, color.superview === root else {
            throw failure("Reduce Transparency left the input backdrop active.")
        }
        color.rootView = AnyView(outline)
        try await Task.sleep(nanoseconds: 150_000_000)
        guard root.profile?.inputOutline != nil, root.isBackdropAttached, panel.alphaValue == 0 else {
            throw failure("Input backdrop did not recover after Reduce Transparency.")
        }
        print("PASS: input backdrop disables and restores through Reduce Transparency without replacing its color host.")
    }

    private static func verifySpeechLifecycle() async throws {
        let state = previewState()
        state.phase = .recording
        let layout = InputOutlineLayout()
        layout.outlineRect = CGRect(x: 116, y: 116, width: 400, height: 64)
        layout.cornerRadius = 32
        var level = 0.3
        var bands = [0.8, 0.2, 0.1, 0.1, 0.1, 0.1, 0.1]
        let panel = BackdropWindowHosting.makePanel()
        panel.setFrame(CGRect(x: 100, y: 100, width: 632, height: 296), display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let root = ProgressiveBackdropView.hosting(InputOutline(state: state, layout: layout,
            reduceMotionOverride: false, levelProvider: { level }, spectrumProvider: { bands },
            reduceTransparencyOverride: false))
        panel.contentView = root
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        try await Task.sleep(nanoseconds: 150_000_000)
        guard let sampler = root.layer?.sublayers?.first,
              let firstDistortion = root.profile?.distortion, !firstDistortion.isIdentity,
              (sampler.filters?.first as? NSObject)?.value(forKey: "inputRadius") as? Double == (root.profile?.chromaGeometry.maximumBlurRadius ?? -1) * (root.profile?.blurGain ?? -1) else {
            throw failure("Input did not submit its live spectrum and audio-driven blur.")
        }
        bands = [0.1, 0.1, 0.1, 0.1, 0.8, 0.2, 0.1]
        try await Task.sleep(nanoseconds: 100_000_000)
        guard root.profile?.distortion != firstDistortion, root.isBackdropAttached else {
            throw failure("Input spectrum did not refresh independently at the same volume.")
        }
        level = 0
        bands = []
        try await Task.sleep(nanoseconds: 70_000_000)
        guard (root.profile?.energy ?? 0) > 0.2, !sampler.isHidden else {
            throw failure("A short syllable pause blanked the input glow.")
        }
        level = 0.3
        bands = [0.1, 0.1, 0.1, 0.1, 0.8, 0.2, 0.1]
        try await Task.sleep(nanoseconds: 80_000_000)
        for phase in [DictationPhase.recording, .processing] {
            level = phase.busy ? 0.55 : 0
            bands = phase.busy ? [0.8, 0.2, 0.1, 0.1, 0.1, 0.1, 0.1] : []
            state.phase = phase
            try await Task.sleep(nanoseconds: phase.busy ? 100_000_000 : 520_000_000)
            let actualRadius = (sampler.filters?.first as? NSObject)?.value(forKey: "inputRadius") as? Double ?? -1
            let quietRadius = (root.profile?.chromaGeometry.maximumBlurRadius ?? -1) * GlowSpeechEnvelope.blurGain(0.3 * min(1, state.glowStrength / 1.3))
            guard root.profile?.energy == 0, root.profile?.distortion.isIdentity == true,
                  abs(actualRadius - (phase.busy ? 0 : quietRadius)) < 0.000001,
                  sampler.isHidden == phase.busy, root.isBackdropAttached else {
                throw failure("Input silence/processing state differs: energy \(root.profile?.energy ?? -1), identity \(root.profile?.distortion.isIdentity ?? false), radius \(actualRadius), expected \(phase.busy ? 0 : quietRadius), hidden \(sampler.isHidden).")
            }
        }
        state.phase = .recording
        level = 0.55
        bands = [0.1, 0.1, 0.1, 0.1, 0.8, 0.2, 0.1]
        try await Task.sleep(nanoseconds: 100_000_000)
        guard root.profile?.distortion.isIdentity == false, !sampler.isHidden, root.isBackdropAttached,
              panel.alphaValue == 0, !panel.canBecomeKey else {
            throw failure("Input did not restore speech after processing without replacing its sampler.")
        }
        if let color = root.subviews.first as? NSHostingView<InputOutline> {
            color.rootView.reduceMotionOverride = true
            level = 0.3
            try await Task.sleep(nanoseconds: 300_000_000)
            let quietEnergy = root.profile?.energy ?? 0
            level = 0.8
            try await Task.sleep(nanoseconds: 160_000_000)
            guard root.profile?.distortion.isIdentity == true, (root.profile?.energy ?? 0) > quietEnergy + 0.1 else {
                throw failure("Reduce Motion froze the input meter instead of only its deformation.")
            }
        }
        print("PASS: hidden input refreshes spectrum independently, uses the Chroma Box blur ceiling, retains quiet glow and clears blur during processing, and resumes on the same sampler.")
    }

    private static func verifyBackdropMaps() throws {
        for radius in [CGFloat(15), 125] {
            let size = CGSize(width: 1600, height: 1100)
            let rect = CGRect(x: 400, y: 400, width: 780, height: 250)
            let outline = InputOutlineBackdrop(rect: rect, cornerRadius: radius)
            guard let image = outline.mask(size: size),
                  let bitmap = image.representations.first as? NSBitmapImageRep,
                  image.size == size, bitmap.size == size else { throw failure("Could not generate the input backdrop map.") }
            func alpha(_ x: Int, _ y: Int) -> CGFloat { bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1 }
            for point in [(790, 500), (500, 500), (1050, 500)] {
                guard alpha(point.0, point.1) == 0 else { throw failure("Input text interior must remain unblurred.") }
            }
            for values in [[alpha(790, 397), alpha(790, 370), alpha(790, 300)],
                           [alpha(790, 653), alpha(790, 680), alpha(790, 750)],
                           [alpha(397, 525), alpha(370, 525), alpha(300, 525)],
                           [alpha(1183, 525), alpha(1210, 525), alpha(1280, 525)]] {
                guard values[0] > 0, values[0] >= values[1], values[1] >= values[2], values[0] > values[2] else {
                    throw failure("Chroma blur must taper outward on every side: \(values).")
                }
            }
            guard alpha(790, 1) == 0, alpha(1, 525) == 0, alpha(1598, 525) == 0 else {
                throw failure("The Box blur tail reaches its panel boundary.")
            }
        }
        print("PASS: Chroma Box native maps taper on all four sides, preserve image dimensions and exclude input interiors.")
    }

    private static func verifyTransientReadRecovery() async throws {
        for recovers in [true, false] {
            let app = AXUIElementCreateApplication(2_100_001)
            let field = AXUIElementCreateApplication(2_100_002)
            var attempts = 0
            var point = CGPoint(x: 100, y: 200)
            var size = CGSize(width: 600, height: 80)
            let position = AXValueCreate(.cgPoint, &point)!
            let dimensions = AXValueCreate(.cgSize, &size)!
            let reader = FocusedInputReader(attribute: { node, name in
                if CFEqual(node, app), name == kAXFocusedWindowAttribute { attempts += 1 }
                if CFEqual(node, app), name == kAXFocusedUIElementAttribute {
                    return recovers && attempts > 1 ? field : nil
                }
                guard CFEqual(node, field) else { return nil }
                switch name {
                case kAXRoleAttribute: return "AXTextArea" as CFString
                case kAXPositionAttribute: return position
                case kAXSizeAttribute: return dimensions
                default: return nil
                }
            }, children: { _ in [] }, fallbackFocus: { _ in nil },
                hitTest: { _, _ in nil }, enableAccessibility: { _ in })
            let service = FocusedInputService(reader: reader, measuresPixels: false)
            let target = await service.read(pid: 2_100_001, anchor: nil).target
            guard attempts == 2, target?.frame == (recovers ? CGRect(origin: point, size: size) : nil) else {
                throw failure("Transient AX failure must retry once before fallback, without retaining stale geometry.")
            }
        }
        print("PASS: temporary AX loss recovers before fallback; persistent loss returns no target after one retry.")
    }

    private static func verifyReader() throws {
        let app = AXUIElementCreateApplication(2_000_001)
        let field = AXUIElementCreateApplication(2_000_002)
        let child = AXUIElementCreateApplication(2_000_003)
        var point = CGPoint(x: 100, y: 200)
        var size = CGSize(width: 600, height: 80)
        let position = AXValueCreate(.cgPoint, &point)!
        let dimensions = AXValueCreate(.cgSize, &size)!
        for role in ["AXTextArea", "AXTextField", "AXComboBox", "AXGroup", "AXButton", "AXWebArea"] {
            for secure in [false, true] {
                var requests = [String]()
                let reader = FocusedInputReader(attribute: { node, name in
                    requests.append(name)
                    if CFEqual(node, app), name == kAXFocusedUIElementAttribute { return child }
                    if CFEqual(node, child) {
                        if name == kAXRoleAttribute { return "AXStaticText" as CFString }
                        if name == kAXParentAttribute { return field }
                        return nil
                    }
                    guard CFEqual(node, field) else { return nil }
                    switch name {
                    case kAXRoleAttribute: return role as CFString
                    case kAXSubroleAttribute: return (secure ? "AXSecureTextField" : "") as CFString
                    case "AXEditable": return (["AXGroup", "AXComboBox"].contains(role)) as CFBoolean
                    case kAXPositionAttribute: return position
                    case kAXSizeAttribute: return dimensions
                    default: return nil
                    }
                }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, enableAccessibility: { _ in })
                let actual = reader.read(pid: 2_000_001)
                let eligible = !secure && !["AXButton", "AXWebArea"].contains(role)
                guard actual == (eligible ? CGRect(origin: point, size: size) : nil),
                      !requests.contains(kAXValueAttribute), !requests.contains(kAXSelectedTextAttribute),
                      !requests.contains(kAXChildrenAttribute) else { throw failure("Focused input reader selected the wrong object or requested content.") }
            }
        }
    }

    private static func verifyComposerReader() throws {
        // Geometry recorded from the live T3 composer. No labels or text content.
        for growth in [CGFloat(0), 140] {
            for nestedToolbar in [false, true] {
                let frames = [
                    CGRect(x: 2114, y: 836, width: 605, height: 64 + growth),
                    CGRect(x: 2114, y: 836, width: 605, height: 64 + growth),
                    CGRect(x: 2114, y: 836, width: 605, height: 64 + growth),
                    CGRect(x: 2100, y: 822, width: 634, height: 85 + growth),
                    CGRect(x: 2099, y: 821, width: 635, height: 130 + growth),
                    CGRect(x: 1900, y: 100, width: 1000, height: 900),
                    CGRect(x: 2689, y: 906 + growth, width: 30, height: 30),
                    CGRect(x: 2105, y: 906 + growth, width: 614, height: 30)
                ]
                let nodes = frames.indices.map { AXUIElementCreateApplication(pid_t(2_100_010 + $0)) }
                func index(_ node: AXUIElement) -> Int? { nodes.firstIndex { CFEqual($0, node) } }
                var reads = [String]()
                var childReads = 0
                for includeControls in [true, false] {
                    let reader = FocusedInputReader(attribute: { node, name in
                        reads.append(name)
                        if name == kAXFocusedUIElementAttribute { return nodes[0] }
                        guard let i = index(node) else { return nil }
                        switch name {
                        case kAXRoleAttribute: return (i == 0 ? "AXTextArea" : i == 6 ? "AXButton" : "AXGroup") as CFString
                        case kAXParentAttribute: return i < 5 ? nodes[i + 1] : nil
                        case kAXPositionAttribute:
                            var point = frames[i].origin
                            return AXValueCreate(.cgPoint, &point)
                        case kAXSizeAttribute:
                            var size = frames[i].size
                            return AXValueCreate(.cgSize, &size)
                        default: return nil
                        }
                    }, children: { node in
                        childReads += 1
                        guard let i = index(node) else { return [] }
                        if i == 4 { return [nodes[3]] + (includeControls ? [nodes[nestedToolbar ? 7 : 6]] : []) }
                        if i == 7 { return [nodes[6]] }
                        return i > 0 && i < 5 ? [nodes[i - 1]] : []
                    }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, enableAccessibility: { _ in })
                    guard reader.read(pid: 2_100_000) == frames[includeControls ? 4 : 3] else {
                        throw failure("The T3 composer must include its footer, skip editor wrappers, and reject the page container. Plain fields must remain unchanged.")
                    }
                }
                guard childReads <= 24, !reads.contains(kAXValueAttribute), !reads.contains(kAXSelectedTextAttribute) else {
                    throw failure("Composer discovery exceeded its local metadata budget or requested text.")
                }
            }
        }
        print("PASS: measured composer fixture includes direct/nested footer controls, follows input growth, rejects the page, and preserves standalone editor boundaries.")
    }

    private static func verifyComposerSelectControls() throws {
        for growth in [CGFloat(0), 140] {
            for editableControl in [false, true] {
                let frames = [
                    CGRect(x: 2114, y: 837, width: 606, height: 64 + growth),
                    CGRect(x: 2100, y: 823, width: 635, height: 85 + growth),
                    CGRect(x: 2099, y: 822, width: 636, height: 130 + growth),
                    CGRect(x: 2340, y: 909 + growth, width: 121, height: 26),
                    CGRect(x: 2690, y: 907 + growth, width: 30, height: 30),
                    CGRect(x: 2340, y: 909 + growth, width: 121, height: 26)
                ]
                let roles = ["AXTextArea", "AXGroup", "AXGroup", "AXComboBox", "AXButton", "AXStaticText"]
                let descendants = [[], [0], [1, 3, 4], [5], [], []]
                let parents: [Int?] = [1, 2, nil, 2, 2, 3]
                let elements = frames.indices.map { AXUIElementCreateApplication(pid_t(2_500_010 + $0)) }
                func index(_ element: AXUIElement) -> Int? { elements.firstIndex { CFEqual($0, element) } }
                var requested = [String]()
                let reader = FocusedInputReader(attribute: { element, name in
                    requested.append(name)
                    if name == kAXFocusedUIElementAttribute { return elements[0] }
                    guard let i = index(element) else { return nil }
                    switch name {
                    case kAXRoleAttribute: return roles[i] as CFString
                    case kAXParentAttribute: return parents[i].map { elements[$0] }
                    case "AXEditableAncestor": return editableControl && (i == 3 || i == 5) ? elements[3] : nil
                    case kAXPositionAttribute:
                        var point = frames[i].origin
                        return AXValueCreate(.cgPoint, &point)
                    case kAXSizeAttribute:
                        var size = frames[i].size
                        return AXValueCreate(.cgSize, &size)
                    default: return nil
                    }
                }, children: { element in index(element).map { descendants[$0].map { elements[$0] } } },
                    fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, enableAccessibility: { _ in })
                let expected = frames[editableControl ? 1 : 2]
                guard reader.read(pid: 2_500_000) == expected else {
                    throw failure("A select control must belong to its composer; an independently editable combo box must prevent expansion.")
                }
                if !editableControl, reader.cornerRadius != 15 {
                    throw failure("Full composer corners must use its 15-point content spacing and remain stable as text grows.")
                }
                guard !requested.contains(kAXValueAttribute), !requested.contains(kAXSelectedTextAttribute),
                      !requested.contains(kAXSelectedTextRangeAttribute) else {
                    throw failure("Input classification requested text or selection values.")
                }
            }
        }
        print("PASS: select controls belong to the full composer, editable combo boxes remain independent, and content-based corners stay stable during growth.")
    }

    private static func verifyGeneralReader() throws {
        let input = CGRect(x: 200, y: 400, width: 300, height: 28)
        let bounds = CGRect(x: 140, y: 386, width: 420, height: 58)
        for (hostRole, hostEditable) in [("AXGroup", false), ("AXGroup", true), ("AXComboBox", false), ("AXComboBox", true)] {
            let nodes = [
                ComposerNode(id: 0, role: "AXTextArea", frame: input, parent: 1),
                ComposerNode(id: 1, role: hostRole, editable: hostEditable, frame: input, parent: 2, children: [0]),
                ComposerNode(id: 2, role: "AXForm", frame: bounds, parent: nil, children: [1, 3]),
                ComposerNode(id: 3, role: "AXGroup", frame: nil, parent: 2, children: [4, 5]),
                ComposerNode(id: 4, role: "AXButton", frame: CGRect(x: 150, y: 398, width: 30, height: 30), parent: 3),
                ComposerNode(id: 5, role: "AXButton", frame: CGRect(x: 520, y: 398, width: 30, height: 30), parent: 3)
            ]
            let elements = nodes.map { AXUIElementCreateApplication(pid_t(2_200_010 + $0.id)) }
            func index(_ element: AXUIElement) -> Int? { elements.firstIndex { CFEqual($0, element) } }
            for focusedContainer in [false, true] {
                for changeFocus in [false, true] {
                    var focusReads = 0
                    var controlOffset: CGFloat = 0
                    let reader = FocusedInputReader(attribute: { element, attribute in
                        if attribute == kAXFocusedUIElementAttribute {
                            focusReads += 1
                            return elements[changeFocus && focusReads > 1 ? 5 : focusedContainer ? 1 : 0]
                        }
                        guard let i = index(element) else { return nil }
                        let node = nodes[i]
                        switch attribute {
                        case kAXRoleAttribute: return node.role as CFString
                        case "AXEditable": return node.editable as CFBoolean
                        case kAXParentAttribute: return node.parent.map { elements[$0] }
                        case kAXPositionAttribute:
                            guard var point = node.frame?.origin else { return nil }
                            if i == 4 || i == 5 { point.y += controlOffset }
                            return AXValueCreate(.cgPoint, &point)
                        case kAXSizeAttribute:
                            guard var size = node.frame?.size else { return nil }
                            return AXValueCreate(.cgSize, &size)
                        default: return nil
                        }
                    }, children: { element in index(element).map { nodes[$0].children.map { elements[$0] } } },
                        fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, enableAccessibility: { _ in })
                    guard reader.read(pid: 2_200_000) == (changeFocus ? nil : bounds) else {
                        throw failure("Generic targeting failed for a focused container, frameless toolbar, side controls, or stale focus.")
                    }
                    if !changeFocus {
                        guard reader.cornerRadius == bounds.height / 2,
                              reader.read(pid: 2_200_000) == bounds,
                              reader.cornerRadius == bounds.height / 2 else {
                            throw failure("A centered input row without search metadata must retain capsule corners across cached reads.")
                        }
                        controlOffset = 10
                        guard reader.read(pid: 2_200_000) == bounds, reader.cornerRadius == 14 else {
                            throw failure("Unchanged field bounds retained capsule corners after its controls moved into a footer.")
                        }
                        controlOffset = 0
                        guard reader.read(pid: 2_200_000) == bounds, reader.cornerRadius == bounds.height / 2 else {
                            throw failure("Returning controls to the centered row did not restore capsule corners.")
                        }
                    }
                }
            }
        }
        print("PASS: shared adapter resolves focused fields and containers, frameless toolbars, controls on both sides, non-search capsule corners across cached reads, and rejects stale focus.")
    }

    private static func verifyAttachmentReader() throws {
        let frames = [CGRect(x: 100, y: 150, width: 500, height: 50), CGRect(x: 88, y: 70, width: 524, height: 185),
                      CGRect(x: 100, y: 82, width: 220, height: 54), CGRect(x: 112, y: 102, width: 140, height: 18),
                      CGRect(x: 282, y: 90, width: 26, height: 26), CGRect(x: 565, y: 215, width: 30, height: 30)]
        let roles = ["AXTextArea", "AXGroup", "AXList", "AXStaticText", "AXButton", "AXButton"]
        let descendants = [[], [0, 2, 5], [3, 4], [], [], []]
        let parents: [Int?] = [1, nil, 1, 2, 2, 1]
        let elements = frames.indices.map { AXUIElementCreateApplication(pid_t(2_400_010 + $0)) }
        func index(_ element: AXUIElement) -> Int? { elements.firstIndex { CFEqual($0, element) } }
        var requested = [String]()
        let reader = FocusedInputReader(attribute: { element, name in
            requested.append(name)
            if name == kAXFocusedUIElementAttribute { return elements[0] }
            guard let i = index(element) else { return nil }
            switch name {
            case kAXRoleAttribute: return roles[i] as CFString
            case kAXParentAttribute: return parents[i].map { elements[$0] }
            case kAXPositionAttribute:
                var point = frames[i].origin
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = frames[i].size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in index(element).map { descendants[$0].map { elements[$0] } } },
            fallbackFocus: { _ in nil }, hitTest: { _, _ in nil }, enableAccessibility: { _ in })
        guard reader.read(pid: 2_400_000) == frames[1],
              !requested.contains(kAXValueAttribute), !requested.contains(kAXSelectedTextAttribute) else {
            throw failure("Attachment metadata did not reach the shared boundary resolver without reading content.")
        }
        print("PASS: attachment controls and labels contribute to the full container through the production metadata reader; no text contents read.")
    }

    private static func verifyPinnedReader() throws {
        let pid: pid_t = 2_950_000
        let window = AXUIElementCreateApplication(pid + 1), field = AXUIElementCreateApplication(pid + 2)
        let other = AXUIElementCreateApplication(pid + 3)
        var bounds = CGRect(x: 120, y: 180, width: 480, height: 80)
        var invalid = false
        let reader = FocusedInputReader(attribute: { node, name in
            if name == kAXFocusedUIElementAttribute || name == kAXFocusedWindowAttribute { return other }
            let isField = CFEqual(node, field), isWindow = CFEqual(node, window)
            guard isField || isWindow else { return nil }
            let frame = isField ? bounds : CGRect(x: 50, y: 50, width: 800, height: 600)
            switch name {
            case kAXRoleAttribute: return (isField ? "AXTextArea" : "AXWindow") as CFString
            case kAXParentAttribute: return isField ? window : nil
            case kAXSubroleAttribute: return invalid && isField ? "AXSecureTextField" as CFString : nil
            case kAXFocusedAttribute: return kCFBooleanFalse
            case kAXPositionAttribute: var point = frame.origin; return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute: var size = frame.size; return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { CFEqual($0, window) ? [field] : [] }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil },
            applicationBundleID: { _ in "fixture" }, enableAccessibility: { _ in })
        let destination = PromptDestination(pid: pid, window: window, field: field, document: nil, tab: nil, selection: nil)
        guard reader.read(pid: pid, pinned: destination) == bounds else { throw failure("Pinned input followed another window's focus") }
        bounds = bounds.offsetBy(dx: 37, dy: 18)
        guard reader.read(pid: pid, pinned: destination) == bounds else { throw failure("Pinned input did not follow its own geometry") }
        invalid = true
        guard reader.read(pid: pid, pinned: destination) == nil else { throw failure("Pinned input accepted a secure field") }
        print("Pinned processing geometry: original field survives unrelated focus, follows movement and rejects secure fields PASS with injected metadata.")
    }

    private static func verifyWindowDiscovery() throws {
        let nodes = [
            ComposerNode(id: 0, role: "AXWindow", frame: CGRect(x: 100, y: 100, width: 1000, height: 800), parent: nil, children: [3, 4]),
            ComposerNode(id: 1, role: "AXTextArea", frame: CGRect(x: 300, y: 825, width: 650, height: 38), parent: 3),
            ComposerNode(id: 2, role: "AXComboBox", frame: CGRect(x: 800, y: 180, width: 180, height: 22), parent: 4),
            ComposerNode(id: 3, role: "AXGroup", frame: CGRect(x: 250, y: 815, width: 750, height: 60), parent: 0, children: [1, 5, 7]),
            ComposerNode(id: 4, role: "AXGroup", subrole: "AXLandmarkSearch", frame: CGRect(x: 790, y: 170, width: 220, height: 42), parent: 0, children: [2, 6]),
            ComposerNode(id: 5, role: "AXButton", frame: CGRect(x: 950, y: 830, width: 30, height: 30), parent: 3),
            ComposerNode(id: 6, role: "AXButton", frame: CGRect(x: 985, y: 180, width: 20, height: 20), parent: 4),
            ComposerNode(id: 7, role: "AXButton", frame: CGRect(x: 260, y: 830, width: 30, height: 30), parent: 3)
        ]
        let elements = nodes.map { AXUIElementCreateApplication(pid_t(2_300_010 + $0.id)) }
        func index(_ element: AXUIElement) -> Int? { elements.firstIndex { CFEqual($0, element) } }
        var hitCount = 0
        var requested = [String]()
        let reader = FocusedInputReader(attribute: { element, name in
            requested.append(name)
            if name == kAXFocusedUIElementAttribute { return nil }
            if name == kAXFocusedWindowAttribute { return elements[0] }
            guard let i = index(element) else { return nil }
            let node = nodes[i]
            switch name {
            case kAXRoleAttribute: return node.role as CFString
            case kAXSubroleAttribute: return node.subrole as CFString
            case "AXEditableAncestor": return i == 2 ? elements[2] : nil
            case kAXParentAttribute: return node.parent.map { elements[$0] }
            case kAXPositionAttribute:
                guard var point = node.frame?.origin else { return nil }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                guard var size = node.frame?.size else { return nil }
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { element in index(element).map { nodes[$0].children.map { elements[$0] } } },
            fallbackFocus: { _ in nil }, hitTest: { _, point in
                hitCount += 1
                if nodes[3].frame!.contains(point) { return elements[3] }
                if nodes[4].frame!.contains(point) { return elements[4] }
                return nil
            }, enableAccessibility: { _ in })
        guard reader.read(pid: 2_300_000) == nodes[3].frame, hitCount <= 28 else {
            throw failure("Window discovery did not locate the main editor when both focus APIs returned nothing.")
        }
        let initialHits = hitCount
        guard reader.read(pid: 2_300_000) == nodes[3].frame, hitCount == initialHits else {
            throw failure("Stable discovery repeated a full window search instead of reusing its editor.")
        }
        guard reader.read(pid: 2_300_000, anchor: CGPoint(x: 820, y: 185)) == nodes[4].frame,
              reader.cornerRadius == InputOutlineGeometry.radius(for: nodes[4].frame!.size, capsule: true),
              !requested.contains(kAXValueAttribute), !requested.contains(kAXSelectedTextRangeAttribute) else {
            throw failure("Interaction did not redirect discovery to an editable combo box, or text selection values were requested.")
        }
        print("PASS: missing-focus window search, bounded hit testing, dominant editor selection, cached reads, click redirection, editable-ancestor combo box input, and search-field shape.")
    }

    private static func verifyClippedEditor() throws {
        let pid: pid_t = 2_955_000
        let app = AXUIElementCreateApplication(pid)
        let editor = AXUIElementCreateApplication(pid + 1)
        let viewport = AXUIElementCreateApplication(pid + 2)
        let input = CGRect(x: 400, y: 80, width: 400, height: 500)
        let visible = CGRect(x: 0, y: 100, width: 1200, height: 100)
        var moves = false, viewportReads = 0
        let reader = FocusedInputReader(attribute: { node, name in
            if CFEqual(node, app) { return name == kAXFocusedUIElementAttribute ? editor : nil }
            let isEditor = CFEqual(node, editor)
            switch name {
            case kAXRoleAttribute: return (isEditor ? "AXTextArea" : "AXScrollArea") as CFString
            case kAXParentAttribute: return isEditor ? viewport : nil
            case kAXPositionAttribute:
                var point = isEditor ? input.origin : visible.origin
                if !isEditor { viewportReads += 1; if moves && viewportReads > 1 { point.y += 5 } }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = isEditor ? input.size : visible.size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { CFEqual($0, viewport) ? [editor] : [] }, fallbackFocus: { _ in nil },
           hitTest: { _, _ in nil }, applicationBundleID: { _ in "test.clipped-editor" }, enableAccessibility: { _ in })
        try checkClipped(reader.read(pid: pid) == input.intersection(visible), "Clipped editor lost its visible field fallback")
        moves = true; viewportReads = 0
        try checkClipped(reader.read(pid: pid) == nil, "Moving viewport kept stale clipped geometry")
        print("PASS: clipped editor fallback validates both the editor and its viewport without reading text.")
    }

    private static func checkClipped(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }

    static func inspectFocusedInput() async {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != "com.raycast.macos",
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            print("Live input check skipped: no eligible foreground app.")
            return
        }
        print("Foreground: \(app.localizedName ?? "unknown"). Accessibility permission: \(AXIsProcessTrusted()).")
        guard AXIsProcessTrusted() else { return }
        let pid = app.processIdentifier
        let target = await Task.detached { () -> InputOutlineTarget? in
            let reader = FocusedInputReader()
            guard let frame = reader.read(pid: pid), let contour = reader.contour else { return nil }
            print("Target kind: \(reader.targetKind), corners: \(reader.cornerRadius), style: \(reader.cornerStyle), calibration: \(String(describing: reader.usedPreset))")
            return InputOutlineTarget(frame: frame, contour: contour, kind: reader.targetKind)
        }.value
        if let target {
            print("Outline target bounds: \(target.frame). No text was read.")
            let screens = NSScreen.screens.map(\.frame)
            if let converted = target.onScreens(primaryTop: screens.first?.maxY ?? 0, screens: screens) {
                let state = previewState()
                let controller = InputOutlineWindowController(state: state)
                let panel = controller.prepare(target: converted)
                if let contour = (panel.contentView as? ProgressiveBackdropView)?.profile?.inputOutline?.contour {
                    let actual = CGRect(x: panel.frame.minX + contour.bounds.minX,
                        y: panel.frame.maxY - contour.bounds.maxY, width: contour.bounds.width, height: contour.bounds.height)
                    print("AppKit target: \(converted.frame); hidden rendered bounds: \(actual); panel: \(panel.frame)")
                }
            }
        }
        else { print("No usable focused input exposed. Around Input will use Bottom.") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "InputOutlineProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
