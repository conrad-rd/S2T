import AppKit
import ApplicationServices
import SwiftUI
import S2TCore

@MainActor enum InputWindowFallbackProbe {
    static func run() async throws {
        let pid: pid_t = 2_940_000
        let app = AXUIElementCreateApplication(pid), window = AXUIElementCreateApplication(pid + 1)
        let field = AXUIElementCreateApplication(pid + 2), otherWindow = AXUIElementCreateApplication(pid + 3)
        var exposesField = false, secure = false, minimized = false, changesWindow = false, changesBounds = false
        var windowReads = 0, sizeReads = 0
        let bounds = CGRect(x: 50, y: 40, width: 1200, height: 800)
        var input = CGRect(x: 100, y: 500, width: 600, height: 100)
        var names = Set<String>()
        let reader = FocusedInputReader(attribute: { node, name in
            names.insert(name)
            if CFEqual(node, app) {
                if name == kAXFocusedWindowAttribute {
                    windowReads += 1
                    return changesWindow && windowReads > 1 ? otherWindow : window
                }
                if name == kAXFocusedUIElementAttribute { return exposesField ? field : nil }
                return nil
            }
            let isWindow = CFEqual(node, window)
            guard isWindow || CFEqual(node, field) else { return nil }
            let rect = isWindow ? bounds : input
            switch name {
            case kAXRoleAttribute: return (isWindow ? "AXWindow" : "AXTextArea") as CFString
            case kAXSubroleAttribute: return (!isWindow && secure ? "AXSecureTextField" : "") as CFString
            case kAXParentAttribute: return isWindow ? nil : window
            case kAXMinimizedAttribute: return minimized ? kCFBooleanTrue : kCFBooleanFalse
            case kAXPositionAttribute:
                var point = rect.origin
                return AXValueCreate(.cgPoint, &point)
            case kAXSizeAttribute:
                var size = rect.size
                if isWindow {
                    sizeReads += 1
                    if changesBounds && sizeReads > 1 { size.height += 20 }
                }
                return AXValueCreate(.cgSize, &size)
            default: return nil
            }
        }, children: { _ in [] }, fallbackFocus: { _ in nil }, hitTest: { _, _ in nil },
            applicationBundleID: { _ in "test.fallback" }, enableAccessibility: { _ in })
        let service = FocusedInputService(reader: reader, measuresPixels: false)
        let unavailable = await service.read(pid: pid, anchor: nil).target
        try check(unavailable == nil, "A missing field was replaced by the app window")
        exposesField = true
        let recovered = await service.read(pid: pid, anchor: nil).target
        try check(recovered?.kind == .input && recovered?.frame == input && (recovered?.cornerRadius ?? 0) > 0,
            "A located field was displaced because its border metadata was incomplete")
        input = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let oversized = await service.read(pid: pid, anchor: nil, primaryTop: 900,
            screens: [CGRect(x: 0, y: 0, width: 1440, height: 900)]).target
        try check(oversized == nil, "Oversized geometry produced a window-sized input target")
        input = CGRect(x: 100, y: 500, width: 600, height: 100)
        secure = true
        let secureTarget = await service.read(pid: pid, anchor: nil).target
        try check(secureTarget == nil, "Secure field produced an input target")
        secure = false; minimized = true
        try check(reader.read(pid: pid) == nil, "Minimized window retained its input target")
        minimized = false; changesWindow = true; windowReads = 0
        try check(reader.read(pid: pid) == nil, "Window change retained stale input geometry")
        changesWindow = false; changesBounds = true; sizeReads = 0
        try check(reader.read(pid: pid) == nil, "Window resize retained stale input geometry")
        try check(names.isDisjoint(with: [kAXValueAttribute, kAXSelectedTextAttribute, kAXTitleAttribute]), "Fallback requested text")
        try await verifyPlacement()
        print("PASS: missing fields return no target, detected fields retain rounded outlines, and secure/minimized/stale geometry is rejected. No app-window or displaced-field fallback.")
    }

    private static func verifyPlacement() async throws {
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let state = AppState(preview: true)
        state.glowAppearance = .aroundInput
        state.glowTuning = .init()
        state.glowMinimum = 0.3; state.glowMaximum = 2; state.glowWidth = 1; state.glowStrength = 0.8
        let fallback = GlowWindowController(state: state)
        let outline = InputOutlineWindowController(state: state)
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        for screen in screens {
            guard let bottom = fallback.prepareWindow(screens: screens, pointer: CGPoint(x: screen.frame.midX, y: screen.frame.midY)) else {
                throw failure("Missing screen-bottom fallback")
            }
            try check(bottom.frame.minY == screen.frame.minY && bottom.frame.width == screen.frame.width,
                "Fallback is anchored to an app window instead of the display")
            try check(!bottom.isVisible && bottom.ignoresMouseEvents && !bottom.canBecomeKey, "Fallback changed focus or visibility")
            for height in [CGFloat(32), 158] {
                for y in [screen.frame.minY + 24.5, screen.frame.midY, screen.frame.maxY - height - 50.5] {
                    let expected = CGRect(x: screen.frame.minX + 130.25, y: y, width: min(690.5, screen.frame.width - 260), height: height)
                    let ax = CGRect(x: expected.minX, y: primaryTop - expected.maxY, width: expected.width, height: expected.height)
                    guard let target = InputOutlineTarget(frame: ax, cornerRadius: 13.25, cornerStyle: .circular)
                        .onScreens(primaryTop: primaryTop, screens: screens.map(\.frame)) else { throw failure("AX coordinate conversion failed") }
                    let panel = outline.prepare(target: target)
                    panel.alphaValue = 0
                    panel.orderFrontRegardless()
                    defer { panel.orderOut(nil) }
                    try await Task.sleep(for: .milliseconds(30))
                    guard let root = panel.contentView as? ProgressiveBackdropView,
                          let native = root.profile?.inputOutline,
                          let host = root.subviews.first as? NSHostingView<InputOutline> else { throw failure("Missing native/color geometry") }
                    for contour in [native.contour, host.rootView.layout.contour] {
                        let actual = CGRect(x: panel.frame.minX + contour.bounds.minX,
                            y: panel.frame.maxY - contour.bounds.maxY, width: contour.bounds.width, height: contour.bounds.height)
                        try check(abs(actual.minX - expected.minX) < 0.001 && abs(actual.minY - expected.minY) < 0.001
                            && actual.size == expected.size && contour.main.radius == 13.25,
                            "Displayed panel shifted or reshaped the input. Actual \(actual), expected \(expected)")
                    }
                    try check(panel.alphaValue == 0 && panel.ignoresMouseEvents && !panel.canBecomeKey,
                        "Placement verification showed a window or intercepted input")
                }
            }
        }
        try check(NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground, "Verification changed focus")
        print("PASS: AX-to-display-to-shown-panel geometry stays anchored at top, middle and bottom across displays, including fractional coordinates and native/color corners. Windows remain invisible.")
    }

    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw failure(message) } }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "InputFallback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
