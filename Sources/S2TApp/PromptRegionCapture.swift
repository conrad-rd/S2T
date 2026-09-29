import AppKit
import S2TCore

@MainActor final class PromptRegionCapture {
    enum Event { case down, drag, up }
    private var startPoint: CGPoint?
    private var cancelledDrag = false
    private var escapeDown = false
    private var gestureDisplays: [(cocoa: CGRect, quartz: CGRect)] = []
    private(set) var active = false
    private(set) var rect: CGRect?
    var onDrag: ((CGRect?) -> Void)?
    var onSelect: ((CGRect) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    /// Command-mouse-down. The gesture may still become a drag.
    var onPress: ((CGPoint) -> Void)?

    init(present: Bool = true) {}

    func start() { active = true }
    func stop() {
        active = false
        if startPoint != nil { cancelledDrag = true }
        startPoint = nil
        rect = nil
        onDrag?(nil)
    }

    func receive(type: CGEventType, event: CGEvent) -> Bool {
        if (type == .keyDown || type == .keyUp), event.getIntegerValueField(.keyboardEventKeycode) == 53, escapeDown {
            if type == .keyUp { escapeDown = false }
            return true
        }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53, startPoint != nil {
            startPoint = nil
            rect = nil
            cancelledDrag = true
            escapeDown = true
            onDrag?(nil)
            return true
        }
        let kind: Event
        switch type {
        case .leftMouseDown: kind = .down
        case .leftMouseDragged: kind = .drag
        case .leftMouseUp: kind = .up
        default: return false
        }
        guard cancelledDrag || (active && (startPoint != nil || (kind == .down && event.flags.contains(.maskCommand)))) else { return false }
        if kind == .down {
            gestureDisplays = NSScreen.screens.compactMap { screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
                return (screen.frame, CGDisplayBounds(id))
            }
        }
        let quartz = event.location
        let point: CGPoint
        if let screen = gestureDisplays.first(where: { $0.quartz.contains(quartz) }) ?? gestureDisplays.first {
            point = CGPoint(x: screen.cocoa.minX + quartz.x - screen.quartz.minX, y: screen.cocoa.maxY - (quartz.y - screen.quartz.minY))
        } else { point = quartz }
        return handle(kind, command: event.flags.contains(.maskCommand), location: point)
    }

    @discardableResult func handle(_ type: Event, command: Bool, location: CGPoint) -> Bool {
        if cancelledDrag {
            if type == .up { cancelledDrag = false }
            if type != .down { return true }
            cancelledDrag = false
        }
        guard active else { return false }
        switch type {
        case .down:
            guard command else { return false }
            startPoint = location
            rect = nil
            onDrag?(nil)
            onPress?(location)
            return true
        case .drag:
            guard let startPoint else { return false }
            let selection = Self.rectangle(startPoint, location)
            if max(selection.width, selection.height) >= 6 {
                rect = selection
                onDrag?(selection)
            }
            return true
        case .up:
            guard let startPoint else { return false }
            var selection = Self.rectangle(startPoint, location)
            // Keep the selection on the screen where it started; that is the screen it captures.
            if let screen = gestureDisplays.first(where: { $0.cocoa.contains(startPoint) })?.cocoa {
                selection = selection.intersection(screen)
                if selection.isNull { selection = CGRect(origin: startPoint, size: .zero) }
            }
            self.startPoint = nil
            rect = nil
            // A capture hands the outline straight to its flash; only an unusable shape clears it here.
            if selection.width >= 6, selection.height >= 6, let onSelect { onSelect(selection) }
            else if max(selection.width, selection.height) < 6, let onClick { onDrag?(nil); onClick(startPoint) }
            else { onDrag?(nil) }
            return true
        }
    }

    private static func rectangle(_ start: CGPoint, _ end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func verify() throws {
        let capture = PromptRegionCapture(present: false)
        var selected: [CGRect] = [], clicked: [CGPoint] = []
        var pressed: [CGPoint] = [], outline: [CGRect?] = []
        capture.onSelect = { selected.append($0) }
        capture.onClick = { clicked.append($0) }
        capture.onPress = { pressed.append($0) }
        capture.onDrag = { outline.append($0) }
        guard !capture.handle(.down, command: true, location: .zero) else { throw failure("Inactive gesture consumed a click") }
        capture.start()
        guard !capture.handle(.down, command: false, location: .zero) else { throw failure("Ordinary click was consumed") }
        capture.handle(.down, command: true, location: CGPoint(x: 100, y: 100))
        capture.handle(.drag, command: true, location: CGPoint(x: 60, y: 140))
        guard capture.rect == CGRect(x: 60, y: 100, width: 40, height: 40) else { throw failure("Reverse rectangle") }
        guard capture.handle(.up, command: false, location: CGPoint(x: 50, y: 150)),
              selected == [CGRect(x: 50, y: 100, width: 50, height: 50)], capture.rect == nil else { throw failure("Final pointer or released Command lost selection") }
        capture.handle(.down, command: true, location: CGPoint(x: -200, y: 900))
        capture.handle(.up, command: false, location: CGPoint(x: -198, y: 902))
        guard clicked == [CGPoint(x: -200, y: 900)] else { throw failure("Command-click with hand jitter") }
        guard pressed == [CGPoint(x: 100, y: 100), CGPoint(x: -200, y: 900)] else { throw failure("Command-press did not start the click capture early") }
        // Press, drag, completed drag (no clear), press, click (clear).
        guard outline == [nil, CGRect(x: 60, y: 100, width: 40, height: 40), nil, nil] else {
            throw failure("A completed drag cleared its outline before the capture flash: \(outline)")
        }
        capture.handle(.down, command: true, location: .zero)
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        guard capture.receive(type: .keyDown, event: escape), capture.receive(type: .keyUp, event: escape),
              capture.handle(.up, command: true, location: CGPoint(x: 80, y: 90)), selected.count == 1 else { throw failure("Escape failed to cancel only the rectangle") }
        capture.stop()
        guard !capture.handle(.down, command: true, location: .zero), !capture.active else { throw failure("Stop retained gesture") }
        print("Prompt gestures: click, jitter, all-direction drag, final pointer, Command release, Escape, inactive passthrough PASS. No posted events.")
    }
    static func benchmark() {
        let capture = PromptRegionCapture(present: false)
        capture.start()
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: CGPoint(x: 250, y: 250), mouseButton: .left)!
        let start = CACurrentMediaTime()
        for _ in 0..<1000 { _ = capture.receive(type: .leftMouseDragged, event: event) }
        print(String(format: "1000 ordinary window-drag events through Prompt capture: %.3f ms. Unposted events.", (CACurrentMediaTime() - start) * 1000))
    }
    private static func failure(_ message: String) -> Error { ServiceError.message(message) }
}
