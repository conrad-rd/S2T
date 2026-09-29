import AppKit
import S2TCore

@MainActor enum WritingPaneProbe {
    static func run() async throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        preferences.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        try await verifyCancelledPermission()
        let draftDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-draft-recovery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: draftDirectory) }
        let firstEditor = WritingEditor(state: state, directory: draftDirectory)
        let savedInstructions = firstEditor.text
        firstEditor.text = "Unsaved α😀 instructions\n"
        firstEditor.selection = .dictionary
        firstEditor.text = "Unsaved dictionary\n"
        let restoredEditor = WritingEditor(state: state, directory: draftDirectory)
        guard restoredEditor.text == "Unsaved α😀 instructions\n", restoredEditor.dirty,
              restoredEditor.drafts[.dictionary] == "Unsaved dictionary\n",
              try WritingDocumentFile(directory: draftDirectory, kind: .instructions).read() == savedInstructions else {
            throw failure("Unsaved writing drafts were lost or silently replaced saved documents")
        }
        try "External edit\n".write(to: draftDirectory.appendingPathComponent(WritingDocumentKind.instructions.filename), atomically: true, encoding: .utf8)
        let conflictEditor = WritingEditor(state: state, directory: draftDirectory)
        conflictEditor.save()
        guard conflictEditor.dirty, !conflictEditor.error.isEmpty,
              try WritingDocumentFile(directory: draftDirectory, kind: .instructions).read() == "External edit\n" else {
            throw failure("Recovered draft overwrote an external edit")
        }
        restoredEditor.selection = .dictionary
        restoredEditor.save()
        guard !restoredEditor.dirty,
              try WritingDraftStore(directory: draftDirectory).load()[.dictionary] == nil else {
            throw failure("Explicit Save did not retire the recovered draft")
        }
        let legacySettings = Data(#"{"provider":"openrouter","routerModel":"fixture/old-model","codexModel":"old-codex","host":"fixture/host","routerOptions":{},"codexOptions":{}}"#.utf8)
        var migrated = try JSONDecoder().decode(WritingAISettings.self, from: legacySettings)
        migrated.provider = "xai"; migrated.model = "grok-4.6"
        migrated.provider = "local"; migrated.model = "fixture-local"
        migrated.provider = "openrouter"
        guard migrated.model == "fixture/old-model", migrated.host == "fixture/host", migrated.codexModel == "old-codex",
              migrated.extraModels?["xai"] == "grok-4.6", migrated.extraModels?["local"] == "fixture-local" else { throw failure("New writing providers reset existing settings or shared model IDs") }
        let unicode = WritingTextDocument()
        unicode.update(text: "α😀\r\n\tbeta\n\n", editable: true, label: "Fixture", identifier: "fixture")
        guard unicode.textView.string == "α😀\r\n\tbeta\n\n", !unicode.scrollView.hasVerticalRuler,
              unicode.scrollView.verticalRulerView == nil else {
            throw failure("Editor changed exact text or restored the overlapping line-number ruler")
        }
        let markdown = WritingTextDocument()
        let markdownSource = "# Heading\n\nUse **bold** and `code`.\n\n- Item\n"
        markdown.update(text: markdownSource, editable: true, label: "Markdown", identifier: "markdown")
        let markdownText = markdownSource as NSString
        let headingRange = markdownText.range(of: "Heading")
        let boldRange = markdownText.range(of: "bold")
        let codeRange = markdownText.range(of: "code")
        let headingAttributes = markdown.textView.layoutManager?.temporaryAttributes(atCharacterIndex: headingRange.location, effectiveRange: nil) ?? [:]
        let boldAttributes = markdown.textView.layoutManager?.temporaryAttributes(atCharacterIndex: boldRange.location, effectiveRange: nil) ?? [:]
        let codeAttributes = markdown.textView.layoutManager?.temporaryAttributes(atCharacterIndex: codeRange.location, effectiveRange: nil) ?? [:]
        guard (headingAttributes[.font] as? NSFont).map({ NSFontManager.shared.traits(of: $0).contains(.boldFontMask) }) == true,
              (boldAttributes[.font] as? NSFont).map({ NSFontManager.shared.traits(of: $0).contains(.boldFontMask) }) == true,
              codeAttributes[.backgroundColor] is NSColor, markdown.textView.string == markdownSource else {
            throw failure("Markdown styling missed heading=\(headingAttributes), bold=\(boldAttributes), code=\(codeAttributes), exact=\(markdown.textView.string == markdownSource)")
        }
        markdown.textView.setSelectedRange(headingRange)
        markdown.format(.bold)
        guard markdown.textView.string == "# **Heading**\n\nUse **bold** and `code`.\n\n- Item\n",
              markdown.textView.selectedRange() == NSRange(location: 4, length: 7) else {
            throw failure("Markdown formatting did not preserve source editing or selection")
        }
        let markdownBenchmark = WritingTextDocument()
        let benchmarkSource = String(String(repeating: "## Heading\n- **Bold item** with `code` and [link](https://s2t.app).\n\n", count: 900).prefix(64_000))
        let markdownStart = ContinuousClock.now
        markdownBenchmark.update(text: benchmarkSource, editable: true, label: "Benchmark", identifier: "benchmark")
        let markdownMilliseconds = Double(markdownStart.duration(to: .now).components.attoseconds) / 1_000_000_000_000_000
        guard markdownMilliseconds < 500, markdownBenchmark.textView.string == benchmarkSource else {
            throw failure("Markdown styling took \(markdownMilliseconds) ms for a 64 KB document or changed its source")
        }
        print("Markdown 64 KB styling benchmark: \(String(format: "%.2f", markdownMilliseconds)) ms")
        let rendered = MarkdownPreviewRenderer.render("# Heading\n\nUse **bold** and `code` with [S2T](https://s2t.app).\n\n- First item\n\n> Quoted text")
        let renderedText = rendered.string as NSString
        let renderedHeading = renderedText.range(of: "Heading")
        let renderedBold = renderedText.range(of: "bold")
        let renderedCode = renderedText.range(of: "code")
        let renderedLink = renderedText.range(of: "S2T")
        guard !rendered.string.contains("# Heading"), !rendered.string.contains("**bold**"),
              rendered.string.contains("•\tFirst item"), rendered.string.contains("│\tQuoted text"),
              (rendered.attribute(.font, at: renderedHeading.location, effectiveRange: nil) as? NSFont)?.pointSize == 24,
              (rendered.attribute(.font, at: renderedBold.location, effectiveRange: nil) as? NSFont).map({ NSFontManager.shared.traits(of: $0).contains(.boldFontMask) }) == true,
              rendered.attribute(.backgroundColor, at: renderedCode.location, effectiveRange: nil) is NSColor,
              rendered.attribute(.link, at: renderedLink.location, effectiveRange: nil) as? URL == URL(string: "https://s2t.app") else {
            throw failure("Rendered Markdown preview kept source markers or lost block and inline formatting")
        }
        let promptKeys = WritingPromptTextView()
        var promptSubmits = 0
        promptKeys.onSubmit = { promptSubmits += 1 }
        promptKeys.string = "First line"
        guard !promptKeys.handleReturnForVerification(shift: true), promptKeys.string == "First line\n", promptSubmits == 0,
              promptKeys.handleReturnForVerification(shift: false), promptSubmits == 1 else {
            throw failure("Prompt composer did not keep Shift-Return for a newline and Return for submit")
        }
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showWriting()
        try await Task.sleep(nanoseconds: 100_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
        guard controller.showingWriting, !controller.showingModels, !controller.showingKeys,
              !controller.preview.running, !window.isVisible,
              controller.sidebar.table.selectedRow == controller.sidebar.writingRow,
              !controller.writingPane.view.isHidden, controller.controlsPanel.isHidden else {
            throw failure("Writing navigation or preview isolation failed")
        }
        let originalModel = state.processingModel
        guard let toolbar = controller.window?.toolbar,
              toolbar === controller.writingPane.nativeToolbar.toolbar,
              toolbar.items.contains(where: { $0.view is NSSegmentedControl }),
              toolbar.items.filter({ $0 is NSMenuToolbarItem }).count == 2,
              controller.window?.toolbarStyle == .unified else {
            throw failure("Instructions must use a native window toolbar with document and menu controls")
        }
        guard let previewAction = toolbar.items.first(where: { $0.itemIdentifier.rawValue == "writing.preview" }),
              previewAction.isBordered, let action = previewAction.action else {
            throw failure("The native toolbar must have bordered action buttons")
        }
        NSApp.sendAction(action, to: previewAction.target, from: previewAction)
        guard !controller.writingPane.editing.showingMarkdownPreview else {
            throw failure("The toolbar Edit action did not reveal the source editor")
        }
        NSApp.sendAction(action, to: previewAction.target, from: previewAction)
        controller.showRecentRecordings()
        guard controller.window?.toolbar === controller.pageToolbar.toolbar,
              controller.pageToolbar.title == "Recent recordings" else {
            throw failure("Recent recordings did not switch to its own page toolbar")
        }
        controller.showWriting()
        guard controller.window?.toolbar === toolbar else {
            throw failure("Returning to Instructions lost its native toolbar")
        }
        let transport = WritingProbeTransport()
        let codex = WritingProbeCodex()
        let promptCapture = WritingPromptCaptureProbe()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-writing-check-" + UUID().uuidString)
        let pane = WritingPane(state: state, directory: directory, api: DictationAPI(transport: transport, codex: codex),
            promptCapture: promptCapture, promptTranscriber: { _ in "Use concise Markdown headings." })
        let fixture = NSWindow(contentRect: NSRect(x: 0, y: 0, width: AppearanceWindowController.contentSize.width - AppearanceSidebarController.width - 1, height: AppearanceWindowController.contentSize.height), styleMask: [.titled], backing: .buffered, defer: true)
        fixture.isReleasedWhenClosed = false
        fixture.contentViewController = pane
        fixture.setContentSize(NSSize(width: AppearanceWindowController.contentSize.width - AppearanceSidebarController.width - 1, height: AppearanceWindowController.contentSize.height))
        pane.view.frame = fixture.contentView!.bounds
        defer { fixture.close() }
        fixture.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editing = pane.editing
        guard editing.showingMarkdownPreview, !editing.showingAssistant,
              descendants(pane.view).contains(where: { $0 === editing.promptPreview.textView }),
              descendants(pane.view).compactMap({ $0 as? WritingPromptTextView }).isEmpty else {
            throw failure("Instructions must open in preview with the AI editor collapsed")
        }
        let previewScroll = editing.promptPreview.scrollView
        guard previewScroll.bounds.height >= 500, previewScroll.documentView!.bounds.height > previewScroll.contentSize.height else {
            throw failure("Preview does not have a bounded scrolling document")
        }
        previewScroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        previewScroll.reflectScrolledClipView(previewScroll.contentView)
        let renders = editing.promptPreview.renderCount
        for _ in 0..<100 { editing.promptPreview.update(markdown: editing.text, label: "Instructions", identifier: "writing.preview") }
        guard editing.promptPreview.renderCount == renders, previewScroll.contentView.bounds.minY >= 100 else {
            throw failure("Unchanged preview updates rebuilt the document or reset scrolling")
        }
        editing.showingMarkdownPreview = false
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        let views = descendants(pane.view)
        guard let editor = views.compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable && !$0.isFieldEditor }),
              editor.enclosingScrollView!.bounds.height >= 400 else { throw failure("The visible assistant must leave at least 400 points of editing space") }
        guard editor.allowsUndo, editor.usesFindBar, !editor.isRichText,
              !editor.isAutomaticQuoteSubstitutionEnabled, !editor.isAutomaticDashSubstitutionEnabled,
              editor.enclosingScrollView?.hasVerticalRuler == false,
              editor.enclosingScrollView?.verticalRulerView == nil else {
            throw failure("Writing needs plain-text fidelity, undo and find/replace without an overlapping ruler")
        }
        let reasoningSettings = editing.settings
        let levels = ["", "none", "minimal", "low", "medium", "high", "xhigh", "max"]
        for model in ["openai/gpt-oss-120b", "openai/gpt-5.6-luna", "meta/muse-spark-1.3-contributor", "openai/gpt-4.1-mini", "fixture/unknown"] {
            editing.settings.routerModel = model
            editing.settings.router = .init(reasoning: .minimal)
            guard editing.reasoningChoices.map(\.0) == levels, levels.contains(editing.reasoning) else {
                throw failure("Writing lost explicit reasoning choices for \(model)")
            }
            let before = editing.reasoning
            editing.reasoning = "invented-level"
            guard editing.reasoning == before else { throw failure("Writing accepted a stale or invalid reasoning action") }
        }
        editing.settings = reasoningSettings
        editing.showingMarkdownPreview = true
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard let preview = descendants(pane.view).compactMap({ $0 as? MarkdownPreviewTextView }).first,
              !preview.isEditable, preview.isSelectable,
              preview.string == MarkdownPreviewRenderer.render(editing.text).string,
              !descendants(pane.view).contains(where: { $0 === editor }) else {
            throw failure("Preview mode did not replace source editing with rendered read-only Markdown")
        }
        editing.showingMarkdownPreview = false
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard descendants(pane.view).contains(where: { $0 === editor }) else {
            throw failure("Edit mode did not restore the Markdown source editor")
        }
        guard descendants(pane.view).compactMap({ $0 as? WritingPromptTextView }).isEmpty else {
            throw failure("AI prompt composer must start collapsed")
        }
        editing.showingAssistant = true
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard let request = descendants(pane.view).compactMap({ $0 as? WritingPromptTextView }).first,
              request.accessibilityIdentifier() == "writing.request",
              let requestScroll = request.enclosingScrollView, !request.isFieldEditor,
              requestScroll.convert(requestScroll.bounds, to: pane.view).minX < 50,
              requestScroll.convert(requestScroll.bounds, to: pane.view).maxX > pane.view.bounds.maxX - 50,
              editor.enclosingScrollView!.bounds.height >= 400 else { throw failure("Expanded AI controls crowded out the document") }
        editing.togglePromptDictation()
        for _ in 0..<50 where editing.dictationPhase != .recording { try await Task.sleep(nanoseconds: 10_000_000) }
        guard editing.dictationPhase == .recording, state.writingPromptDictationActive else {
            throw failure("Prompt composer did not start its isolated microphone capture")
        }
        try await Task.sleep(nanoseconds: 310_000_000)
        editing.togglePromptDictation()
        for _ in 0..<100 where editing.dictationPhase != .idle { try await Task.sleep(nanoseconds: 10_000_000) }
        guard editing.instruction == "Use concise Markdown headings.", !state.writingPromptDictationActive,
              promptCapture.startCount == 1, promptCapture.finishCount == 1 else {
            throw failure("Prompt dictation did not transcribe into the request bar and release capture")
        }
        editing.showingAssistant = false
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard descendants(pane.view).compactMap({ $0 as? WritingPromptTextView }).isEmpty,
              editor.enclosingScrollView!.bounds.height >= 500 else {
            throw failure("Switching off the assistant must return space to the document")
        }
        let draftBeforeNavigation = editing.text
        let picker = WritingModelPickerController(editing: editing, choices: editing.modelChoices, close: {})
        _ = picker.view
        picker.filter("GPT-OSS", group: "openrouter")
        guard picker.visibleChoices.contains(where: { $0.model == "openai/gpt-oss-120b" }),
              editing.text == draftBeforeNavigation, descendants(pane.view).contains(where: { $0 === editor }) else {
            throw failure("Inline model picker lost the document or model search")
        }
        picker.filter("grok", group: "openrouter")
        guard picker.visibleChoices.contains(where: { $0.provider == .xai }) else { throw failure("Search did not cross provider groups") }
        let favorite = "codex|default"
        editing.toggleFavorite(favorite)
        picker.filter("", group: "favorites")
        guard picker.visibleChoices.map(\.id) == [favorite] else { throw failure("Model favorites did not filter") }
        picker.choose(0)
        guard editing.settings.isCodex, editing.text == draftBeforeNavigation else { throw failure("Picker did not select its actual provider") }
        picker.filter("vendor/new-model", group: "openrouter")
        guard picker.visibleChoices.count == 1 else { throw failure("Custom model ID not reachable") }
        picker.choose(0)
        guard editing.settings.model == "vendor/new-model", editing.settings.host.isEmpty else { throw failure("Custom model retained a mismatched host") }
        editing.settings = reasoningSettings
        fixture.makeFirstResponder(editor)
        editor.selectAll(nil)
        editor.insertText("Keep all names intact.\n", replacementRange: editor.selectedRange())
        try await Task.sleep(nanoseconds: 30_000_000)
        guard editing.text == "Keep all names intact.\n", editing.dirty else { throw failure("Native editor did not update the document draft") }
        editor.breakUndoCoalescing()
        guard editor.tryToPerform(Selector(("undo:")), with: nil) else { throw failure("Editor did not handle the native Undo command") }
        try await Task.sleep(nanoseconds: 30_000_000)
        guard editing.text == draftBeforeNavigation else { throw failure("Undo did not restore the previous document: canRedo=\(editor.undoManager?.canRedo == true), native=\(editor.string.count), draft=\(editing.text.count), expected=\(draftBeforeNavigation.count)") }
        guard editor.tryToPerform(Selector(("redo:")), with: nil) else { throw failure("Editor did not handle the native Redo command") }
        try await Task.sleep(nanoseconds: 30_000_000)
        guard editing.text == "Keep all names intact.\n" else { throw failure("Redo lost the edited document") }
        editor.setSelectedRange(NSRange(location: 9, length: 5))
        editing.selection = .dictionary
        editing.text = "# Dictionary\n\n"
        guard editing.addDictionaryEntry(term: "GPT-6 Astra", context: "common AI model"),
              editing.addDictionaryEntry(term: "Conrad", context: "name"),
              editing.dictionaryEntries.map(\.term) == ["Conrad", "GPT-6 Astra"],
              editing.dictionaryEntries.map(\.context) == ["name", "common AI model"] else {
            throw failure("Structured dictionary did not add or alphabetize words with context")
        }
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        let dictionaryFields = descendants(pane.view).compactMap { $0 as? NSTextField }.map(\.stringValue)
        guard dictionaryFields.contains("Conrad"), dictionaryFields.contains("name"),
              dictionaryFields.contains("GPT-6 Astra"), dictionaryFields.contains("common AI model"),
              !descendants(pane.view).contains(where: { $0 === editing.dictionaryDocument.textView }) else {
            throw failure("Dictionary did not show its custom word and context rows")
        }
        let termField = descendants(pane.view).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Conrad" }!
        let dictionaryY = termField.convert(termField.bounds, to: pane.view)
        let topDistance = pane.view.isFlipped ? dictionaryY.minY : pane.view.bounds.height - dictionaryY.maxY
        guard topDistance < 250, termField.isEnabled, termField.isEditable else {
            throw failure("Dictionary header stretched or a saved word is not editable: \(topDistance)")
        }
        state.phase = .recording
        guard editing.enabled else { throw failure("Dictation must not lock local document drafts") }
        state.phase = .idle
        editing.showingDictionaryMarkdown = true
        try await Task.sleep(nanoseconds: 60_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard descendants(pane.view).contains(where: { $0 === editing.dictionaryDocument.textView }),
              editing.dictionaryDocument.textView.string.contains("- Conrad\n  - Category: \"name\"") else {
            throw failure("Dictionary Markdown access did not expose the compatible source file")
        }
        editing.showingDictionaryMarkdown = false
        editing.selection = .instructions
        try await Task.sleep(nanoseconds: 30_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard descendants(pane.view).contains(where: { $0 === editor }), editor.selectedRange() == NSRange(location: 9, length: 5),
              editor.undoManager?.canUndo == true, editing.text == "Keep all names intact.\n" else {
            throw failure("Document switching lost selection, undo history or draft text")
        }
        let find = NSMenuItem()
        find.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        editor.performTextFinderAction(find)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard editor.enclosingScrollView?.isFindBarVisible == true else { throw failure("Find and replace did not open inside the document") }
        find.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editor.performTextFinderAction(find)
        editing.save()
        guard try WritingDocumentFile(directory: directory, kind: .instructions).read() == editing.text, !editing.dirty else { throw failure("Instructions save failed") }
        editing.selection = .dictionary
        editing.text = "# Dictionary\n- S2T\n"
        editing.save()
        let dictionary = editing.text
        editing.selection = .instructions
        state.routerKey = "fixture-key"
        editing.settings.host = ""
        editing.reasoning = "high"
        editing.fast = true
        editing.instruction = "Make this more precise"
        editing.improve()
        try await wait(editing)
        guard editing.suggestion == "Keep every proper name intact.\n", editing.text == "Keep all names intact.\n", await transport.markdownFirst,
              try WritingDocumentFile(directory: directory, kind: .instructions).read() == editing.text else { throw failure("AI must propose a change without saving it") }
        editing.review = .suggestion
        try await Task.sleep(nanoseconds: 100_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard let review = descendants(pane.view).compactMap({ $0 as? NSTextView }).first(where: { $0.isEditable && !$0.isFieldEditor }),
              review.string == editing.suggestion, review.enclosingScrollView!.bounds.height >= 450,
              fixture.sheets.isEmpty else {
            throw failure("AI review must use the full document editor with explicit apply/discard and original comparison")
        }
        guard let versions = descendants(pane.view).compactMap({ $0 as? SettingsChoiceControl }).first(where: { $0.segmentCount == 3 && $0.label(forSegment: 0) == "Changes" }) else {
            throw failure("Missing native original/suggestion switch")
        }
        versions.selectedSegment = 2
        versions.sendAction(versions.action, to: versions.target)
        try await Task.sleep(nanoseconds: 30_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard descendants(pane.view).contains(where: { $0 === editor }), !editor.isEditable,
              editor.string == "Keep all names intact.\n" else { throw failure("Original comparison must preserve the source and remain read only") }
        versions.selectedSegment = 1
        versions.sendAction(versions.action, to: versions.target)
        try await Task.sleep(nanoseconds: 30_000_000)
        fixture.contentView?.layoutSubtreeIfNeeded()
        guard review.isEditable, descendants(pane.view).contains(where: { $0 === review }) else { throw failure("Suggestion did not return to editable review") }
        editing.applySuggestion()
        guard editing.text == "Keep every proper name intact.\n", !editing.dirty else { throw failure("Apply must save the reviewed suggestion") }
        editing.settings.provider = "codex"
        editing.settings.codexModel = "fixture-model"
        editing.selection = .dictionary
        editing.improve()
        try await wait(editing)
        guard editing.suggestion == "# Dictionary\n- S2T\n- Codex\n", editing.text == dictionary,
              await codex.calls == 1, await transport.calls == 1, state.processingModel == originalModel else {
            throw failure("Codex routing or dictation setting isolation failed")
        }
        editing.cancel()
        editing.settings.provider = "openrouter"
        editing.improve()
        editing.text = "Newer manual draft"
        try await Task.sleep(nanoseconds: 100_000_000)
        guard editing.suggestion == nil, !editing.busy, editing.text == "Newer manual draft" else { throw failure("Cancelled AI replaced a newer draft") }
        let external = "# Dictionary\n- Added externally\n"
        try external.write(to: directory.appendingPathComponent("dictionary.md"), atomically: true, encoding: .utf8)
        editing.save()
        guard !editing.error.isEmpty, editing.text == "Newer manual draft",
              try WritingDocumentFile(directory: directory, kind: .dictionary).read() == external else { throw failure("External edits were overwritten") }
        let restored = WritingEditor(state: state, directory: directory)
        guard restored.settings == editing.settings else { throw failure("AI settings did not persist") }
        state.xaiKey = "fixture-xai-key"
        for provider in [ProcessingProvider.xai, .local] {
            editing.settings.provider = provider.rawValue
            editing.settings.localURL = "http://127.0.0.1:1234/v1/chat/completions"
            editing.improve()
            try await wait(editing)
            guard let outgoing = await transport.lastRequest,
                  outgoing.url?.host == (provider == .xai ? "api.x.ai" : "127.0.0.1"),
                  outgoing.value(forHTTPHeaderField: "Authorization") == (provider == .xai ? "Bearer fixture-xai-key" : nil),
                  editing.suggestion != nil else { throw failure("Writing used the wrong provider connection") }
            editing.cancel()
        }
        try await WritingUXProbe.run(state: state)
        try await WritingCreditsProbe.run()
        controller.showModels()
        guard !controller.showingWriting, controller.writingPane.view.isHidden,
              controller.modelsPane.controls["model.prompt.finder"] == nil else { throw failure("Writing did not leave Models cleanly") }
        controller.showWriting()
        controller.sidebar.selectAppearance()
        guard !controller.showingWriting, controller.writingPane.view.isHidden else { throw failure("Return to Appearance failed") }
        guard !fixture.isVisible, !window.isVisible else { throw failure("Writing verification showed a window") }
        print("PASS: Writing workspace, rendered Markdown preview, alphabetized searchable dictionary rows with word/context fields and Markdown access, custom multiline prompt composer with Return submit and Shift-Return newline, isolated in-bar dictation, Markdown source styling and formatting, Markdown-first AI request, expanded/collapsed AI, native editing without an overlapping ruler, undo/redo, find/replace, local prompt/dictionary saves, external edit conflicts, full-size AI review/apply, OpenRouter and Codex routing, cancellation, independent saved model options and hidden layout. Isolated files, preferences and mock providers; no real credentials, fields or screen capture.")
    }
    private static func verifyCancelledPermission() async throws {
        let microphone = Microphone(simulatedAudio: Array(repeating: 0.1, count: 4096), startDelay: 0)
        var permission: CheckedContinuation<Bool, Never>?
        let capture = LiveWritingPromptCapture(microphone: microphone, requestAccess: {
            await withCheckedContinuation { permission = $0 }
        })
        let attempt = Task { try await capture.start(deviceUID: "") }
        while permission == nil { await Task.yield() }
        attempt.cancel(); capture.cancel()
        permission?.resume(returning: true)
        do { try await attempt.value; throw failure("Cancelled microphone permission started capture") }
        catch is CancellationError { }
        await microphone.waitUntilStopped()
        guard await capture.finish().count == 44, microphone.capturedFrameCount == 0 else {
            throw failure("Granting permission after Stop started the microphone")
        }
        let active = LiveWritingPromptCapture(microphone: microphone, requestAccess: { true })
        try await active.start(deviceUID: "")
        guard await active.finish().count == 44 + 4096 * 2 else { throw failure("The next microphone attempt failed after cancellation") }
    }

    private static func wait(_ editor: WritingEditor) async throws {
        for _ in 0..<100 {
            if !editor.busy { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw failure("AI fixture did not complete")
    }
    private static func failure(_ message: String) -> NSError { NSError(domain: "WritingPaneProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@MainActor private final class WritingPromptCaptureProbe: WritingPromptCapturing {
    private(set) var startCount = 0
    private(set) var finishCount = 0
    func start(deviceUID: String) async throws { startCount += 1 }
    func finish() async -> Data {
        finishCount += 1
        return Data(repeating: 1, count: 128)
    }
    func cancel() { }
}

private actor WritingProbeTransport: HTTPTransport {
    var calls = 0
    private(set) var lastRequest: URLRequest?
    private(set) var markdownFirst = false
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        lastRequest = request
        if let body = request.httpBody,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let messages = object["messages"] as? [[String: String]],
           let instructions = messages.first?["content"] {
            markdownFirst = instructions.contains("Markdown by default") && instructions.contains("without a surrounding code fence")
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let body = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Keep every proper name intact.\n"}}]}"#.utf8)
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
private actor WritingProbeCodex: CodexServing {
    var calls = 0
    func complete(instructions: String, prompt: String, model: String, executable: String, options: CodexOptions) async throws -> String {
        calls += 1
        return "# Dictionary\n- S2T\n- Codex\n"
    }
}
