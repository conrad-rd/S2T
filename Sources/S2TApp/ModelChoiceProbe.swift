import AppKit
import S2TCore

@MainActor enum ModelChoiceProbe {
    static func choose(_ id: String, _ value: String, in pane: ModelsPane) throws {
        pane.showSettings(containing: id)
        if id.hasSuffix(".model"), pane.controls[id] is NSTextField {
            let prefix = String(id.dropLast(".model".count))
            try beginCustom(prefix, in: pane)
            guard let field = pane.controls[id] as? NSTextField, field.isEnabled else { throw failure("Custom model field is unavailable") }
            field.stringValue = value
            guard let save = pane.controls[id + ".save"] as? NSButton else { throw failure("Custom model needs an explicit Save action") }
            save.performClick(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            return
        }
        if let toggle = pane.controls[id] as? NSSwitch, value == "fast" || value == "normal" {
            toggle.state = value == "fast" ? .on : .off
            toggle.sendAction(toggle.action, to: toggle.target)
            return
        }
        guard let popup = pane.controls[id] as? NSPopUpButton, popup.isEnabled,
              let item = item(value, in: popup.menu), item.isEnabled else {
            throw failure("Missing enabled choice: " + id + "/" + value + "; cleanup model=" + pane.state.processingModel + "; provider=" + (pane.state.processingProvider?.rawValue ?? "none") + "; catalog=" + pane.catalog.map(\.slug).joined(separator: ",") + "; choices=" + ((pane.controls[id] as? NSPopUpButton)?.itemTitles.joined(separator: ",") ?? "missing"))
        }
        if item.menu === popup.menu {
            popup.select(item)
            popup.sendAction(popup.action, to: popup.target)
        } else if let menu = item.menu {
            // Provider submenu leaves carry their own action, like a real menu selection.
            menu.performActionForItem(at: menu.index(of: item))
        }
    }

    /// Every visible choice value, including provider submenus.
    static func values(in menu: NSMenu?) -> [String] {
        (menu?.items ?? []).filter { !$0.isHidden }.flatMap { item in
            (item.representedObject as? String).map { [$0] } ?? values(in: item.submenu)
        }
    }

    static func item(_ value: String, in menu: NSMenu?) -> NSMenuItem? {
        let items = (menu?.items ?? []).filter { !$0.isHidden }
        for item in items where item.submenu != nil && item.state == .on {
            if let found = self.item(value, in: item.submenu) { return found }
        }
        for item in items {
            if item.representedObject as? String == value { return item }
            if let found = self.item(value, in: item.submenu) { return found }
        }
        return nil
    }

    static func beginCustom(_ prefix: String, in pane: ModelsPane) throws {
        try choose(prefix + ".choice", "custom", in: pane)
    }

    static func verify(_ pane: ModelsPane) throws {
        let state = pane.state
        let original = state.processingModel
        let originalHost = state.routerEndpoint
        pane.navigation.select(.cleanup)
        guard pane.controls["cleanup.provider"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.choice"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == true,
              pane.controls.keys.allSatisfy({ !$0.contains(".suggestion.") }) else {
            throw failure("Provider and model must share one page, with no competing suggestion buttons or idle custom editor")
        }
        pane.navigation.select(.local)
        pane.navigation.back()
        guard pane.navigation.page == .settings, !pane.navigation.onSubpage,
              pane.controls["cleanup.choice"]?.isHiddenOrHasHiddenAncestor == false else { throw failure("Back must return directly to the Models page") }
        pane.navigation.select(.cleanup)
        try beginCustom("cleanup", in: pane)
        guard let draft = pane.controls["cleanup.model"] as? NSTextField,
              pane.controls["cleanup.model.save"]?.isHiddenOrHasHiddenAncestor == false else {
            throw failure("Choosing Custom must reveal its editor and Save action")
        }
        draft.stringValue = "fixture/unsaved-model"
        pane.navigation.select(.speech)
        pane.navigation.select(.cleanup)
        guard state.processingModel == original, pane.controls["cleanup.model"] === draft,
              draft.stringValue == "fixture/unsaved-model" else {
            throw failure("Navigating must preserve a custom draft without activating it")
        }
        pane.rebuild()
        guard (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == "fixture/unsaved-model",
              state.processingModel == original else {
            throw failure("A settings refresh must preserve an unsaved model draft without activating it")
        }
        try choose("cleanup.model", "fixture/custom-model", in: pane)
        try choose("cleanup.choice", "openai/gpt-oss-20b", in: pane)
        guard state.processingModel == "openai/gpt-oss-20b",
              pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == true else {
            throw failure("Choosing a catalog model must save immediately and hide custom editing")
        }
        let restored = ModelsPane(state: AppState(preview: true))
        _ = restored.view
        try beginCustom("cleanup", in: restored)
        guard (restored.controls["cleanup.model"] as? NSTextField)?.stringValue == "fixture/custom-model",
              state.processingModel == "openai/gpt-oss-20b" else {
            throw failure("Custom draft must survive restart without replacing the selected catalog model")
        }
        try beginCustom("cleanup", in: pane)
        guard state.processingModel == "openai/gpt-oss-20b",
              (pane.controls["cleanup.model"] as? NSTextField)?.stringValue == "fixture/custom-model" else {
            throw failure("Custom must restore the saved ID and wait for Save")
        }
        (pane.controls["cleanup.model.save"] as? NSButton)?.performClick(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        try choose("cleanup.provider", "codex", in: pane)
        guard let codexChoice = pane.controls["cleanup.choice"] as? NSPopUpButton,
              codexChoice.selectedItem?.representedObject as? String == "default",
              pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == true else {
            throw failure("Codex must offer its default without requiring a catalog or custom ID")
        }
        try choose("cleanup.provider", "openrouter", in: pane)
        guard state.processingProvider == .openRouter, state.processingModel == "fixture/custom-model" else {
            throw failure("Provider switching lost the saved custom model")
        }
        guard let popup = pane.controls["cleanup.provider"] as? ModelProviderPicker,
              popup.itemArray.filter({ $0.representedObject as? String == "openrouter" }).count == 1,
              popup.isEnabled else { throw failure("Provider choices must appear once") }
        try choose("cleanup.choice", original, in: pane)
        state.routerEndpoint = originalHost
        pane.rebuild()
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ModelChoiceProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
