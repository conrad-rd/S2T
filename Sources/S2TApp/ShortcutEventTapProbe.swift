import AppKit
import S2TCore

@MainActor enum ShortcutEventTapProbe {
    static func run() async throws {
        try await verifyKeyboardRouting()
        let capture = PromptRegionCapture(present: false)
        capture.start()
        var delivered: [CGEventType] = []
        var selected: CGRect?
        capture.onSelect = { selected = $0 }
        let tap = ShortcutEventTap { type, event in
            delivered.append(type)
            return capture.receive(type: type, event: event)
        }
        defer { tap.stop() }
        func mouse(_ type: CGEventType, _ x: Double, command: Bool = false) -> CGEvent {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: x), mouseButton: .left)!
            event.flags = command ? .maskCommand : []
            return event
        }
        let drag = mouse(.leftMouseDragged, 150)
        func blockedMainLatency(legacy: Bool) async -> Double {
            let ready = DispatchSemaphore(value: 0)
            let task = Task.detached { () -> Double in
                let start = CACurrentMediaTime()
                ready.signal()
                if legacy { _ = DispatchQueue.main.sync { capture.receive(type: .leftMouseDragged, event: drag) } }
                else { _ = tap.route(type: .leftMouseDragged, event: drag) }
                return (CACurrentMediaTime() - start) * 1000
            }
            blockMain(until: ready)
            return await task.value
        }
        let before = await blockedMainLatency(legacy: true)
        let after = await blockedMainLatency(legacy: false)
        guard before >= 70, after < 20, delivered.isEmpty else { throw failure("Ordinary window dragging waited for the main thread") }
        print(String(format: "Unposted window drag with 80 ms of main-thread work: former routing %.3f ms, current routing %.3f ms.", before, after))
        guard !tap.route(type: .leftMouseDown, event: mouse(.leftMouseDown, 100)) else { throw failure("Ordinary click consumed") }
        guard tap.route(type: .leftMouseDown, event: mouse(.leftMouseDown, 100, command: true)) else { throw failure("Capture click escaped") }
        for index in 0..<1000 {
            guard tap.route(type: .leftMouseDragged, event: mouse(.leftMouseDragged, 110 + Double(index) / 10)) else { throw failure("Capture drag escaped") }
        }
        guard tap.route(type: .leftMouseUp, event: mouse(.leftMouseUp, 250)) else { throw failure("Released Command lost the captured mouse-up") }
        try await Task.sleep(nanoseconds: 20_000_000)
        guard delivered == [.leftMouseDown, .leftMouseDragged, .leftMouseUp], selected?.size == CGSize(width: 150, height: 150) else {
            throw failure("Queued drag positions replayed or changed the release rectangle")
        }
        guard tap.route(type: .leftMouseDown, event: mouse(.leftMouseDown, 100, command: true)) else { throw failure("Second selection lost") }
        _ = tap.route(type: .leftMouseDragged, event: drag)
        tap.stop()
        let calls = delivered.count
        try await Task.sleep(nanoseconds: 20_000_000)
        guard delivered.count == calls else { throw failure("Stopped event tap delivered queued movement") }
        print("Mouse routing: ordinary passthrough, 1000-to-1 drag coalescing, exact release rectangle, Command release and shutdown PASS. No installed tap or posted events.")
    }

    private static func verifyKeyboardRouting() async throws {
        var delivered: [UInt16] = []
        let tap = ShortcutEventTap { _, event in
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            delivered.append(code)
            return code == 63
        }
        defer { tap.stop() }
        let ordinary = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        for observing in [false, true] {
            tap.configureRouting(keyCodes: [63, 53], observesOtherKeys: observing, commandClicks: false)
            let ready = DispatchSemaphore(value: 0)
            let task = Task.detached { () -> (Bool, Double) in
                ready.signal()
                let start = CACurrentMediaTime()
                let consumed = tap.route(type: .keyDown, event: ordinary)
                return (consumed, (CACurrentMediaTime() - start) * 1000)
            }
            blockMain(until: ready)
            let (consumed, elapsed) = await task.value
            guard !consumed, elapsed < 20 else { throw failure("Ordinary typing waited for rendering") }
            try await Task.sleep(for: .milliseconds(5))
            guard delivered == (observing ? [0] : []) else { throw failure("Shortcut interruption observation lost") }
            print(String(format: "Ordinary key with 80 ms main-thread stall (observing %@): %.3f ms", String(observing), elapsed))
        }
        let shortcut = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true)!
        guard tap.route(type: .keyDown, event: shortcut), delivered == [0, 63] else { throw failure("Shortcut lost its synchronous consume decision") }
        let commandClick = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        commandClick.flags = .maskCommand
        guard !tap.route(type: .leftMouseDown, event: commandClick), delivered == [0, 63] else { throw failure("Ordinary Command-click routed into Prompt mode") }
        tap.configureRouting(keyCodes: nil, observesOtherKeys: true, commandClicks: false)
        _ = tap.route(type: .keyDown, event: ordinary)
        guard delivered == [0, 63, 0] else { throw failure("Shortcut capture missed an arbitrary key") }
        tap.configureRouting(keyCodes: [63, 53], observesOtherKeys: false, commandClicks: false)
        let ready = DispatchSemaphore(value: 0)
        let modifierTask = Task.detached { () -> (Bool, Double) in
            ready.signal()
            let started = CACurrentMediaTime()
            let consumed = tap.route(type: .flagsChanged, event: shortcut)
            let letterConsumed = tap.route(type: .keyDown, event: ordinary)
            let releaseConsumed = tap.route(type: .flagsChanged, event: shortcut)
            return (consumed || letterConsumed || releaseConsumed, (CACurrentMediaTime() - started) * 1000)
        }
        blockMain(until: ready)
        let (consumed, elapsed) = await modifierTask.value
        try await Task.sleep(for: .milliseconds(5))
        guard !consumed, elapsed < 20, delivered == [0, 63, 0, 63, 0, 63] else { throw failure("Fn combination waited for rendering or lost ordered shortcut observation") }
        print(String(format: "Fn combination with 80 ms main-thread stall: %.3f ms; press, interruption and release remain ordered.", elapsed))
    }

    private static func failure(_ text: String) -> Error { ServiceError.message(text) }
    private static func blockMain(until ready: DispatchSemaphore) {
        ready.wait()
        Thread.sleep(forTimeInterval: 0.08)
    }
}
