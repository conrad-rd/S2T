import AppKit

final class ShortcutEventTap: @unchecked Sendable {
    private let receive: @MainActor (CGEventType, CGEvent) -> Bool
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var stopped = false
    private var pendingDrag: CGEvent?
    private var dragScheduled = false
    private var capturesMouse = false
    private var port: CFMachPort?
    private var keyCodes: Set<UInt16>?
    private var observesOtherKeys = true
    private var pendingKeyboardObservations = 0
    private var commandClicks = true
    private var dragObserver: (@Sendable (CGPoint) -> Void)?

    /// Receives each captured ⌘-drag position on the tap thread, before main-thread coalescing,
    /// so the selection outline follows the pointer even while the main thread is drawing.
    func setDragObserver(_ observer: (@Sendable (CGPoint) -> Void)?) {
        lock.lock(); dragObserver = observer; lock.unlock()
    }

    init(receive: @escaping @MainActor (CGEventType, CGEvent) -> Bool) { self.receive = receive }

    // Only events that the shortcut can consume need a synchronous decision.
    // Publish this small snapshot from the main thread; ordinary typing must not
    // wait behind AppKit layout or an appearance frame.
    func configureRouting(keyCodes: Set<UInt16>?, observesOtherKeys: Bool, commandClicks: Bool) {
        lock.lock()
        self.keyCodes = keyCodes
        self.observesOtherKeys = observesOtherKeys
        self.commandClicks = commandClicks
        lock.unlock()
    }

    func start(mask: CGEventMask) -> CFMachPort? {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<ShortcutEventTap>.fromOpaque(pointer).takeUnretainedValue()
                return tap.route(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: pointer) else { return nil }
        self.port = port
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return }
            lock.lock()
            runLoop = loop
            let shouldRun = !stopped
            if shouldRun { CFRunLoopAddSource(loop, source, .commonModes) }
            lock.unlock()
            if shouldRun { CFRunLoopRun() }
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "com.s2t.shortcuts"
        thread.qualityOfService = .userInteractive
        thread.start()
        return port
    }

    func stop() {
        lock.lock()
        stopped = true
        pendingDrag = nil
        let loop = runLoop
        lock.unlock()
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let loop { CFRunLoopStop(loop) }
    }

    // Ordinary mouse events never wait for drawing, layout, or clipboard work on the main thread.
    func route(type: CGEventType, event: CGEvent) -> Bool {
        lock.lock()
        let stopped = stopped, keyCodes = keyCodes,
            observesOtherKeys = observesOtherKeys || pendingKeyboardObservations > 0, commandClicks = commandClicks
        lock.unlock()
        guard !stopped else { return false }
        switch type {
        case .leftMouseDown:
            capturesMouse = commandClicks && event.flags.contains(.maskCommand) && onMain(type, event)
            return capturesMouse
        case .leftMouseDragged:
            guard capturesMouse else { return false }
            lock.lock()
            let observer = dragObserver
            lock.unlock()
            observer?(event.location)
            lock.lock()
            pendingDrag = event.copy()
            let schedule = !dragScheduled
            dragScheduled = true
            lock.unlock()
            if schedule {
                DispatchQueue.main.async { [self] in
                    lock.lock()
                    let event = pendingDrag
                    pendingDrag = nil; dragScheduled = false
                    let stopped = stopped
                    lock.unlock()
                    if !stopped, let event { _ = receive(.leftMouseDragged, event) }
                }
            }
            return true
        case .leftMouseUp:
            guard capturesMouse else { return false }
            capturesMouse = false
            if let copy = event.copy() {
                DispatchQueue.main.async { [self] in
                    lock.lock(); let stopped = stopped; lock.unlock()
                    if !stopped { _ = receive(.leftMouseUp, copy) }
                }
            }
            return true
        case .keyDown, .keyUp, .flagsChanged:
            if event.getIntegerValueField(.eventSourceUserData) == TextInsertion.eventMarker { return false }
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isModifier = type == .flagsChanged
            if isModifier || keyCodes.map({ !$0.contains(code) }) == true {
                // Interrupting a held shortcut or Escape never consumes this key.
                // Queue that state transition before any later shortcut decision.
                // Modifier flags (including Fn) always pass through so system
                // combinations keep working, even during an AppKit stall.
                if (observesOtherKeys || isModifier && (keyCodes?.contains(code) ?? true)), let copy = event.copy() {
                    // A queued Fn press has not updated the routing snapshot yet.
                    // Keep observing its following keys until the queue catches up,
                    // so a fast Fn combination still interrupts hold-to-talk.
                    lock.lock(); pendingKeyboardObservations += 1; lock.unlock()
                    DispatchQueue.main.async { [self] in
                        lock.lock(); let stopped = stopped; lock.unlock()
                        if !stopped { _ = receive(type, copy) }
                        lock.lock(); pendingKeyboardObservations -= 1; lock.unlock()
                    }
                }
                return false
            }
            return onMain(type, event)
        default:
            return onMain(type, event)
        }
    }

    private func onMain(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if Thread.isMainThread { return MainActor.assumeIsolated { receive(type, event) } }
        return DispatchQueue.main.sync { receive(type, event) }
    }
}
