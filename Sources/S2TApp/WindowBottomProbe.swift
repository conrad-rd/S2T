import AppKit
import ApplicationServices
import SwiftUI
import S2TCore

@MainActor enum WindowBottomProbe {
    static func run() async throws {
        if CommandLine.arguments.contains("--benchmark-motion") { try benchmarkMotion(requireContinuous: false); return }
        let originalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        try await verifyTracking()
        try benchmarkMotion(requireContinuous: true)
        try await verifyHiddenPlacement()
        try verifyFields()
        try check(NSWorkspace.shared.frontmostApplication?.processIdentifier == originalPID, "Verification changed foreground focus")
        print("PASS: selected-window following, pinned starting identity, movement/resize, unavailable-window fallback, corner metadata, shared color/blur clipping and hidden nonactivating placement. No screen capture or real field reads.")
    }

    private static func benchmarkMotion(requireContinuous: Bool) throws {
        let state = AppState(preview: true)
        state.glowAppearance = .bottom
        let controller = GlowWindowController(state: state)
        let screens = NSScreen.screens
        guard let screen = screens.first else { throw failure("No display for generated movement") }
        let window = AXUIElementCreateApplication(2_980_001)
        let identity = BottomWindowIdentity(pid: 2_980_000, element: window)
        var rect = CGRect(x: screen.frame.minX + 100, y: 100, width: 700, height: 400)
        var movesDuringRead = false
        let reader = BottomWindowReader(attribute: { _, name in
            switch name {
            case kAXMinimizedAttribute: return kCFBooleanFalse
            case kAXPositionAttribute:
                if movesDuringRead { rect.origin.x += 1 }
                var value = rect.origin
                return AXValueCreate(.cgPoint, &value)
            case kAXSizeAttribute:
                var value = rect.size
                return AXValueCreate(.cgSize, &value)
            default: return nil
            }
        }, corners: { _ in [16, 16, 16, 16] })
        var missing = 0, resizes = 0, prior: CGSize?, times: [Double] = []
        for sample in 0..<120 {
            movesDuringRead = sample.isMultiple(of: 2)
            let start = CACurrentMediaTime()
            let frame = reader.read(identity, requireFocus: false, primaryTop: screen.frame.maxY, screens: screens.map(\.frame))
            if frame == nil { missing += 1 }
            guard let panel = controller.prepareWindow(screens: screens, pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY), window: frame),
                  !panel.isVisible else { throw failure("Generated movement displayed an overlay") }
            if let prior, prior != panel.frame.size { resizes += 1 }
            prior = panel.frame.size
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        times.sort()
        print(String(format: "120 generated moving-window reads: %d screen-bottom fallbacks, %d backing-size changes; native placement median %.3f ms, p95 %.3f ms. Hidden panels, not displayed FPS.",
            missing, resizes, times[60], times[114]))
        if requireContinuous { try check(missing == 0 && resizes == 0, "Window movement repeatedly resized Bottom into a screen-wide fallback") }
    }

    private static func verifyTracking() async throws {
        let pid: pid_t = 2_970_000
        let app = AXUIElementCreateApplication(pid)
        let first = AXUIElementCreateApplication(pid + 1), second = AXUIElementCreateApplication(pid + 2)
        var focused: AXUIElement? = first
        var firstBounds = CGRect(x: -900.25, y: 180.5, width: 700, height: 400)
        let secondBounds = CGRect(x: 60, y: 40, width: 900, height: 700)
        var minimized = false, closed = false, fullscreen = false, stale = false
        var reads = 0
        var names = Set<String>()
        let reader = BottomWindowReader(attribute: { element, name in
            names.insert(name)
            if CFEqual(element, app) { return name == kAXFocusedWindowAttribute ? focused : nil }
            let isFirst = CFEqual(element, first)
            if isFirst && closed { return nil }
            let rect = isFirst ? firstBounds : secondBounds
            switch name {
            case kAXRoleAttribute: return kAXWindowRole as CFString
            case kAXMinimizedAttribute: return (isFirst && minimized) ? kCFBooleanTrue : kCFBooleanFalse
            case "AXFullScreen": return fullscreen ? kCFBooleanTrue : kCFBooleanFalse
            case kAXPositionAttribute:
                reads += 1
                var point = rect.origin
                if stale && reads > 1 { point.x += 1 }
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = rect.size
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, corners: { _ in [16, 16, 16, 16] })
        let service = BottomWindowService(reader: reader)
        let screens = [CGRect(x: -1200, y: 0, width: 1200, height: 900), CGRect(x: 0, y: 0, width: 1440, height: 900)]
        guard let start = await service.capture(pid: pid) else { throw failure("Missing initial window") }
        func read(_ locked: Bool, pinned: BottomWindowIdentity? = nil) async -> BottomWindowFrame? {
            await service.read(pid: pid, pinned: pinned, lockToStart: locked, primaryTop: 900, screens: screens)
        }
        let initial = await read(false)
        try check(initial?.frame == CGRect(x: -900.25, y: 319.5, width: 700, height: 400), "Window coordinate conversion moved the bottom")
        focused = second
        let following = await read(false)
        let pinned = await read(true, pinned: start)
        try check(following?.frame.width == 900 && pinned == initial, "Switching windows did not distinguish following from pinning")
        firstBounds.origin.x += 41; firstBounds.size.width += 100
        let moved = await read(true, pinned: start)
        try check(moved?.frame.minX == -859.25 && moved?.frame.width == 800, "Pinned window did not move/resize")
        focused = nil
        let missing = await read(false), pinnedWithoutFocus = await read(true, pinned: start)
        try check(missing == nil && pinnedWithoutFocus == moved, "Missing focus lost the pinned starting identity")
        focused = second
        let uncaptured = await read(true)
        try check(uncaptured == nil, "A missing starting window rebound to the current window")
        minimized = true
        let minimizedFrame = await read(true, pinned: start)
        try check(minimizedFrame == nil, "Minimized window did not fall back")
        minimized = false; closed = true
        let closedFrame = await read(true, pinned: start)
        try check(closedFrame == nil, "Closed window did not fall back")
        closed = false; fullscreen = true
        let square = await read(true, pinned: start)
        try check(square?.leftRadius == 0 && square?.rightRadius == 0, "Fullscreen window gained corners")
        fullscreen = false; stale = true; reads = 0
        let staleFrame = await read(true, pinned: start)
        try check(staleFrame?.frame.minX == firstBounds.minX + 1 && staleFrame?.frame.width == firstBounds.width,
                  "Movement during sampling lost the same window instead of using its latest geometry")
        try check(names.isDisjoint(with: [kAXValueAttribute, kAXSelectedTextAttribute, kAXTitleAttribute, kAXChildrenAttribute]), "Window tracker inspected content")
    }

    private static func verifyHiddenPlacement() async throws {
        let state = AppState(preview: true)
        state.glowAppearance = .bottom
        let controller = GlowWindowController(state: state)
        let screens = NSScreen.screens
        guard let screen = screens.first else { throw failure("No display") }
        for style: NSWindow.StyleMask in [.borderless, [.titled, .resizable]] {
            let fixture = NSWindow(contentRect: NSRect(x: screen.frame.minX + 120, y: screen.frame.minY + 140, width: 480, height: 300),
                styleMask: style, backing: .buffered, defer: false)
            fixture.alphaValue = 0
            fixture.orderFrontRegardless()
            defer { fixture.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(100))
            guard let corners = WindowCornerMetadata.radii(windowID: CGWindowID(fixture.windowNumber)) else { throw failure("Native corner metadata unavailable") }
            try check(style.isEmpty ? corners.allSatisfy { $0 == 0 } : corners.allSatisfy { $0 > 0 }, "Native square/rounded window metadata differs")
            let target = BottomWindowFrame(frame: fixture.frame, leftRadius: corners[2], rightRadius: corners[3])
            guard let panel = controller.prepareWindow(screens: screens, pointer: CGPoint(x: screen.frame.maxX - 10, y: screen.frame.maxY - 10), window: target),
                  let root = panel.contentView as? ProgressiveBackdropView,
                  let layout = root.profile?.windowBottom else { throw failure("Missing window placement") }
            try check(panel.frame.minY == fixture.frame.minY && panel.frame.minX == fixture.frame.minX && panel.frame.width == fixture.frame.width,
                "Pointer displaced window-bound Bottom")
            try check(layout.leftRadius == corners[2] && layout.rightRadius == corners[3], "Native corner metadata was discarded")
            try check(panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.isVisible, "Placement activated or displayed a window")
        }
        for screen in screens {
            guard let fallback = controller.prepareWindow(screens: screens, pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY)) else { throw failure("Missing fallback") }
            try check(fallback.frame.minY == screen.frame.minY && fallback.frame.width == screen.frame.width,
                "Missing window did not use the display bottom")
            try check((fallback.contentView as? ProgressiveBackdropView)?.profile?.windowBottom == nil, "Fallback kept old corners")
        }
    }

    private static func verifyFields() throws {
        let size = CGSize(width: 180, height: 90)
        let layout = WindowBottomLayout(window: CGRect(origin: .zero, size: size), leftRadius: 26, rightRadius: 16, maximumHeight: size.height)
        var profile = GlowProfile(energy: 0.55, heights: [3])
        profile.windowBottom = layout
        profile.response.width = 1
        let geometry = profile.chromaGeometry
        for x in [2.0, 8, 90, 172, 178] {
            let edge = layout.boundaryY(at: x)
            try check(abs(geometry.distance(CGPoint(x: x, y: edge), size: size)) < 0.0001, "Color boundary missed the window corner")
        }
        guard let frame = ChromaFrame.render(.init(geometry: geometry, size: size, profile: profile, brightness: 0.55, backdrop: true)),
              let map = frame.radiusMap,
              let cg = map.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw failure("Window renderer produced no map") }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let scaleX = Double(bitmap.pixelsWide) / size.width, scaleY = Double(bitmap.pixelsHigh) / size.height
        func alpha(_ x: Double, _ y: Double) -> CGFloat {
            bitmap.colorAt(x: min(bitmap.pixelsWide - 1, Int(x * scaleX)), y: min(bitmap.pixelsHigh - 1, Int(y * scaleY)))?.alphaComponent ?? -1
        }
        try check(alpha(1, 89) < 0.01 && alpha(179, 89) < 0.01, "Native blur extends outside rounded corners")
        try check(alpha(90, 85) > 0.01, "Native blur lost the straight lower edge")
        try check(!layout.clipPath.contains(CGPoint(x: 1, y: 89)) && layout.clipPath.contains(CGPoint(x: 90, y: 85)), "Color clipping disagrees with native blur")
        profile.active = false
        let root = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
        root.profile = profile
        try check(root.profile?.windowBottom == layout, "Processing discarded the lower-corner geometry")
    }

    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw failure(message) } }
    private static func failure(_ message: String) -> NSError { NSError(domain: "WindowBottom", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
