import AppKit

@MainActor enum MenuHighlightProbe {
    static func run() throws {
        let state = AppState(preview: true)
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        guard controller.statusItem.length == 24,
              let button = controller.statusItem.button,
              button.image?.size.width == 24,
              button.imageScaling == .scaleNone else {
            throw failure("Status item must fit the unchanged 24-point artwork without scaling")
        }
        guard button.frame.width == 24, button.window?.frame.width == 24,
              button.cell?.imageRect(forBounds: button.bounds).width == 24 else {
            throw failure("AppKit added external spacing or clipped the status image")
        }
        controller.refreshStatus()
        guard controller.statusItem.length == 24 else { throw failure("Status refresh restored extra padding") }
        print("PASS: 24-point status item, unchanged logo size and disabled image scaling.")
        controller.menuNeedsUpdate(controller.menu)
        let iconRows = ["setup", "dictation.toggle", "dictation.cancel", "result", "clipboard.history", "prompt", "dictation", "appearance", "notice", "quit"]
        for id in iconRows {
            guard let item = controller.menu.items.first(where: { $0.identifier?.rawValue == id }),
                  let title = item.attributedTitle,
                  let attachment = title.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment,
                  let image = attachment.image, image.size.width > 0, image.size.height > 0,
                  attachment.bounds.width > 0, attachment.bounds.height > 0,
                  max(attachment.bounds.width, attachment.bounds.height) <= 16,
                  abs(attachment.bounds.width / attachment.bounds.height - image.size.width / image.size.height) < 0.001,
                  title.string.hasSuffix(item.title), item.image == nil,
                  item.view == nil else {
                throw failure("Root row must use a native SF Symbol and standard menu layout: \(id)")
            }
        }
        let appearance = controller.appearanceWindow
        appearance.prepare()
        defer { appearance.window?.close() }
        guard let slider = appearance.sliders[.intensity] else { throw failure("Intensity slider missing") }
        let originalTitles = controller.menu.items.map { $0.attributedTitle?.copy() as? NSAttributedString }
        let started = CFAbsoluteTimeGetCurrent()
        for index in 0..<200 {
            slider.doubleValue = 0.25 + Double(index % 101) / 100 * 1.05
            slider.sendAction(slider.action, to: slider.target)
            controller.refreshStatus()
            for (item, original) in zip(controller.menu.items, originalTitles) {
                if let original {
                    guard item.attributedTitle?.isEqual(to: original) == true,
                          item.attributedTitle?.string.filter({ $0 == "\u{fffc}" }).count == 1 else {
                        throw failure("Slider refresh accumulated icons or changed root title width")
                    }
                }
            }
        }
        print("PASS: 200 intensity updates kept root titles unchanged with one icon each in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - started)) seconds.")
        state.phase = .recording
        controller.refreshStatus()
        guard controller.menu.items.first(where: { $0.identifier?.rawValue == "dictation.toggle" })?.attributedTitle?.string == "\u{fffc}  Finish dictation" else {
            throw failure("Dynamic command title did not update")
        }
        state.phase = .idle
        controller.refreshStatus()
        var actions = 0
        var submenus = 0
        func verify(_ menu: NSMenu) throws {
            controller.menuNeedsUpdate(menu)
            for item in menu.items {
                guard menu === controller.menu || item.attributedTitle == nil else {
                    throw failure("Menu row contains custom title formatting: \(item.title)")
                }
                if let child = item.submenu {
                    guard item.view == nil else { throw failure("Submenu uses a custom row") }
                    submenus += 1
                    try verify(child)
                } else if let action = item as? ActionMenuItem {
                    guard action.view == nil, action.target === action, action.action != nil else {
                        throw failure("Action must remain a standard menu title without a button view: \(item.title)")
                    }
                    actions += 1
                }
            }
        }
        try verify(controller.menu)
        guard actions > 20, submenus > 8 else { throw failure("Menu coverage is incomplete") }
        var calls = 0
        let selected = ActionMenuItem(title: "Selected setting") { calls += 1 }
        selected.state = .on
        selected.invoke()
        selected.isEnabled = false
        selected.invoke()
        guard calls == 1, selected.state == .on else { throw failure("Native action enablement or checkmark failed") }
        state.phase = .complete
        controller.refreshStatus()
        guard controller.menu.items.first(where: { $0.identifier?.rawValue == "status.phase" })?.isHidden == true else {
            throw failure("Completion caption must remain hidden")
        }
        print("PASS: \(actions) native actions and \(submenus) native submenus, native root SF Symbol text attachments, action dispatch, disabled actions and independent checkmarks.")
        print("No menus opened, real actions invoked, or screen pixels captured.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MenuHighlightProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
