import AppKit
import S2TCore

@MainActor enum InputAppearanceActionsProbe {
    static func verify(state: AppState, menu: MenuBarController) throws {
        let saved = state.glowAppearance
        let controls = menu.appearanceWindow
        defer { state.glowAppearance = saved; controls.window?.close() }
        guard let choices = menu.menu.items.first(where: { $0.identifier?.rawValue == "appearance.styles" })?.submenu else {
            throw failure("Missing Appearance choices")
        }
        menu.menuNeedsUpdate(choices)
        let window = controls.prepare()
        controls.setModelsVisible(false)
        let picker = controls.modeBar.picker
        guard picker.segmentCount == GlowAppearance.selectableCases.count else {
            throw failure("Missing native appearance segments")
        }
        for mode in [GlowAppearance.aroundInput, .withinInput] {
            guard let index = GlowAppearance.selectableCases.firstIndex(of: mode),
                  let action = choices.items.compactMap({ $0 as? ActionMenuItem }).first(where: { $0.title == mode.title }),
                  picker.toolTip(forSegment: index) == mode.title else { throw failure("Input mode is unreachable") }
            action.invoke()
            menu.menuNeedsUpdate(choices)
            guard state.glowAppearance == mode, AppState(preview: true).glowAppearance == mode, action.state == .on else {
                throw failure("Input mode did not save or update its menu checkmark")
            }
            picker.selectedSegment = index
            picker.sendAction(picker.action, to: picker.target)
            window.contentView?.layoutSubtreeIfNeeded()
            guard controls.preview.mode == mode, state.glowAppearance == mode, !window.isVisible else {
                throw failure("Native input preview selection changed live state or showed its window")
            }
        }
        print("PASS: both input modes are reachable and persist through native menu actions and the hidden native preview picker.")
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "InputAppearanceActions", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
