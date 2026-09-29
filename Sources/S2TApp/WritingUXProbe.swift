import AppKit
import SwiftUI
import S2TCore

@MainActor enum WritingUXProbe {
    static func run(state: AppState) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("S2T-writing-ux-" + UUID().uuidString)
        let transport = WritingUXTransport()
        let pane = WritingPane(state: state, directory: directory, api: DictationAPI(transport: transport))
        let editing = pane.editing
        editing.settings.provider = "openrouter"; editing.settings.routerModel = "fixture/writing"; editing.settings.host = ""
        state.routerKey = "fixture-writing-key"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 760), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        defer { editing.cancel(); window.close() }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "WritingUXProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func layout() async throws {
            try await Task.sleep(for: .milliseconds(70))
            window.contentView?.layoutSubtreeIfNeeded()
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func wait() async throws {
            for _ in 0..<200 where editing.busy || editing.diffPending { try await Task.sleep(for: .milliseconds(10)) }
            try require(!editing.busy && !editing.diffPending, "Writing request or comparison did not finish")
        }
        let initial = editing.text
        try require(editing.addRules(["Use British spelling."]), "Quick rule was rejected")
        try require(!editing.dirty && (try WritingDocumentFile(directory: directory, kind: .instructions).read()) == editing.text,
                    "Quick rule was not atomically saved")
        try require(editing.text.hasPrefix(initial), "Quick rule altered the original instructions")
        editing.text += "\nManual draft\n"
        let disk = try WritingDocumentFile(directory: directory, kind: .instructions).read()
        try require(editing.addRules(WritingRules.templates[0].rules), "Template was rejected")
        try require(editing.dirty && (try WritingDocumentFile(directory: directory, kind: .instructions).read()) == disk,
                    "Template unexpectedly saved an existing draft")
        editing.selection = .dictionary
        try require(editing.addDictionaryEntry(term: "S2T", context: "Our app", replaces: "S to T"), "Dictionary correction failed")
        try require(!editing.dirty && (try WritingDocumentFile(directory: directory, kind: .dictionary).read()) == editing.text,
                    "Dictionary addition was not saved")
        let entry = editing.dictionaryEntries[0]
        try await layout()
        guard let termField = descendants(pane.view).compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "S2T" }) else {
            throw NSError(domain: "WritingUXProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing native dictionary word field"])
        }
        window.makeFirstResponder(termField)
        try await layout()
        if let fieldEditor = window.fieldEditor(false, for: termField) as? NSTextView {
            fieldEditor.selectAll(nil)
            fieldEditor.insertText("S2T app", replacementRange: fieldEditor.selectedRange())
            window.makeFirstResponder(nil)
        }
        try await layout()
        try require(editing.dictionaryEntries.first?.term == "S2T app" && !editing.dirty && editing.error.isEmpty,
                    "Native dictionary blur did not save the edited word: term=\(editing.dictionaryEntries.first?.term ?? "nil"), dirty=\(editing.dirty), error=\(editing.error)")
        let renamed = editing.dictionaryEntries[0]
        editing.updateDictionaryEntry(renamed, term: entry.term, context: "", replaces: "speech to tea")
        try require(!editing.dirty && editing.dictionaryEntries[0].learnedFrom == "speech to tea", "Dictionary spelling edit not persisted")
        editing.removeDictionaryEntry(editing.dictionaryEntries[0])
        try require(!editing.dirty && editing.dictionaryEntries.isEmpty, "Dictionary removal not persisted")
        let external = "# Dictionary\n- External word\n"
        try external.write(to: directory.appendingPathComponent("dictionary.md"), atomically: true, encoding: .utf8)
        try require(!editing.addDictionaryEntry(term: "Keep my draft", context: ""), "External dictionary conflict was ignored")
        try require(editing.dirty && editing.text.contains("Keep my draft") && !editing.error.isEmpty,
                    "External conflict discarded the user's edit")
        try require(try WritingDocumentFile(directory: directory, kind: .dictionary).read() == external, "External file was overwritten")

        editing.selection = .instructions
        editing.text = "Original rules.\n"; editing.save()
        editing.showingAssistant = true
        editing.instruction = "First revision"
        editing.improve()
        try await layout()
        try require(editing.busy && editing.startedAt != nil, "Missing observable working state")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require(descendants(pane.view).contains { ($0 as? NSProgressIndicator)?.accessibilityIdentifier() == "writing.activity.spinner" },
                        "AI working state did not mount a native animated spinner")
        }
        try await wait(); try await layout()
        try require(editing.review == .changes && editing.diff?.changeCount == 1 && editing.suggestion == "First suggestion.\n",
                    "First suggestion did not open its comparison")
        try require(descendants(pane.view).contains { ($0 as? NSTextView)?.accessibilityIdentifier() == "writing.diff" }, "Changes review not mounted")
        try require(descendants(pane.view).contains { $0 is WritingPromptTextView }, "Review hid the follow-up composer")
        let baseline = editing.text
        editing.instruction = "Refine this suggestion"
        editing.improve(); try await wait()
        let request = await transport.requests.last!
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        try require(body.contains("First suggestion.") && !body.contains("Original rules."), "Follow-up request ignored the reviewed suggestion")
        try require(editing.text == baseline && editing.suggestion == "Refined suggestion.\n", "Refining modified the original before apply")
        let suggestion = editing.suggestion
        editing.instruction = "Cancelled revision"
        editing.improve(); editing.stopTask()
        try await Task.sleep(for: .milliseconds(320))
        try require(!editing.busy && editing.startedAt == nil && editing.suggestion == suggestion,
                    "Stopped request discarded review or accepted a late result")
        editing.settings.host = "fixture/host"
        try require(editing.suggestion == suggestion, "Changing model options discarded the review")
        editing.applySuggestion()
        try require(editing.text == suggestion && !editing.dirty, "Apply did not save the refined suggestion")
        editing.improve()
        try await Task.sleep(for: .milliseconds(30))
        editing.text = "Newer manual draft.\n"
        try await Task.sleep(for: .milliseconds(320))
        try require(editing.suggestion == nil && editing.text == "Newer manual draft.\n", "Late result replaced newer manual edits")

        let layoutChoices = (1...12).map { index in
            WritingModelChoice(provider: .codex, model: "fixture-\(index)", title: index == 1 ? "A very long model name that must fit within the compact menu" : "Model \(index)")
        }
        let layoutPicker = WritingModelPickerController(editing: editing, choices: layoutChoices, close: {})
        let pickerWindow = NSWindow(contentRect: NSRect(origin: .zero, size: WritingModelPickerController.size), styleMask: [.borderless], backing: .buffered, defer: true)
        pickerWindow.isReleasedWhenClosed = false
        pickerWindow.contentViewController = layoutPicker
        defer { pickerWindow.close() }
        layoutPicker.filter("", group: "codex")
        pickerWindow.contentView?.layoutSubtreeIfNeeded()
        let searchBounds = layoutPicker.search.convert(layoutPicker.search.bounds, to: layoutPicker.view)
        let modelScroll = layoutPicker.table.enclosingScrollView!
        try require(searchBounds.minX < layoutPicker.view.bounds.width * 0.2 && searchBounds.width > layoutPicker.view.bounds.width * 0.75,
                    "Model picker rail expanded into a wide empty gutter")
        try require(modelScroll.bounds.width > layoutPicker.view.bounds.width * 0.8,
                    "Model list is squeezed by provider navigation")
        let providerButtons = descendants(layoutPicker.view).compactMap { $0 as? NSButton }.filter { $0.identifier?.rawValue == "codex" || $0.identifier?.rawValue == "favorites" }
        let providerDescription = descendants(layoutPicker.view).compactMap { $0 as? NSButton }.map { "\($0.identifier?.rawValue ?? "nil") \($0.convert($0.bounds, to: layoutPicker.view)) bordered=\($0.isBordered)" }.joined(separator: "; ")
        try require(providerButtons.count == 2 && providerButtons.allSatisfy { button in
            let frame = button.convert(button.bounds, to: layoutPicker.view)
            return !button.isBordered && frame.width == frame.height && frame.maxX <= WritingModelPickerController.railWidth
        }, "Provider controls lost their compact borderless rail: " + providerDescription)
        try require(layoutPicker.table.rect(ofRow: 0).height <= 36 && layoutPicker.table.rect(ofRow: 7).maxY <= modelScroll.bounds.height,
                    "Compact provider list cannot show eight model rows")
        let labels = descendants(layoutPicker.view).compactMap { $0 as? NSTextField }.map(\.stringValue)
        try require(!labels.contains(where: { $0.contains("Codex ·") || $0.contains("Uses your provider") || $0.contains("to browse") }),
                    "Picker restored redundant per-model IDs or a tutorial footer")
        layoutPicker.filter("Model 2")
        pickerWindow.contentView?.layoutSubtreeIfNeeded()
        try require(layoutPicker.table.rect(ofRow: 0).height <= 48, "Search result rows became oversized")
        guard let cursorSurface = layoutPicker.view as? WritingModelPickerSurface else {
            throw NSError(domain: "WritingUXProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Picker does not own its non-text cursor regions"])
        }
        var simulatedCursorIsArrow = false
        cursorSurface.setArrowCursor = { simulatedCursorIsArrow = true }
        cursorSurface.updateTrackingAreas()
        let textRegion = layoutPicker.search.convert(layoutPicker.search.bounds, to: cursorSurface)
        let textPoint = NSPoint(x: textRegion.midX, y: textRegion.midY)
        try require(!cursorSurface.arrowCursorRegions.contains { $0.contains(textPoint) }, "Arrow cursor overrides search editing")
        let cursorPoints = providerButtons.map { button -> NSPoint in
            let frame = button.convert(button.bounds, to: cursorSurface)
            return NSPoint(x: frame.midX, y: frame.midY)
        } + [NSPoint(x: 2, y: 2), modelScroll.convert(NSPoint(x: modelScroll.bounds.midX, y: modelScroll.bounds.midY), to: cursorSurface)]
        for point in cursorPoints {
            simulatedCursorIsArrow = false // Simulate arrival from an editor's I-beam.
            let location = cursorSurface.convert(point, to: nil)
            let event = NSEvent.enterExitEvent(with: .cursorUpdate, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: pickerWindow.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            cursorSurface.cursorUpdate(with: event)
            try require(simulatedCursorIsArrow && cursorSurface.trackingAreas.contains { $0.options.contains(.cursorUpdate) && $0.rect.contains(point) },
                        "Moving from search to picker controls retained the text cursor")
        }
        try require(layoutPicker.search.isEditable && cursorSurface.arrowCursorRegions.allSatisfy { !$0.intersects(textRegion) },
                    "Picker arrow regions overlap the native search field")
        try require(!pickerWindow.isVisible, "Picker layout check showed a window")

        let picker = WritingModelPickerController(editing: editing, choices: editing.modelChoices, close: {})
        _ = picker.view
        picker.filter("", group: "openrouter")
        let before = picker.table.selectedRow
        _ = picker.control(picker.search, textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        try require(picker.table.selectedRow == min(before + 1, picker.visibleChoices.count - 1), "Picker arrow keys did not move selection")
        let picked = picker.visibleChoices[picker.table.selectedRow]
        _ = picker.control(picker.search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        try require(editing.selectedModelID == picked.id, "Picker Return did not select the focused model")
        editing.toggleFavorite("openrouter|fixture/favorite")
        let restored = WritingEditor(state: state, directory: directory)
        try require(restored.favorites.contains("openrouter|fixture/favorite") && restored.modelChoices.contains { $0.id == "openrouter|fixture/favorite" },
                    "Custom favorite did not survive reopening")
        try require(!window.isVisible, "Writing UX check showed a window")
        print("PASS: Writing quick rules/templates, dictionary autosave and conflicts, native busy animation, three-way comparison, follow-up source, stop/stale-result guards, provider picker keyboard actions and persistent custom favorites.")
    }
}

private actor WritingUXTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let index = requests.count
        // Deliberately return even after cancellation to exercise stale-result guards.
        try? await Task.sleep(for: .milliseconds(260))
        let result = index == 1 ? "First suggestion.\n" : index == 2 ? "Refined suggestion.\n" : "Stale result.\n"
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": result]]]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
