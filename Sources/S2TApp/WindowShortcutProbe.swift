import AppKit

@MainActor enum WindowShortcutProbe {
    private final class QuitReceiver: NSObject {
        var calls = 0
        @objc func terminate(_ sender: Any?) { calls += 1 }
    }

    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "WindowShortcutProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func event(_ key: String, code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                            windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                            isARepeat: false, keyCode: code)!
        }
        let menu = ApplicationMenu.make()
        let quit = menu.items[0].submenu!.items[0]
        let close = menu.items[1].submenu!.items[0]
        try require(quit.target === NSApp && quit.action == #selector(NSApplication.terminate(_:)), "Quit must terminate the application.")
        try require(close.target == nil && close.action == #selector(NSWindow.performClose(_:)), "Close must use the window responder chain.")
        let receiver = QuitReceiver()
        quit.target = receiver
        try require(menu.performKeyEquivalent(with: event("q", code: 12)) && receiver.calls == 1, "Command-Q did not dispatch Quit.")
        let state = AppState(preview: true)
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        controller.menuNeedsUpdate(controller.menu)
        let statusQuit = controller.menu.items.first { $0.identifier?.rawValue == "quit" }
        try require(statusQuit?.keyEquivalent == "q" && statusQuit?.keyEquivalentModifierMask == .command, "Status menu is missing Command-Q.")
        statusQuit?.target = receiver
        statusQuit?.action = #selector(QuitReceiver.terminate(_:))
        try require(controller.menu.performKeyEquivalent(with: event("q", code: 12)) && receiver.calls == 2, "Status menu Command-Q did not dispatch Quit.")
        let window = controller.appearanceWindow.prepare()
        close.target = window
        menu.autoenablesItems = false
        menu.items[1].submenu?.autoenablesItems = false
        try require(menu.performKeyEquivalent(with: event("w", code: 13)), "Command-W did not dispatch Close.")
        try require(!window.isVisible && controller.statusItem.menu === controller.menu && receiver.calls == 2, "Close affected the status item or quit the application.")
        print("Window shortcuts PASS: native Quit/Close dispatch, status-menu Quit, hidden settings close, menu item retained. No posted keys or screen capture.")
    }
}
