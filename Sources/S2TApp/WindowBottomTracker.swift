import AppKit
import ApplicationServices
import S2TCore

struct BottomWindowIdentity {
    let pid: pid_t
    let element: AXUIElement
}

struct BottomWindowFrame: Equatable {
    let frame: CGRect
    let leftRadius: CGFloat
    let rightRadius: CGFloat

    func layout(maximumHeight: CGFloat) -> WindowBottomLayout {
        WindowBottomLayout(window: frame, leftRadius: leftRadius, rightRadius: rightRadius, maximumHeight: maximumHeight)
    }
}

// Resolve optional WindowServer metadata dynamically. No window images or titles are read.
enum WindowCornerMetadata {
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    static func radii(windowID: CGWindowID) -> [CGFloat]? {
        guard let connection = function("SLSMainConnectionID", as: (@convention(c) () -> Int32).self),
              let query = function("SLSWindowQueryWindows", as: (@convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?).self),
              let iterator = function("SLSWindowQueryResultCopyWindows", as: (@convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?).self),
              let advance = function("SLSWindowIteratorAdvance", as: (@convention(c) (CFTypeRef) -> Bool).self),
              let radii = function("SLSWindowIteratorGetResolvedCornerRadii", as: (@convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?).self),
              let result = query(connection(), [NSNumber(value: windowID)] as CFArray, 1)?.takeRetainedValue(),
              let cursor = iterator(result)?.takeRetainedValue(), advance(cursor),
              let values = radii(cursor)?.takeRetainedValue() as? [NSNumber], values.count == 4 else { return nil }
        let numbers = values.map { CGFloat($0.doubleValue) }
        return numbers.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 256 } ? numbers : nil
    }

    static func windowID(_ element: AXUIElement) -> CGWindowID? {
        typealias Read = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        let read = unsafeBitCast(symbol, to: Read.self)
        var id: CGWindowID = 0
        return read(element, &id) == .success && id != 0 ? id : nil
    }
}

final class BottomWindowReader {
    typealias Attribute = (AXUIElement, String) -> CFTypeRef?
    private let attribute: Attribute
    private let corners: (AXUIElement) -> [CGFloat]?

    init(attribute: @escaping Attribute = BottomWindowReader.systemAttribute,
         corners: @escaping (AXUIElement) -> [CGFloat]? = { WindowCornerMetadata.windowID($0).flatMap(WindowCornerMetadata.radii) }) {
        self.attribute = attribute
        self.corners = corners
    }

    static func systemAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    func capture(pid: pid_t) -> BottomWindowIdentity? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.08)
        guard attribute(element, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
        return BottomWindowIdentity(pid: pid, element: element)
    }

    func read(_ identity: BottomWindowIdentity, requireFocus: Bool, primaryTop: CGFloat, screens: [CGRect]) -> BottomWindowFrame? {
        let window = identity.element
        guard attribute(window, kAXMinimizedAttribute) as? Bool != true,
              let bounds = bounds(window), bounds.width >= 40, bounds.height >= 20 else { return nil }
        let radii = corners(window) ?? [0, 0, 0, 0]
        // Movement is a new frame, not a missing window. Use its latest geometry.
        guard let bounds = self.bounds(window), bounds.width >= 40, bounds.height >= 20,
              attribute(window, kAXMinimizedAttribute) as? Bool != true else { return nil }
        if requireFocus {
            guard let latest = capture(pid: identity.pid), CFEqual(latest.element, window) else { return nil }
        }
        let converted = CGRect(x: bounds.minX, y: primaryTop - bounds.maxY, width: bounds.width, height: bounds.height)
        // Do not relocate an offscreen lower edge to a different window or display edge.
        guard screens.contains(where: { $0.intersects(converted) && converted.minY >= $0.minY && converted.minY < $0.maxY }) else { return nil }
        let fullscreen = attribute(window, "AXFullScreen") as? Bool == true
        return BottomWindowFrame(frame: converted, leftRadius: fullscreen ? 0 : radii[2], rightRadius: fullscreen ? 0 : radii[3])
    }

    private func bounds(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

actor BottomWindowService {
    private let reader: BottomWindowReader
    init(reader: BottomWindowReader = BottomWindowReader()) { self.reader = reader }
    func capture(pid: pid_t) -> BottomWindowIdentity? { reader.capture(pid: pid) }
    func read(pid: pid_t?, pinned: BottomWindowIdentity?, lockToStart: Bool, primaryTop: CGFloat, screens: [CGRect]) -> BottomWindowFrame? {
        let identity = lockToStart ? pinned : pid.flatMap(reader.capture)
        guard let identity else { return nil }
        return reader.read(identity, requireFocus: !lockToStart, primaryTop: primaryTop, screens: screens)
    }
}

@MainActor final class WindowBottomTracker {
    private let service = BottomWindowService()
    private var startingWindow: Task<BottomWindowIdentity?, Never>?
    private var lockToStart = false
    private var startingApp: NSRunningApplication?
    private var generation = 0
    private var reading = false
    private var promptTarget: Task<TextInsertion.Target?, Never>?
    var pinsPromptDestination: Bool { promptTarget != nil }

    func begin(app: NSRunningApplication?, lockToStart: Bool) {
        promptTarget = nil
        generation += 1
        startingWindow?.cancel()
        startingApp = app
        self.lockToStart = lockToStart
        let service = service
        startingWindow = nil
        if lockToStart, let app, eligible(app), AXIsProcessTrusted() {
            let pid = app.processIdentifier
            startingWindow = Task { await service.capture(pid: pid) }
        }
    }

    func pin(to target: Task<TextInsertion.Target?, Never>) {
        generation += 1
        startingWindow?.cancel()
        promptTarget = target
        lockToStart = true
        startingWindow = Task { await target.value?.promptDestination?.bottomIdentity }
    }

    func invalidate() { generation += 1 }

    func refresh(completion: @escaping (BottomWindowFrame?) -> Void) {
        guard AXIsProcessTrusted() else { completion(nil); return }
        guard !reading else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? startingApp : front
        guard lockToStart || app.map(eligible) == true else { completion(nil); return }
        let pid = app?.processIdentifier
        let request = generation, locked = lockToStart, start = startingWindow, service = service, prompt = promptTarget
        let screens = NSScreen.screens.map(\.frame), top = NSScreen.screens.first?.frame.maxY ?? 0
        reading = true
        Task { [weak self] in
            let pinned = await start?.value
            let destination = await prompt?.value?.promptDestination
            let visible = if let destination { await Task.detached { PromptDestinationAccess.system.isVisible(destination) }.value } else { prompt == nil }
            let result = visible ? await service.read(pid: pid, pinned: pinned, lockToStart: locked, primaryTop: top, screens: screens) : nil
            guard let self else { return }
            self.reading = false
            guard request == self.generation else { return }
            guard locked || NSWorkspace.shared.frontmostApplication?.processIdentifier == front?.processIdentifier else { completion(nil); return }
            completion(result)
        }
    }

    private func eligible(_ app: NSRunningApplication) -> Bool {
        !app.isTerminated && app.processIdentifier != ProcessInfo.processInfo.processIdentifier && app.bundleIdentifier != "com.raycast.macos"
    }
}
