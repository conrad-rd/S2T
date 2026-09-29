import AppKit
import S2TCore

@MainActor enum HoldEscapeProbe {
    static func run() async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw ServiceError.message(message) }
        }
        func event(_ code: CGKeyCode = 53, flags: CGEventFlags = [], repeatKey: Bool = false) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            return event
        }
        func pause(_ milliseconds: UInt64) async throws { try await Task.sleep(nanoseconds: milliseconds * 1_000_000) }
        var escapeKeyIsDown = true
        let shortcut = ActivationShortcut(verification: true, escapeKeyIsDown: { escapeKeyIsDown })
        defer { shortcut.stop() }
        shortcut.configure(key: .function, hold: true, tap: false)
        shortcut.configurePrompt(key: .rightCommand, hold: true, tap: false)
        shortcut.refresh()
        let state = AppState(preview: true)
        shortcut.canCancel = { state.canCancel }
        var cancellations = 0
        shortcut.onCancel = { cancellations += 1; state.cancel() }
        let phases: [DictationPhase] = [.preparing, .recording, .transcribing, .processing]
        for phase in phases {
            state.phase = phase
            try check(!shortcut.receive(type: .keyDown, event: event()), "A quick Escape must reach the active app during \(phase)")
            try await pause(30)
            try check(!shortcut.receive(type: .keyUp, event: event()), "Escape release must reach the active app")
            try check(state.phase == phase, "A quick Escape cancelled \(phase)")
        }
        try await pause(700)
        try check(cancellations == 0, "Released Escape left a cancellation timer behind")
        for phase in phases {
            state.phase = phase
            state.rawTranscript = "Keep previous text"
            _ = shortcut.receive(type: .keyDown, event: event())
            try await pause(300)
            _ = shortcut.receive(type: .keyDown, event: event(repeatKey: true))
            try check(state.phase == phase, "Escape cancelled before the hold threshold")
            try await pause(400)
            try check(state.phase == .idle && state.rawTranscript == "Keep previous text", "Held Escape must cancel \(phase) and retain the previous transcript")
            let count = cancellations
            _ = shortcut.receive(type: .keyDown, event: event(repeatKey: true))
            try check(!shortcut.receive(type: .keyUp, event: event()), "Held Escape must balance the key-down delivered to the active app")
            try check(cancellations == count, "Escape repeat cancelled twice")
        }
        state.phase = .complete
        state.isWaitingToPaste = true
        _ = shortcut.receive(type: .keyDown, event: event())
        try await pause(700)
        try check(!state.isWaitingToPaste && state.phase == .idle, "Held Escape must cancel deferred delivery")
        _ = shortcut.receive(type: .keyUp, event: event())

        for (code, flags): (CGKeyCode, CGEventFlags) in [(63, .maskSecondaryFn), (54, CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10))] {
            var actions: [ActivationAction] = []
            shortcut.onAction = { actions.append($0) }
            shortcut.onPromptAction = { actions.append($0) }
            shortcut.isListening = { false }
            _ = shortcut.receive(type: .flagsChanged, event: event(code, flags: flags))
            _ = shortcut.receive(type: .keyDown, event: event(flags: flags))
            _ = shortcut.receive(type: .keyUp, event: event(flags: flags))
            try await pause(30)
            try check(actions == [.start], "A quick Escape interrupted held \(code == 63 ? "dictation" : "Prompt mode")")
            _ = shortcut.receive(type: .flagsChanged, event: event(code))
            try await pause(30)
            try check(actions == [.start, .stop], "Quick Escape changed normal activation release")
            actions = []
            let count = cancellations
            _ = shortcut.receive(type: .flagsChanged, event: event(code, flags: flags))
            _ = shortcut.receive(type: .keyDown, event: event(flags: flags))
            try await pause(700)
            _ = shortcut.receive(type: .keyUp, event: event(flags: flags))
            _ = shortcut.receive(type: .flagsChanged, event: event(code))
            try await pause(30)
            try check(actions == [.start] && cancellations == count + 1, "Held Escape must cancel without finishing on activation release")
        }

        let pointer = PromptRegionCapture(present: false)
        pointer.start()
        shortcut.onPromptPointer = { pointer.receive(type: $0, event: $1) }
        state.phase = .recording
        pointer.handle(.down, command: true, location: .zero)
        pointer.handle(.drag, command: true, location: CGPoint(x: 100, y: 100))
        try check(shortcut.receive(type: .keyDown, event: event()), "Rectangle Escape must be handled locally")
        try check(pointer.rect == nil && state.phase == .recording, "Quick Escape must cancel only the screenshot rectangle")
        _ = shortcut.receive(type: .keyUp, event: event())
        _ = pointer.handle(.up, command: false, location: CGPoint(x: 100, y: 100))
        try await pause(700)
        try check(state.phase == .recording, "Rectangle cancellation left a global cancellation pending")
        pointer.handle(.down, command: true, location: .zero)
        _ = shortcut.receive(type: .keyDown, event: event(flags: .maskCommand))
        try await pause(700)
        try check(state.phase == .idle, "Holding rectangle Escape must still cancel the prompt")
        _ = shortcut.receive(type: .keyUp, event: event())
        pointer.stop()
        shortcut.onPromptPointer = nil

        let count = cancellations
        state.phase = .recording
        _ = shortcut.receive(type: .keyDown, event: event(flags: [.maskCommand, .maskAlternate]))
        try await pause(700)
        _ = shortcut.receive(type: .keyUp, event: event())
        try check(cancellations == count, "Modified Escape must remain available to system shortcuts")
        _ = shortcut.receive(type: .keyDown, event: event())
        _ = shortcut.receive(type: .keyDown, event: event(8))
        try await pause(700)
        _ = shortcut.receive(type: .keyUp, event: event())
        try check(cancellations == count, "A new key must interrupt the Escape hold")
        state.phase = .idle
        _ = shortcut.receive(type: .keyDown, event: event())
        state.phase = .recording
        _ = shortcut.receive(type: .keyDown, event: event(repeatKey: true))
        try await pause(700)
        _ = shortcut.receive(type: .keyUp, event: event())
        try check(cancellations == count, "Idle Escape repeat must not cancel a new session")
        _ = shortcut.receive(type: .keyDown, event: event())
        escapeKeyIsDown = false
        try await pause(700)
        try check(cancellations == count, "A released physical key with a queued key-up must not become a hold")
        _ = shortcut.receive(type: .keyUp, event: event())
        escapeKeyIsDown = true
        _ = shortcut.receive(type: .keyDown, event: event())
        _ = shortcut.receive(type: .tapDisabledByTimeout, event: event())
        try await pause(700)
        try check(cancellations == count, "Tap interruption must cancel the pending Escape hold")
        _ = shortcut.receive(type: .keyDown, event: event())
        shortcut.stop()
        try await pause(700)
        try check(cancellations == count, "Stopping shortcut monitoring must cancel the pending Escape hold")
        print("Hold Escape: quick-press passthrough, 600-ms cancellation, repeat, held dictation/Prompt mode, rectangle, deferred delivery, modified keys and teardown PASS. Synthetic unposted events only.")
    }
}
