import AppKit
import S2TCore

@MainActor enum MenuBarProbe {
    static func run(directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let original = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(original, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        state.processingProvider = .openRouter
        state.menuAppearance = "system"
        state.assemblyKey = ""
        state.routerKey = ""
        state.cerebrasKey = ""
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); state.cancel() }
        guard let icon = NSImage(named: "MenuBar"), icon.isValid,
              Bundle.main.url(forResource: "S2T", withExtension: "icns") != nil,
              Bundle.main.url(forResource: "Assets", withExtension: "car") != nil else { throw failure("Packaged artwork is missing.") }
        guard NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain }).isEmpty else { throw failure("A settings window opened.") }
        guard controller.statusItem.length == 24, controller.statusItem.button?.image?.size == MenuBarArtwork.size else { throw failure("Menu bar logo is not compact.") }
        if let data = controller.statusItem.button?.image?.tiffRepresentation,
           let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("menu-bar-mark.png"))
        }
        print("Packaged icons, reference-proportioned logo, 24-point menu item, and windowless startup: PASS")
        controller.menuNeedsUpdate(controller.menu)
        let root = controller.menu
        for id in ["keys", "dictation", "result"] {
            guard let child = item(id, in: root)?.submenu else { throw failure("Missing submenu: \(id)") }
            controller.menuNeedsUpdate(child)
            guard !child.items.isEmpty else { throw failure("Empty submenu: \(id)") }
        }
        let dictation = item("dictation", in: root)!.submenu!
        (item("mode.notes", in: dictation) as? ActionMenuItem)?.invoke()
        guard state.mode == .notes else { throw failure("Writing mode did not change.") }
        let activation = item("activation", in: dictation)!.submenu!
        controller.menuNeedsUpdate(activation)
        let hold = state.holdEnabled
        (item("shortcut.hold", in: activation) as? ActionMenuItem)?.invoke()
        guard state.holdEnabled != hold else { throw failure("Hold toggle did not change.") }
        let appearance = controller.appearanceWindow
        appearance.prepare()
        state.menuAppearance = "dark"
        appearance.refresh()
        appearance.window?.close()
        guard state.menuAppearance == "dark" else { throw failure("Appearance was not saved.") }
        state.menuAppearance = "system"
        controller.refreshStatus()
        let keys = item("keys", in: root)!.submenu!
        let processing = item("keys.processing", in: keys)!.submenu!
        controller.menuNeedsUpdate(processing)
        (item("provider.cerebras", in: processing) as? ActionMenuItem)?.invoke()
        guard state.processingProvider == .cerebras else { throw failure("Provider selection failed.") }
        controller.menuNeedsUpdate(processing)
        guard let alternate = processing.items.compactMap({ $0.view as? MenuValueEditor }).first,
              alternate.field is NSSecureTextField else { throw failure("Provider editor is not secure.") }
        state.processingProvider = .openRouter
        print("All settings submenus, mode, hold, appearance, and provider actions: PASS")

        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
        board.clearContents()
        board.setString("synthetic-menu-key", forType: .string)
        var ownedChange = board.changeCount
        defer {
            if board.changeCount == ownedChange {
                board.clearContents()
                board.writeObjects(saved.map { values in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                })
            }
        }
        var step = 0
        var attempts = 0
        var problem: Error?
        let originalMouse = NSEvent.mouseLocation
        var movedMouse: NSPoint?
        defer {
            if let movedMouse, hypot(NSEvent.mouseLocation.x - movedMouse.x, NSEvent.mouseLocation.y - movedMouse.y) < 2 {
                moveMouse(originalMouse)
            }
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { timer in
            MainActor.assumeIsolated {
                let board = NSPasteboard.general
                do {
                    attempts += 1
                    guard attempts < 25 else { throw failure("Menu verification timed out at step \(step).") }
                    switch step {
                    case 0:
                        guard let entry = item("keys", in: controller.menu) else { return }
                        let frame = entry.accessibilityFrame()
                        guard frame.width > 0 else { return }
                        let point = NSPoint(x: frame.midX, y: frame.midY)
                        print("Hover step \(step): \(frame)")
                        moveMouse(point)
                        movedMouse = point
                        step = 1
                    case 1:
                        guard let keys = item("keys", in: controller.menu)?.submenu,
                              let entry = item("keys.processing", in: keys) else { return }
                        let frame = entry.accessibilityFrame()
                        guard frame.width > 0 else { return }
                        let point = NSPoint(x: frame.midX, y: frame.midY)
                        print("Hover step \(step): \(frame)")
                        moveMouse(point)
                        movedMouse = point
                        step = 2
                    case 2:
                        guard let keys = item("keys", in: controller.menu)?.submenu,
                              let processing = item("keys.processing", in: keys)?.submenu,
                              let initialEditor = processing.items.compactMap({ $0.view as? MenuValueEditor }).first,
                              initialEditor.window != nil else { return }
                        guard let choice = item("provider.cerebras", in: processing) as? ActionMenuItem else { throw failure("Provider control missing.") }
                        choice.invoke()
                        guard state.processingProvider == .cerebras,
                              let replacement = processing.items.compactMap({ $0.view as? MenuValueEditor }).first,
                              replacement.window != nil, TextInsertion.menuIsOpen,
                              choice.state == .on else { throw failure("Provider click closed the menu or failed to update.") }
                        guard let router = item("provider.openrouter", in: processing) as? ActionMenuItem else { throw failure("OpenRouter row missing.") }
                        router.invoke()
                        guard let editor = processing.items.compactMap({ $0.view as? MenuValueEditor }).first, let window = editor.window else { throw failure("Switching back closed the menu.") }
                        print("Provider clicks keep the menu open and update the editor: PASS")
                        try capture(window, to: directory.appendingPathComponent("provider-submenu.png"))
                        editor.pasteButton.performClick(nil)
                        guard state.routerKey == "synthetic-menu-key", state.cerebrasKey.isEmpty else { throw failure("Paste reached the wrong provider or failed.") }
                        editor.saveButton.performClick(nil)
                        guard state.savedKeyAccounts.contains("openrouter"), editor.saveButton.title == "✓ Saved" else { throw failure("Save confirmation failed.") }
                        try capture(window, to: directory.appendingPathComponent("saved-submenu.png"))
                        board.clearContents()
                        board.setString("changed-synthetic-key", forType: .string)
                        ownedChange = board.changeCount
                        editor.pasteButton.performClick(nil)
                        guard !state.savedKeyAccounts.contains("openrouter"), editor.saveButton.title == "Save API key" else { throw failure("Paste did not clear the saved state.") }
                        print("Live nested menu, secure paste, save, and confirmation reset: PASS")
                        step = 3
                        timer.invalidate()
                        controller.menu.cancelTracking()
                    default: break
                    }
                } catch {
                    problem = error
                    timer.invalidate()
                    controller.menu.cancelTracking()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let button = controller.statusItem.button, let window = button.window else { throw failure("Status button is not visible.") }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        print("Status button: \(frame), visible=\(window.isVisible), screens=\(NSScreen.screens.map { $0.frame })")
        controller.menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.minY), in: nil)
        timer.invalidate()
        if let problem { throw problem }
        guard step == 3 else { throw failure("Menu closed before verification finished at step \(step).") }
        for theme in ["light", "dark"] {
            state.menuAppearance = theme
            controller.refreshStatus()
            var themeStep = 0
            var themeError: Error?
            let themeTimer = Timer(timeInterval: 0.5, repeats: true) { timer in
                MainActor.assumeIsolated {
                    do {
                        if themeStep == 0 {
                            guard let entry = item("appearance", in: controller.menu) else { throw failure("Appearance submenu missing.") }
                            let rect = entry.accessibilityFrame()
                            let point = NSPoint(x: rect.midX, y: rect.midY)
                            moveMouse(point)
                            movedMouse = point
                            themeStep = 1
                        } else if themeStep < 5 {
                            guard let child = item("appearance", in: controller.menu)?.submenu,
                                  let view = child.items.compactMap({ $0.view as? MenuSlider }).first,
                                  let window = view.window else { themeStep += 1; return }
                            guard let other = item("appearance.\(theme == "light" ? "dark" : "light")", in: child) as? ActionMenuItem,
                                  let chosen = item("appearance.\(theme)", in: child) as? ActionMenuItem else { throw failure("Appearance controls missing.") }
                            other.invoke()
                            chosen.invoke()
                            guard view.window != nil, TextInsertion.menuIsOpen, state.menuAppearance == theme else { throw failure("Appearance selection closed the menu.") }
                            view.slider.doubleValue = 1.1
                            view.slider.sendAction(view.slider.action, to: view.slider.target)
                            guard abs(state.glowStrength - 1.1) < 0.001 else { throw failure("Menu slider failed.") }
                            try capture(window, to: directory.appendingPathComponent("appearance-\(theme).png"))
                            print("Live \(theme) appearance submenu and slider: PASS")
                            themeStep = 6
                            timer.invalidate()
                            controller.menu.cancelTracking()
                        } else { throw failure("Appearance submenu did not open.") }
                    } catch {
                        themeError = error
                        timer.invalidate()
                        controller.menu.cancelTracking()
                    }
                }
            }
            RunLoop.main.add(themeTimer, forMode: .eventTracking)
            controller.menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.minY), in: nil)
            themeTimer.invalidate()
            if let themeError { throw themeError }
            guard themeStep == 6 else { throw failure("Appearance check closed early.") }
        }
        print("No provider requests or real credential writes were used.")
    }

    private static func moveMouse(_ point: NSPoint) {
        let location = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func item(_ id: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier?.rawValue == id }
    }

    private static func capture(_ window: NSWindow, to url: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw failure("Menu capture failed.") }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MenuBarProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
