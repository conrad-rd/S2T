import AppKit
import S2TCore

@MainActor enum ModelsWindowProbe {
    static func run() throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        let pane = controller.modelsPane
        try SettingsLayoutFixture.write(window, name: "settings-models")
        guard let hosting = pane.controls["cleanup.hosting.disclosure"] as? NSButton,
              hosting.state == .off, pane.controls["cleanup.host"]?.isHiddenOrHasHiddenAncestor == true,
              pane.controls["cleanup.provider"]?.isHiddenOrHasHiddenAncestor == false,
              pane.controls["cleanup.model"]?.isHiddenOrHasHiddenAncestor == false else { throw failure("Advanced hosting must not crowd primary model controls") }
        hosting.performClick(nil)
        guard pane.controls["cleanup.host"]?.isHiddenOrHasHiddenAncestor == false else { throw failure("Hosting disclosure does not reveal its editor") }
        pane.rebuild()
        guard (pane.controls["cleanup.hosting.disclosure"] as? NSButton)?.state == .on else { throw failure("Model refresh collapses an open disclosure") }

        let fixture = Data(#"{"models":[{"slug":"fixture-vision","display_name":"Fixture vision","visibility":"list","supported_reasoning_levels":[{"effort":"low","description":"Quick"},{"effort":"high","description":"Deep"}],"service_tiers":[{"id":"priority","name":"Fast"}],"input_modalities":["text","image"]},{"slug":"fixture-text","display_name":"Fixture text","visibility":"list","supported_reasoning_levels":[],"input_modalities":["text"]}]}"#.utf8)
        pane.setCatalog(try CodexModelCatalog.decode(fixture))
        func choose(_ id: String, _ value: String) throws {
            guard let popup = pane.controls[id] as? NSPopUpButton,
                  let index = popup.itemArray.firstIndex(where: { $0.representedObject as? String == value }) else { throw failure("Missing choice \(id): \(value)") }
            popup.selectItem(at: index)
            popup.sendAction(popup.action, to: popup.target)
        }
        try choose("cleanup.provider", "codex")
        try choose("cleanup.model", "fixture-vision")
        try choose("cleanup.reasoning", "high")
        guard let fast = pane.controls["cleanup.fast"] as? NSButton, fast.isEnabled else { throw failure("Fast option missing") }
        fast.performClick(nil)
        guard state.codexOptions(model: "fixture-vision", vision: false) == CodexOptions(reasoning: "high", fast: true),
              AppState(preview: true).codexOptions(model: "fixture-vision", vision: false) == CodexOptions(reasoning: "high", fast: true) else { throw failure("Codex options did not persist") }
        try choose("cleanup.model", "fixture-text")
        guard (pane.controls["cleanup.fast"] as? NSButton)?.isEnabled == false,
              (pane.controls["cleanup.reasoning"] as? NSPopUpButton)?.numberOfItems == 1 else { throw failure("Unsupported options were offered") }
        try choose("cleanup.model", "fixture-vision")
        guard (pane.controls["cleanup.fast"] as? NSButton)?.state == .on else { throw failure("Switching models lost options") }
        try choose("vision.provider", "codex")
        guard let visionModels = pane.controls["vision.model"] as? NSPopUpButton,
              !visionModels.itemArray.contains(where: { $0.representedObject as? String == "fixture-text" }) else { throw failure("Text-only model offered for vision") }
        try choose("vision.model", "fixture-vision")
        try choose("vision.reasoning", "low")
        guard state.codexOptions(model: "fixture-vision", vision: true) == CodexOptions(reasoning: "low"),
              state.codexOptions(model: "fixture-vision", vision: false).reasoning == "high" else { throw failure("Vision and cleanup options leaked") }
        try choose("cleanup.provider", "openrouter")
        let previous = state.processingModel
        guard let field = pane.controls["cleanup.model"] as? NSTextField, let save = pane.controls["cleanup.model.save"] as? NSButton else { throw failure("Model editor missing") }
        if #available(macOS 26, *) {
            guard save.bezelStyle == .glass, save.borderShape == .capsule,
                  (pane.controls["cleanup.provider"] as? NSPopUpButton)?.bezelStyle == .glass else { throw failure("Model controls must use native Liquid Glass") }
        }
        field.stringValue = "cerebras/fp16"; save.performClick(nil)
        guard state.processingModel == previous else { throw failure("Hosting endpoint accepted as model") }
        field.stringValue = "fixture/selected"; save.performClick(nil)
        guard state.processingModel == "fixture/selected", AppState(preview: true).processingModel == "fixture/selected" else { throw failure("Model Save failed") }
        controller.refresh()
        window.contentView?.layoutSubtreeIfNeeded()
        guard !window.isVisible, controller.showingModels, !controller.preview.running,
              controller.sectionBar.isHiddenOrHasHiddenAncestor,
              controller.sidebar.table.numberOfRows == 8, pane.view.bounds.width > 400,
              pane.view.bounds.height > 450, state.phase == .idle else { throw failure("Models window geometry or isolation failed: visible=\(window.isVisible), showing=\(controller.showingModels), preview=\(controller.preview.running), sectionHidden=\(controller.sectionBar.isHiddenOrHasHiddenAncestor), rows=\(controller.sidebar.table.numberOfRows), bounds=\(pane.view.bounds), phase=\(state.phase)") }
        for (id, control) in pane.controls where !control.isHiddenOrHasHiddenAncestor {
            let frame = control.convert(control.bounds, to: pane.view)
            guard control.bounds.width >= 25, frame.minX >= 0, frame.maxX <= pane.view.bounds.width else { throw failure("Clipped model control: \(id) \(frame)") }
        }
        state.phase = .recording
        pane.rebuild()
        guard pane.controls.values.allSatisfy({ !$0.isEnabled }) else { throw failure("Models can change during dictation") }
        state.phase = .idle
        pane.rebuild()
        guard let scroll = pane.view as? NSScrollView, let document = scroll.documentView,
              document.bounds.height > scroll.bounds.height else { throw failure("Model controls must scroll") }
        controller.sidebar.select(.bottom)
        guard !controller.showingModels, pane.view.isHidden, controller.previewHost?.isHidden == false else { throw failure("Return to Appearance failed") }
        print("Models window verified: hidden native controls, catalog filtering, reasoning and fast capability checks, per-model/task persistence, model Save, scroll layout and appearance navigation. No live providers or screen capture.")
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "ModelsWindowProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
