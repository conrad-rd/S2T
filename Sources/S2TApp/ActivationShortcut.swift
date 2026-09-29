import AppKit
import Combine
import S2TCore

@MainActor final class ActivationShortcut: ObservableObject {
    @Published private(set) var available = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var status = "Accessibility access is required."
    @Published private(set) var isCapturing = false { didSet { updateRouting() } }
    @Published private(set) var isTesting = false { didSet { updateRouting() } }
    @Published private(set) var testStatus = "Test your shortcut without recording."
    @Published private(set) var testPassed = false
    var onAction: ((ActivationAction) -> Void)?
    var onPromptPointer: ((CGEventType, CGEvent) -> Bool)?
    var capturesPromptPointer = false { didSet { updateRouting() } }
    var promptDragObserver: (@Sendable (CGPoint) -> Void)? { didSet { eventTap?.setDragObserver(promptDragObserver) } }
    var onPromptAction: ((ActivationAction) -> Void)?
    var onPromptCapture: ((ShortcutKey) -> Void)?
    private var capturingPrompt = false
    private var promptKey: ShortcutKey?
    private var promptHoldEnabled = true
    private var promptTapEnabled = true
    private var activeKey: ShortcutKey?
    private var activePrompt = false
    private var activePressStartedRecording = false
    var onCapture: ((ShortcutKey) -> Void)?
    var isListening: () -> Bool = { false }
    var canCancel: () -> Bool = { false }
    var onCancel: (() -> Void)?
    private var escapeTimer: Timer?
    private var escapeIsDown = false
    private var escapeDidCancel = false
    private static let escapeHoldDuration: TimeInterval = 0.6
    private var key = ShortcutKey.function
    private var holdEnabled = true
    private var tapEnabled = true
    private var tap: CFMachPort?
    private var eventTap: ShortcutEventTap?
    private var permissionTimer: Timer?
    private var requestedAccess = false
    private var localMonitor: Any?
    private var gesture = ActivationGesture()
    private var keyIsDown = false
    private var capturedKeyAwaitingRelease: UInt16?
    private var testTimer: Timer?
    private let systemAction = FnSystemAction()
    private var fnReady = true
    private let verification: Bool
    private let escapeKeyIsDown: () -> Bool
    private static let modifierFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]

    init(verification: Bool = false, escapeKeyIsDown: (() -> Bool)? = nil) {
        self.verification = verification
        self.escapeKeyIsDown = escapeKeyIsDown ?? (verification ? { true } : { CGEventSource.keyState(.hidSystemState, key: 53) })
    }

    func configure(key: ShortcutKey, hold: Bool, tap: Bool) {
        guard self.key != key || holdEnabled != hold || tapEnabled != tap else { return }
        resetGesture()
        cancelTest()
        testPassed = false
        testStatus = "Test your shortcut without recording."
        self.key = key
        holdEnabled = hold
        tapEnabled = tap
        updateRouting()
        updateSystemAction()
        refresh()
    }

    func configurePrompt(key: ShortcutKey?, hold: Bool = true, tap: Bool = true) {
        guard promptKey != key || promptHoldEnabled != hold || promptTapEnabled != tap else { return }
        resetGesture()
        cancelCapture()
        promptKey = key
        promptHoldEnabled = hold
        promptTapEnabled = tap
        updateRouting()
        updateSystemAction()
        refresh()
    }

    func startMonitoring() {
        refresh()
        guard !verification else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consume = MainActor.assumeIsolated {
                guard let self, self.tap == nil, self.isCapturing, let cg = event.cgEvent else { return false }
                return self.receive(type: cg.type, event: cg)
            }
            return consume ? nil : event
        }
    }

    func beginCapture(prompt: Bool = false) { cancelTest(); resetGesture(); capturingPrompt = prompt; isCapturing = true }
    func cancelCapture() { isCapturing = false }

    func beginTest() {
        refresh()
        guard available else { testStatus = status; return }
        cancelCapture()
        resetGesture()
        testPassed = false
        isTesting = true
        testStatus = "Press and release \(key.displayName). No audio is recorded."
        testTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cancelTest()
                self?.testStatus = "No shortcut detected. Check Accessibility or choose another key."
            }
        }
        testTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancelTest() {
        guard isTesting else { return }
        testTimer?.invalidate(); testTimer = nil
        isTesting = false
        testStatus = "Shortcut test cancelled."
        resetGesture()
    }

    func repairFn() {
        guard !verification else { return }
        guard key.keyCode == 63, tap != nil, holdEnabled || tapEnabled else { return }
        testPassed = false
        _ = systemAction.retry()
        updateSystemAction()
    }

    func requestAccess() {
        guard !verification else { return }
        guard !AXIsProcessTrusted() else { refresh(); return }
        if requestedAccess {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            requestedAccess = true
            let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        }
        refresh()
    }

    func refresh() {
        if verification {
            accessibilityGranted = true
            available = holdEnabled || tapEnabled
            return
        }
        let trusted = AXIsProcessTrusted()
        if accessibilityGranted != trusted { accessibilityGranted = trusted }
        guard trusted else {
            removeTap()
            status = "Allow Accessibility access to use the activation key."
            return
        }
        if let tap {
            if !CFMachPortIsValid(tap) { removeTap() }
            else {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
                updateSystemAction()
                return
            }
        }
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        let eventTap = ShortcutEventTap { [weak self] type, event in self?.receive(type: type, event: event) ?? false }
        guard let created = eventTap.start(mask: mask) else {
            status = "macOS could not enable the shortcut. Check Accessibility access and reopen the app."
            return
        }
        self.eventTap = eventTap
        eventTap.setDragObserver(promptDragObserver)
        updateRouting()
        tap = created
        CGEvent.tapEnable(tap: created, enable: true)
        updateSystemAction()
    }

    private func updateSystemAction() {
        guard !verification else { refresh(); return }
        guard tap != nil, holdEnabled || tapEnabled || (promptKey != nil && (promptHoldEnabled || promptTapEnabled)) else {
            systemAction.restore()
            available = false
            if !holdEnabled && !tapEnabled { status = "Both shortcut behaviors are off. Use the Dictation button to record." }
            return
        }
        let needsFn = (key.keyCode == 63 && (holdEnabled || tapEnabled)) || (promptKey?.keyCode == 63 && (promptHoldEnabled || promptTapEnabled))
        if needsFn { fnReady = systemAction.begin() }
        else { systemAction.restore(); fnReady = true }
        available = (holdEnabled || tapEnabled) && (key.keyCode != 63 || fnReady)
        if available { status = "\(key.displayName) shortcut enabled." }
        else if key.keyCode == 63 && !fnReady { status = "Set the Fn action to Do Nothing in macOS Keyboard settings to override the emoji picker." }
        else { status = "Both shortcut behaviors are off. Use the Dictation button to record." }
    }

    func receive(type: CGEventType, event: CGEvent) -> Bool {
        defer { updateRouting() }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGesture()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == TextInsertion.eventMarker { return false }
        if !isCapturing, !isTesting, onPromptPointer?(type, event) == true {
            if event.getIntegerValueField(.keyboardEventKeycode) == 53, type == .keyDown || type == .keyUp {
                _ = receiveEscape(type: type, event: event, allowModifiers: true)
            }
            if type == .leftMouseDown, activePrompt, !activePressStartedRecording { _ = gesture.interrupt() }
            return true
        }
        if [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(type) { return false }
        let eventTime = event.timestamp == 0 ? ProcessInfo.processInfo.systemUptime : Double(event.timestamp) / 1_000_000_000
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifier = Self.primaryModifier(code)
        let modifierIsDown = Self.modifierIsDown(code, flags: event.flags)
        let down = type == .keyDown || (type == .flagsChanged && modifierIsDown == true)
        let up = type == .keyUp || (type == .flagsChanged && modifierIsDown == false)
        if isTesting {
            if code == 53 && down { cancelTest(); testStatus = "Shortcut test cancelled."; return true }
            if code == key.keyCode {
                var modifiers = event.flags.intersection(Self.modifierFlags)
                if let modifier { modifiers.remove(modifier) }
                if down && modifiers.rawValue == key.modifiers { keyIsDown = true }
                if up && keyIsDown {
                    cancelTest()
                    testPassed = true
                    testStatus = "\(key.displayName) detected. \(code == 63 ? "If emoji appeared too, use Fix Fn below." : "Your shortcut works.")"
                }
                return modifier == nil
            }
            if down { keyIsDown = false }
            return false
        }
        if capturedKeyAwaitingRelease == code {
            if up { capturedKeyAwaitingRelease = nil }
            return modifier == nil
        }
        if isCapturing {
            if type == .keyDown && code == 53 { cancelCapture(); return true }
            if (type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0) || (type == .flagsChanged && up) {
                var modifiers = event.flags.intersection(Self.modifierFlags)
                if let modifier { modifiers.remove(modifier) }
                let captured = ShortcutKey(keyCode: code, modifiers: modifiers.rawValue, name: Self.keyName(code, event: event))
                isCapturing = false
                if down { capturedKeyAwaitingRelease = code }
                if capturingPrompt { onPromptCapture?(captured) } else { onCapture?(captured) }
                return modifier == nil
            }
            return type == .keyDown || type == .keyUp
        }
        if code == 53, type == .keyDown || type == .keyUp {
            return receiveEscape(type: type, event: event)
        }
        if down { cancelEscapeHold() }
        if keyIsDown, let activeKey {
            if code == activeKey.keyCode {
                if up {
                    keyIsDown = false
                    self.activeKey = nil
                    dispatch(gesture.release(at: eventTime), prompt: activePrompt)
                }
                return modifier == nil
            }
            if type == .keyDown || type == .flagsChanged { dispatch(gesture.interrupt(), prompt: activePrompt) }
            return false
        }
        guard down, verification || tap != nil else { return false }
        let bindings: [(key: ShortcutKey, prompt: Bool, hold: Bool, tap: Bool)] =
            (available ? [(key, false, holdEnabled, tapEnabled)] : []) +
            (promptKey.map { [($0, true, promptHoldEnabled, promptTapEnabled)] } ?? [])
        for binding in bindings where (binding.hold || binding.tap) && code == binding.key.keyCode {
            if binding.key.keyCode == 63 && !fnReady { continue }
            var modifiers = event.flags.intersection(Self.modifierFlags)
            if let modifier { modifiers.remove(modifier) }
            guard modifiers.rawValue == binding.key.modifiers else { continue }
            let oppositeMasks: [UInt16: UInt64] = [54: 0x8, 55: 0x10, 56: 0x4, 60: 0x2, 58: 0x40, 61: 0x20, 59: 0x2000, 62: 0x1]
            if let opposite = oppositeMasks[code], event.flags.rawValue & opposite != 0 { continue }
            activePrompt = binding.prompt
            activeKey = binding.key
            keyIsDown = true
            let listening = isListening()
            activePressStartedRecording = binding.hold && !listening
            dispatch(gesture.press(at: eventTime, listening: listening, hold: binding.hold, tap: binding.tap), prompt: binding.prompt)
            return modifier == nil
        }
        return false
    }

    private func dispatch(_ action: ActivationAction, prompt: Bool = false) {
        guard action != .none else { return }
        Task { @MainActor [weak self] in
            if prompt { self?.onPromptAction?(action) } else { self?.onAction?(action) }
        }
    }

    private func receiveEscape(type: CGEventType, event: CGEvent, allowModifiers: Bool = false) -> Bool {
        if type == .keyUp {
            cancelEscapeHold()
            return false
        }
        guard !escapeIsDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return escapeDidCancel }
        escapeIsDown = true
        var modifiers = event.flags.intersection(Self.modifierFlags)
        if keyIsDown, let activeKey {
            modifiers.subtract(CGEventFlags(rawValue: activeKey.modifiers))
            if let modifier = Self.primaryModifier(activeKey.keyCode) { modifiers.remove(modifier) }
        }
        guard (allowModifiers || modifiers.isEmpty), canCancel() || keyIsDown else { return false }
        let timer = Timer(timeInterval: Self.escapeHoldDuration, repeats: false) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.escapeTimer === timer else { return }
                self.escapeTimer = nil
                guard self.escapeIsDown, self.canCancel() || self.keyIsDown else { return }
                // A queued key-up must not become a hold when the main thread was busy.
                guard self.escapeKeyIsDown() else { return }
                self.escapeDidCancel = true
                _ = self.gesture.interrupt()
                self.onCancel?()
            }
        }
        escapeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return false
    }

    private func cancelEscapeHold() {
        escapeTimer?.invalidate()
        escapeTimer = nil
        escapeIsDown = false
        escapeDidCancel = false
    }

    func resetGesture() {
        cancelEscapeHold()
        keyIsDown = false
        activeKey = nil
        updateRouting()
        dispatch(gesture.interrupt(), prompt: activePrompt)
    }

    private func updateRouting() {
        var codes: Set<UInt16> = [key.keyCode, 53]
        if let promptKey { codes.insert(promptKey.keyCode) }
        if let capturedKeyAwaitingRelease { codes.insert(capturedKeyAwaitingRelease) }
        eventTap?.configureRouting(keyCodes: isCapturing ? nil : codes,
            observesOtherKeys: keyIsDown || escapeIsDown || isTesting,
            commandClicks: capturesPromptPointer && !isCapturing && !isTesting)
    }
    func stop() {
        cancelTest()
        permissionTimer?.invalidate(); permissionTimer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        removeTap()
    }
    private func removeTap() {
        cancelTest()
        testPassed = false
        eventTap?.stop()
        eventTap = nil; tap = nil
        resetGesture()
        if !verification { systemAction.restore() }
        available = false
    }

    private static func primaryModifier(_ code: UInt16) -> CGEventFlags? {
        switch code {
        case 63: return .maskSecondaryFn
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        default: return nil
        }
    }
    private static func modifierIsDown(_ code: UInt16, flags: CGEventFlags) -> Bool? {
        if code == 63 { return flags.contains(.maskSecondaryFn) }
        let deviceMasks: [UInt16: UInt64] = [59: 0x1, 56: 0x2, 60: 0x4, 55: 0x8, 54: 0x10, 58: 0x20, 61: 0x40, 62: 0x2000]
        guard let mask = deviceMasks[code] else { return nil }
        return flags.rawValue & mask != 0
    }
    private static func keyName(_ code: UInt16, event: CGEvent) -> String {
        let names: [UInt16: String] = [63: "Fn", 54: "Right Command", 55: "Left Command", 56: "Left Shift", 60: "Right Shift", 58: "Left Option", 61: "Right Option", 59: "Left Control", 62: "Right Control", 36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape", 76: "Enter", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return names[code] ?? NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? "Key \(code)"
    }
}
