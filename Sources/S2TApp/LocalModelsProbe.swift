import AppKit
import S2TCore

@MainActor enum LocalModelsProbe {
    static func repair() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-repair-check-" + UUID().uuidString)
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("runtime/bin"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("models/fixture"), withIntermediateDirectories: true)
        try manager.createDirectory(at: root.appendingPathComponent("uv-aarch64-apple-darwin"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let catalog = #"[{"id":"fixture","name":"Fixture","category":"text","repository":"mlx-community/fixture","revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","speed":1,"quality":1,"memoryGB":0.001,"diskGB":0.001,"details":"Fixture","license":"Fixture"}]"#
        try Data(catalog.utf8).write(to: root.appendingPathComponent("catalog.json"))
        try Data(#"{"revision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8).write(to: root.appendingPathComponent("models/fixture/installed.json"))
        try Data("ready".utf8).write(to: root.appendingPathComponent("runtime/ready-v3"))
        let python = root.appendingPathComponent("runtime/bin/python3")
        try """
        #!/bin/sh
        root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
        echo $$ > "$root/worker.pid"
        trap '' TERM
        echo '{"endpoint":"http://127.0.0.1:1/fixture/v1"}'
        exec /bin/sleep 120
        """.write(to: python, atomically: true, encoding: .utf8)
        let uv = root.appendingPathComponent("uv-aarch64-apple-darwin/uv")
        try """
        #!/bin/sh
        root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
        if kill -0 "$(cat "$root/worker.pid")" 2>/dev/null; then touch "$root/overlap"; exit 90; fi
        if [ -f "$root/runtime/ready-v3" ]; then touch "$root/stale-ready"; exit 91; fi
        touch "$root/installer-started"
        while [ ! -f "$root/finish-install" ]; do /bin/sleep 0.02; done
        exit 72
        """.write(to: uv, atomically: true, encoding: .utf8)
        for executable in [python, uv] { try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path) }
        let local = LocalModels(resources: root, root: root)
        defer { local.stop() }
        guard let model = local.catalog.first(where: { $0.id == "fixture" }) else { throw ServiceError.message("Repair fixture catalog failed") }
        _ = try await local.url(for: model.id, path: "/chat/completions")
        local.repair(model)
        guard local.isRepairing else { throw ServiceError.message("Repair did not reserve the runtime") }
        let suite = "s2t-repair-state-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let state = AppState(preview: true, previewPreferences: preferences)
        state.localModels = local
        state.mode = .verbatim; state.speechUsesCredits = false
        state.transcriptionProvider = .local
        state.localTranscriptionURL = LocalModels.managedEndpoint
        state.localTranscriptionModel = "parakeet"
        guard !state.canRecord else { throw ServiceError.message("Dictation remained enabled for a repairing managed speech model") }
        state.localTranscriptionModel = "apple-speech-en-US"
        guard state.canRecord else { throw ServiceError.message("Managed repair blocked independent Apple speech") }
        state.mode = .clean; state.cleanupUsesCredits = false
        state.processingProvider = .local
        state.localProcessingURL = LocalModels.managedEndpoint
        guard !state.canRecord else { throw ServiceError.message("Dictation remained enabled for managed cleanup during repair") }
        var blocked = false
        do { _ = try await local.url(for: model.id, path: "/chat/completions") } catch { blocked = true }
        guard blocked else { throw ServiceError.message("Inference started during repair") }
        for _ in 0..<200 where !manager.fileExists(atPath: root.appendingPathComponent("installer-started").path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard manager.fileExists(atPath: root.appendingPathComponent("installer-started").path),
              !manager.fileExists(atPath: root.appendingPathComponent("overlap").path),
              !manager.fileExists(atPath: root.appendingPathComponent("stale-ready").path) else {
            throw ServiceError.message("Runtime mutation overlapped the old worker or kept a stale completion marker")
        }
        try Data().write(to: root.appendingPathComponent("finish-install"))
        for _ in 0..<200 where local.installing != nil { try await Task.sleep(for: .milliseconds(10)) }
        guard local.installing == nil, !local.isRepairing, local.message.contains("Installation failed") else {
            throw ServiceError.message("Failed repair did not end cleanly")
        }
        blocked = false
        do { _ = try await local.url(for: model.id, path: "/chat/completions") } catch { blocked = true }
        guard blocked else { throw ServiceError.message("Failed runtime repair was reused") }
        let modelFolder = root.appendingPathComponent("models/fixture")
        try manager.moveItem(at: modelFolder, to: root.appendingPathComponent("models/fixture.previous"))
        local.refreshInstalled()
        guard local.installed.contains(model.id), manager.fileExists(atPath: modelFolder.appendingPathComponent("installed.json").path) else {
            throw ServiceError.message("An interrupted model-folder replacement did not restore the previous download")
        }
        print("PASS: repair waits for the old worker, blocks concurrent inference, clears stale readiness and refuses failed runtimes. Temporary scripts only; no downloads or models.")
    }

    static func runtime() async throws {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--local-fixture-root"), args.indices.contains(index + 1) else {
            throw ServiceError.message("Pass an isolated --local-fixture-root containing the test runtime and generated audio.")
        }
        let root = URL(fileURLWithPath: args[index + 1]).standardizedFileURL
        let marker = root.appendingPathComponent("s2t-verification-fixture")
        guard FileManager.default.fileExists(atPath: marker.path) else { throw ServiceError.message("Fixture marker missing.") }
        let local = LocalModels(root: root)
        defer { local.stop() }
        let api = DictationAPI()
        let speechURL = try await local.url(for: "qwen-asr", path: "/audio/transcriptions")
        let transcript = try await api.transcribe(audio: Data(contentsOf: root.appendingPathComponent("fixture.wav")),
            apiKey: "", provider: .local, model: "qwen-asr", localURL: speechURL)
        guard transcript.lowercased().contains("blue square") else { throw ServiceError.message("Packaged local speech failed.") }
        let textURL = try await local.url(for: "qwen-small", path: "/chat/completions")
        let result = try await api.process(text: "the cat is sleeping.", mode: .clean, model: "qwen-small", apiKey: "", provider: .local,
            instructions: "Correct capitalization. Return only the corrected text.", localURL: textURL)
        guard result.text.lowercased().contains("cat"), result.host == "On this Mac" else { throw ServiceError.message("Packaged local cleanup failed.") }
        local.cancelInference()
        let restarted = try await local.url(for: "qwen-small", path: "/chat/completions")
        guard restarted != textURL else { throw ServiceError.message("Worker did not restart with a new private endpoint.") }
        print("PASS: packaged worker startup, native URLSession speech and cleanup, cancellation and restart with isolated models and generated audio.")
    }

    static func run() throws {
        try ModelProviderProbe.run()
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        guard !state.localModels.catalog.isEmpty else { throw ServiceError.message("Run this check from build/S2T.app, which includes the model catalog.") }
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        (controller.modelsPane.controls["models.local"] as? NSButton)?.performClick(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        let pane = controller.modelsPane.localPane
        guard controller.showingModels, controller.modelsPane.navigation.page == .local, !pane.view.isHiddenOrHasHiddenAncestor, !controller.preview.running, pane.selectedCategory == "speech",
              pane.table.tableColumns.map(\.title) == ["Model"],
              state.localModels.installed.isEmpty else { throw ServiceError.message("Local settings navigation or preview isolation failed.") }
        guard controller.sidebar.table.selectedRow == controller.sidebar.modelsRow,
              !pane.isBrowsing,
              !pane.overviewGroup.isHiddenOrHasHiddenAncestor,
              pane.table.isHiddenOrHasHiddenAncestor,
              pane.compareButton.isHiddenOrHasHiddenAncestor,
              pane.overviewChooseButtons.count == 2,
              pane.overviewChooseButtons.allSatisfy({ !$0.isHiddenOrHasHiddenAncestor && $0.isEnabled }),
              pane.comparison?.isHiddenOrHasHiddenAncestor == true,
              pane.compareButton.title == "Compare performance" else {
            throw ServiceError.message("Local models should open with two task choices, leaving the browser and comparison hidden.")
        }
        let initialSize = pane.view.frame.size
        for width in [420.0, 600.0] {
            pane.view.setFrameSize(NSSize(width: width, height: initialSize.height))
            pane.view.layoutSubtreeIfNeeded()
            guard pane.overviewGroup.frame.width > 300,
                  pane.overviewChooseButtons.allSatisfy({ button in
                      button.superview?.bounds.contains(button.frame) == true && button.bounds.width >= 55
                  }) else {
                throw ServiceError.message("Local task choices are clipped at width \(width).")
            }
        }
        pane.view.setFrameSize(initialSize)
        pane.view.layoutSubtreeIfNeeded()
        pane.overviewChooseButtons[0].performClick(nil)
        guard pane.isBrowsing, pane.overviewGroup.isHiddenOrHasHiddenAncestor,
              !pane.table.isHiddenOrHasHiddenAncestor,
              pane.detail.isHiddenOrHasHiddenAncestor,
              !pane.backButton.isHiddenOrHasHiddenAncestor,
              pane.selectedCategory == "speech" else {
            throw ServiceError.message("Choosing a local task did not open its model browser.")
        }
        pane.backButton.performClick(nil)
        guard !pane.isBrowsing, pane.table.isHiddenOrHasHiddenAncestor,
              !pane.overviewGroup.isHiddenOrHasHiddenAncestor else {
            throw ServiceError.message("Local browser Back did not restore the small task summary.")
        }
        pane.overviewChooseButtons[1].performClick(nil)
        guard pane.isBrowsing, pane.selectedCategory == "text", !pane.table.isHiddenOrHasHiddenAncestor,
              pane.detail.isHiddenOrHasHiddenAncestor else {
            throw ServiceError.message("The text task did not open the correct local catalog.")
        }
        pane.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        pane.table.sendAction(pane.table.action, to: pane.table.target)
        guard pane.isShowingDetail, !pane.detail.isHiddenOrHasHiddenAncestor,
              pane.table.isHiddenOrHasHiddenAncestor, !pane.detailBackButton.isHiddenOrHasHiddenAncestor else {
            throw ServiceError.message("Selecting a model should open its details on a separate page.")
        }
        pane.detailBackButton.performClick(nil)
        guard !pane.isShowingDetail, !pane.table.isHiddenOrHasHiddenAncestor,
              pane.detail.isHiddenOrHasHiddenAncestor else {
            throw ServiceError.message("Model details Back did not restore the catalog.")
        }
        for (index, kind) in ["speech", "text"].enumerated() {
            pane.taskPicker.selectItem(at: index)
            pane.taskPicker.sendAction(pane.taskPicker.action, to: pane.taskPicker.target)
            pane.refresh()
            guard pane.selectedCategory == kind,
                  pane.rows.allSatisfy({ $0.category == kind }),
                  pane.table.numberOfRows == state.localModels.catalog.filter({ $0.category == kind && !$0.isNative }).count,
                  pane.taskSelection.index == index,
                  zip(pane.rows, pane.rows.dropFirst()).allSatisfy({ $0.memoryGB <= $1.memoryGB }) else {
                throw ServiceError.message("Native task picker or ranking failed for " + kind)
            }
        }
        pane.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        pane.table.sendAction(pane.table.action, to: pane.table.target)
        pane.compareButton.performClick(nil)
        guard pane.comparison?.isHiddenOrHasHiddenAncestor == false,
              pane.compareButton.title == "Hide comparison" else {
            throw ServiceError.message("Model comparison does not open on request.")
        }
        guard pane.table.rowHeight <= 40, pane.table.headerView == nil else {
            throw ServiceError.message("Model browser must use compact single-column rows.")
        }
        for index in pane.rows.indices {
            pane.detailBackButton.performClick(nil)
            pane.table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            pane.table.sendAction(pane.table.action, to: pane.table.target)
            guard pane.detailModelID == pane.rows[index].id, pane.isShowingDetail else {
                throw ServiceError.message("Model selection did not update details.")
            }
        }
        guard let chart = pane.comparison, chart.rootView.models == pane.rows else {
            throw ServiceError.message("Comparison chart does not match the filtered list.")
        }
        for model in pane.rows {
            chart.rootView.select(model.id)
            guard pane.detailModelID == model.id, chart.rootView.selectedID == model.id else {
                throw ServiceError.message("Chart selection failed to update details.")
            }
        }
        pane.selectCategory(0)
        pane.searchField.stringValue = "Parakeet"
        pane.searchField.sendAction(pane.searchField.action, to: pane.searchField.target)
        guard pane.rows.map(\.id) == ["parakeet"], pane.detailModelID == "parakeet" else { throw ServiceError.message("Local model search did not filter the browser.") }
        pane.searchField.stringValue = ""
        pane.sortPicker.selectItem(at: 1)
        pane.sortPicker.sendAction(pane.sortPicker.action, to: pane.sortPicker.target)
        guard zip(pane.rows, pane.rows.dropFirst()).allSatisfy({ $0.diskGB <= $1.diskGB }) else { throw ServiceError.message("Download sorting is incorrect.") }
        pane.sortPicker.selectItem(at: 0)
        pane.selectCategory(1)
        pane.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        pane.table.sendAction(pane.table.action, to: pane.table.target)
        window.contentView?.layoutSubtreeIfNeeded()
        guard pane.detail.frame.height >= 90 && pane.detail.frame.height < 200, pane.detail.frame.width > 300,
              let parent = pane.detail.superview, parent.bounds.contains(pane.detail.frame),
              pane.table.enclosingScrollView?.frame.height ?? 0 >= 140 else {
            throw ServiceError.message("Model details or list are clipped: detail \(pane.detail.frame), parent \(String(describing: pane.detail.superview?.bounds)), table height \(pane.table.enclosingScrollView?.frame.height ?? 0).")
        }
        guard chart.frame.height >= 160 && chart.frame.height < 300, chart.frame.width > 300,
              pane.view is NSScrollView else {
            throw ServiceError.message("Chart layout or page scrolling failed.")
        }
        guard let actions = pane.detail.stack.arrangedSubviews.compactMap({ $0 as? NSStackView }).first,
              let source = actions.arrangedSubviews.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Details" }),
              source.identifier?.rawValue == pane.detailModelID,
              source.action != nil, source.target === pane,
              !source.isHiddenOrHasHiddenAncestor,
              actions.arrangedSubviews.allSatisfy({ !($0 is NSPopUpButton) }) else {
            throw ServiceError.message("Model details must be visible beside Install, without an options menu.")
        }
        for button in actions.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            if #available(macOS 26, *) {
                guard button.bezelStyle == .rounded, button.borderShape == .automatic, button.tintProminence == .none else {
                    throw ServiceError.message("Local model actions must use system buttons.")
                }
            }
            guard button.isBordered, button.appearance == nil,
                  button.contentTintColor == nil, button.bounds.height >= 24 else {
                throw ServiceError.message("Local model actions must match the native buttons in model settings.")
            }
        }
        let originalSize = pane.view.frame.size
        pane.detailBackButton.performClick(nil)
        for width in [420.0, 600.0] {
            pane.view.setFrameSize(NSSize(width: width, height: originalSize.height))
            pane.view.layoutSubtreeIfNeeded()
            guard let toolbar = pane.taskPicker.superview,
                  [pane.taskPicker, pane.searchField, pane.sortPicker].allSatisfy({ toolbar.bounds.contains($0.frame) }),
                  pane.searchField.frame.width >= 80,
                  abs(pane.taskPicker.frame.midY - pane.searchField.frame.midY) < 1,
                  pane.taskPicker.frame.maxX < pane.searchField.frame.minX,
                  pane.searchField.frame.maxX < pane.sortPicker.frame.minX,
                  let cell = pane.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView,
                  cell.textField?.stringValue == pane.rows.first?.name else {
                throw ServiceError.message("Native local browser controls overlap or lose their accessible model cell at width \(width).")
            }
        }
        pane.compareButton.performClick(nil)
        guard pane.comparison?.isHiddenOrHasHiddenAncestor == true,
              pane.compareButton.title == "Compare performance" else {
            throw ServiceError.message("Model comparison does not close without changing the selected model.")
        }
        pane.view.setFrameSize(originalSize)
        pane.view.layoutSubtreeIfNeeded()
        let original = state.transcriptionProvider
        state.localModels.install(state.localModels.catalog[0])
        state.localModels.use(state.localModels.catalog[0], state: state)
        guard state.localModels.installing == nil, state.transcriptionProvider == original else {
            throw ServiceError.message("Preview attempted a real installation or selected an absent model.")
        }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-local-probe-" + UUID().uuidString)
        let isolated = LocalModels(preview: true, root: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        isolated.discard = { try FileManager.default.removeItem(at: $0) }
        for model in isolated.catalog {
            let directory = fixture.appendingPathComponent("models/" + model.id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["revision": model.revision]).write(to: directory.appendingPathComponent("installed.json"))
        }
        isolated.refreshInstalled()
        for category in ["speech", "text"] {
            let model = isolated.catalog.first { $0.category == category }!
            isolated.use(model, state: state)
            let actual = category == "speech" ? state.localTranscriptionModel : state.processingModel
            guard actual == model.id else { throw ServiceError.message("Installed model selection failed for " + category) }
        }
        pane.refresh()
        guard pane.overviewStatus.allSatisfy({ $0.stringValue.hasPrefix("Using ") }) else {
            throw ServiceError.message("Local task summary did not show the selected models.")
        }
        try verifyInstalledList(state: state, isolated: isolated, fixture: fixture)
        state.phase = .recording
        let before = state.processingModel
        isolated.use(isolated.catalog.first { $0.category == "text" && $0.id != before }!, state: state)
        guard state.processingModel == before else { throw ServiceError.message("Model changed during recording.") }
        state.phase = .idle
        controller.modelsPane.navigation.select(.cleanup)
        guard controller.modelsPane.navigation.section == .cleanup, controller.showingModels, pane.view.isHidden,
              !controller.modelsPane.scroll.isHidden else { throw ServiceError.message("Local pane did not hide on navigation.") }
        print("PASS: Local settings table, task filters, navigation, preview isolation, installed selection and recording guard. Hidden controls only; no screen capture or real model inference.")
    }

    /// Checks the "On this Mac" list against an isolated fixture: names, sources, in-use guards, partial downloads and removal.
    private static func verifyInstalledList(state: AppState, isolated: LocalModels, fixture: URL) throws {
        func settle(_ done: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        let emptyState = AppState(preview: true)
        let emptyPane = LocalModelsPane(state: emptyState)
        emptyPane.view.setFrameSize(NSSize(width: 600, height: 700))
        guard emptyPane.installedRowIDs.isEmpty, emptyState.localModels.summary == "None installed",
              !emptyPane.installedGroup.isHiddenOrHasHiddenAncestor else {
            throw ServiceError.message("An empty Mac must say that nothing is installed.")
        }
        let spare = isolated.catalog.first { model in !["speech", "text"].contains { state.managedLocalModelID(for: $0) == model.id } }!
        let partialModel = spare
        let partialMarker = fixture.appendingPathComponent("models/\(partialModel.id)/installed.json")
        try FileManager.default.removeItem(at: partialMarker)
        try Data(count: 4096).write(to: fixture.appendingPathComponent("models/\(partialModel.id)/weights.safetensors"))
        isolated.refreshInstalled()
        settle { isolated.partial[partialModel.id] != nil }
        state.localModels = isolated
        let pane = LocalModelsPane(state: state)
        var confirmations = 0
        pane.confirmRemoval = { _, done in confirmations += 1; done(true) }
        pane.view.setFrameSize(NSSize(width: 420, height: 900))
        pane.view.layoutSubtreeIfNeeded()
        let downloaded = isolated.downloadedModels.map(\.id)
        guard !downloaded.contains(partialModel.id), Set(pane.installedRowIDs) == Set(downloaded + [partialModel.id]),
              isolated.summary == "\(downloaded.count) downloaded" else {
            throw ServiceError.message("On this Mac must list every completed download and the unfinished one, with an accurate summary. Got \(pane.installedRowIDs), \(isolated.summary).")
        }
        for category in ["speech", "text"] {
            let id = state.managedLocalModelID(for: category)!
            guard pane.removeButtons[id]?.isEnabled == false, pane.useButtons[id] == nil else {
                throw ServiceError.message("A model in use must not be removable.")
            }
        }
        guard let partialRemove = pane.removeButtons[partialModel.id], partialRemove.isEnabled,
              let free = downloaded.first(where: { id in !["speech", "text"].contains { state.managedLocalModelID(for: $0) == id } }),
              pane.useButtons[free]?.isEnabled == true, let freeRemove = pane.removeButtons[free], freeRemove.isEnabled else {
            throw ServiceError.message("Unused and unfinished downloads need Use and Remove actions.")
        }
        for button in [freeRemove, partialRemove] {
            guard pane.installedGroup.bounds.contains(button.convert(button.bounds, to: pane.installedGroup)) else {
                throw ServiceError.message("Installed-model actions are clipped at 420 points.")
            }
        }
        freeRemove.performClick(nil)
        partialRemove.performClick(nil)
        guard confirmations == 2, !isolated.installed.contains(free),
              !FileManager.default.fileExists(atPath: fixture.appendingPathComponent("models/" + free).path),
              !FileManager.default.fileExists(atPath: fixture.appendingPathComponent("models/" + partialModel.id).path) else {
            throw ServiceError.message("Remove did not ask first or did not delete the fixture download.")
        }
        settle { isolated.partial[partialModel.id] == nil }
        guard !pane.installedRowIDs.contains(free), !pane.installedRowIDs.contains(partialModel.id) else {
            throw ServiceError.message("Removed models still appear under On this Mac.")
        }
    }
}
