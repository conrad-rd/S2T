import AppKit
import S2TCore

@MainActor enum PromptModeProbe {
    static func run() async throws {
        if CommandLine.arguments.contains("--benchmark") { try await PromptPerformanceProbe.run(); return }
        try await verifyShortcuts()
        try await BrowserInsertionProbe.run()
        try await verifyModelEditor()
        try Microphone.verifyPromptAudio()
        try await verifyTimeline()
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let board = NSPasteboard(name: .init("com.s2t.prompt.fixture." + UUID().uuidString))
        let state = AppState(preview: true, outputPasteboard: board)
        guard !state.promptModeEnabled, state.promptVisionModel == "google/gemini-2.5-flash" else { throw failure("Prompt mode defaults") }
        guard state.promptShortcutKey == .rightCommand, state.shortcutKey == .function else { throw failure("Separate default shortcuts") }
        state.saveShortcut(.function, prompt: true)
        guard state.promptShortcutKey == .rightCommand else { throw failure("Duplicate shortcut accepted") }
        let custom = ShortcutKey(keyCode: 97, modifiers: 0, name: "F6")
        state.saveShortcut(custom, prompt: true)
        state.promptTapEnabled = false
        let restored = AppState(preview: true)
        guard restored.promptShortcutKey == custom, !restored.promptTapEnabled, restored.shortcutKey == .function else { throw failure("Independent prompt shortcut persistence") }
        state.saveShortcut(.rightCommand, prompt: true)
        state.promptTapEnabled = true
        state.phase = .recording
        state.rawTranscript = "Preserve this dictation"
        state.handleActivation(.cancel, prompt: true)
        guard state.phase == .recording, state.rawTranscript == "Preserve this dictation" else { throw failure("Prompt shortcut cancelled normal dictation") }
        state.cancel()
        let controller = MenuBarController(state: state)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.menuNeedsUpdate(controller.menu)
        guard let root = controller.menu.items.first(where: { $0.identifier?.rawValue == "prompt" }),
              root.title.contains("Experimental beta"), let menu = root.submenu else { throw failure("Experimental beta menu") }
        controller.menuNeedsUpdate(menu)
        guard let toggle = menu.items.first(where: { $0.identifier?.rawValue == "prompt.enabled" }) as? ActionMenuItem else { throw failure("Toggle missing") }
        guard let activation = menu.items.first(where: { $0.identifier?.rawValue == "prompt.activation" })?.submenu else { throw failure("Prompt activation submenu") }
        controller.menuNeedsUpdate(activation)
        guard activation.items.contains(where: { $0.identifier?.rawValue == "prompt.shortcut.record" }),
              let reset = activation.items.first(where: { $0.identifier?.rawValue == "prompt.shortcut.default" }) as? ActionMenuItem,
              reset.state == .on else { throw failure("Prompt shortcut controls and default checkmark") }
        state.saveShortcut(custom, prompt: true)
        reset.invoke()
        guard state.promptShortcutKey == .rightCommand, state.shortcutKey == .function else { throw failure("Prompt default reset changed normal shortcut") }
        toggle.invoke()
        controller.refreshStatus()
        guard state.promptModeEnabled, toggle.state == .on, AppState(preview: true).promptModeEnabled else { throw failure("Toggle persistence") }
        guard !menu.items.contains(where: { $0.identifier?.rawValue == "prompt.capture" }) else { throw failure("Window capture is still offered") }
        state.phase = .recording
        controller.refreshStatus()
        guard !toggle.isEnabled else { throw failure("Mode changed mid-recording") }
        state.phase = .idle
        let model = state.processingModel, host = state.routerEndpoint
        state.promptVisionModel = "fixture/vision"
        guard state.processingModel == model, state.routerEndpoint == host else { throw failure("Vision changed cleanup settings") }

        guard let visionMenu = menu.items.first(where: { $0.identifier?.rawValue == "prompt.model" })?.submenu else { throw failure("Missing image provider menu") }
        for provider in [VisionProvider.local, .codex] {
            controller.menuNeedsUpdate(visionMenu)
            guard let select = visionMenu.items.first(where: { $0.identifier?.rawValue == "visionProvider." + provider.rawValue }) as? ActionMenuItem else { throw failure("Missing image provider choice") }
            select.invoke()
            controller.menuNeedsUpdate(visionMenu)
            guard state.promptVisionProvider == provider,
                  visionMenu.items.contains(where: { $0.identifier?.rawValue == "visionProvider." + provider.rawValue && $0.state == .on }),
                  visionMenu.items.contains(where: { $0.view?.identifier?.rawValue == (provider == .local ? "local.vision.url" : "codex.executable") }) else { throw failure("Image provider settings did not follow selection") }
            state.promptVisionModel = provider == .local ? "fixture-vision:local" : "fixture-codex"
            state.localVisionURL = "http://localhost:1234/fixture-vision"
            let restored = AppState(preview: true)
            guard restored.promptVisionProvider == provider, restored.promptVisionModel == state.promptVisionModel,
                  restored.localVisionURL == state.localVisionURL, state.processingModel == model, state.routerEndpoint == host else { throw failure("Image provider settings are not independent or persistent") }
        }
        state.promptVisionProvider = .local
        guard state.promptVisionModel == "fixture-vision:local" else { throw failure("Codex replaced the local image model") }
        state.promptVisionProvider = .openRouter
        guard state.promptVisionModel == "fixture/vision" else { throw failure("Image provider switch replaced OpenRouter model") }
        print("Vision providers: local/Codex menu actions, checkmarks, settings, persistence and cleanup isolation: PASS")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 180, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let sourcePNG = bitmap.representation(using: .png, properties: [:])!
        let frame = PromptScreenRecorder.Frame(time: 101.2, pointer: CGPoint(x: 5, y: 6), region: CGRect(x: 0, y: 0, width: 32, height: 24), image: sourcePNG)
        let png = try frame.screenshot().png
        func fixture() -> PromptModeSession {
            PromptModeSession(frames: [frame], words: [.init(text: "look", start: 1, end: 1.1), .init(text: "here", start: 1.2, end: 1.4)], audioOrigin: 100)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-prompt-fixture-" + UUID().uuidString)
        let session = fixture()
        session.stopListening()
        let result = try await session.describe(transcript: "Match this layout. Look here.", api: DictationAPI(transport: PromptProbeTransport(needsImage: true)), key: "fixture", model: "fixture/vision", directory: directory)
        guard result.images.count == 1, result.references.count == 1,
              try Data(contentsOf: result.images[0]) == png, result.images[0].lastPathComponent.hasPrefix(session.id) else { throw failure("Timestamp frame selection and named image association") }
        let rendered = PromptReferenceText.append(to: "Match this layout.", session: session.id, references: result.references)
        guard rendered.contains(result.images[0].lastPathComponent), rendered.contains("1.2s") else { throw failure("Prompt image reference") }
        state.promptImages = result.images
        state.copyPromptImage(result.images[0])
        guard board.data(forType: .png) == png, board.data(forType: ClipboardMonitor.outputType) != nil else { throw failure("Isolated image clipboard") }

        let sufficient = fixture()
        let allImagesDirectory = directory.appendingPathComponent("all-references")
        let described = try await sufficient.describe(transcript: "Rename this button. Look here.", api: DictationAPI(transport: PromptProbeTransport(needsImage: false)), key: "fixture", model: "fixture/vision", directory: allImagesDirectory)
        guard described.images.count == 1, described.references.count == 1,
              try Data(contentsOf: described.images[0]) == png,
              described.references[0].imageName == described.images[0].lastPathComponent else { throw failure("A successful description must still preserve its screenshot") }
        try await verifyImagePasting(images: result.images + described.images, png: png)

        let broken = fixture()
        var accountFailure = false
        let fallback = try await broken.describe(transcript: "Fix this. Look here.", api: DictationAPI(transport: PromptProbeTransport(needsImage: false, status: 401)), key: "fixture", model: "fixture/vision", directory: directory, onVisionError: { error in
            if case .account(.openRouter, _) = error as? ServiceError { accountFailure = true; return true }
            return false
        })
        guard accountFailure, fallback.images.count == 1, fallback.warnings.isEmpty,
              fallback.references[0].description == "See screenshot for 'look here'." else { throw failure("Vision failure lost the image or account routing") }

        let cancelled = fixture()
        let cancelledDirectory = directory.appendingPathComponent("cancelled")
        let pending = Task { try await cancelled.describe(transcript: "Look here", api: DictationAPI(transport: PromptProbeTransport(needsImage: true, delay: 200_000_000)), key: "fixture", model: "fixture/vision", directory: cancelledDirectory) }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelled.cancel()
        pending.cancel()
        do { _ = try await pending.value; throw failure("Cancelled processing completed") }
        catch is CancellationError { }
        guard !FileManager.default.fileExists(atPath: cancelledDirectory.path) else { throw failure("Cancellation saved an image") }
        for (provider, cleanupFails, deliveryOutcome) in [(ProcessingProvider.openRouter, false, TextInsertion.Outcome.textSent), (.openRouter, true, .textSent), (.openRouter, false, .noTarget), (.local, false, .textSent), (.local, true, .textSent), (.codex, false, .textSent), (.codex, true, .textSent)] {
            let pipelineSession = fixture()
            pipelineSession.stopListening()
            var delivered = ""
            var attachmentCalls = 0
            let pipelineBoard = NSPasteboard(name: .init("com.s2t.prompt.pipeline." + UUID().uuidString))
            let pipeline = AppState(preview: true, api: DictationAPI(transport: PromptProbeTransport(needsImage: false, cleanupFails: cleanupFails), codex: ProviderProbeCodex(fails: cleanupFails)), outputPasteboard: pipelineBoard, promptSession: pipelineSession, insertPromptImages: { images, _, board in
                guard delivered.contains("reference-1.png"), images.count == 1,
                      board.string(forType: .string) == nil else { throw failure("Images pasted before text delivery or clipboard finalized too soon") }
                attachmentCalls += 1
                return .init(sentCount: images.count, issue: nil, clipboardChange: board.changeCount)
            }, insertText: { text, _ in
                delivered = text
                return deliveryOutcome
            })
            pipeline.processingProvider = provider
            pipeline.promptVisionProvider = provider == .codex ? .codex : provider == .local ? .local : .openRouter
            pipeline.promptVisionModel = pipeline.promptVisionProvider.defaultModel
            pipeline.assemblyKey = "fixture"
            pipeline.routerKey = provider == .openRouter ? "fixture" : ""
            pipeline.mode = .clean
            pipeline.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24000), sampleRate: 48000))
            for _ in 0..<200 {
                if pipeline.phase == .complete || pipeline.phase == .failed { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard pipeline.phase == .complete, delivered.contains("Prompt set " + pipelineSession.id),
                  delivered.contains("reference-1.png"), pipeline.promptImages.count == 1,
                  attachmentCalls == (deliveryOutcome == .textSent ? 1 : 0),
                  pipelineBoard.string(forType: .string) == (deliveryOutcome == .textSent ? delivered : nil),
                  (pipeline.processingFailureModel != nil) == cleanupFails else { throw failure("End-to-end prompt delivery or cleanup fallback") }
            guard pipeline.promptImages[0].path.hasPrefix(FileManager.default.temporaryDirectory.path) else { throw failure("Preview wrote real prompt storage") }
            pipeline.cancel()
        }
        print("Prompt mode: beta menu, persistence, model isolation, generated frames, timestamp selection, stop/cancel, every reference saved, account fallback, named references, isolated image copy and complete delivery with cleanup success/failure PASS.")
        print("No screen capture, microphone, Speech recognition, real clipboard, Keychain, provider requests, or visible menus used. Live screen recording, provider latency and browser attachment acceptance are unverified.")
    }

    private static func verifyTimeline() async throws {
        var frames: [PromptScreenRecorder.Frame] = []
        var words: [TimedWord] = []
        for index in 0..<12 {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
            memset(bitmap.bitmapData!, Int32(40 + index * 10), bitmap.bytesPerRow * bitmap.pixelsHigh)
            let time = 0.25 * Double(index)
            frames.append(.init(time: 500 + time, pointer: CGPoint(x: index, y: 6), region: CGRect(x: -32, y: 0, width: 32, height: 24), image: bitmap.representation(using: .png, properties: [:])!))
            words.append(.init(text: "here", start: time, end: time + 0.15))
        }
        var history = PromptFrameHistory(maximumFrames: 2, maximumBytes: frames[0].image.count * 3)
        guard history.append(frames[0]), history.append(frames[0]), !history.append(frames[0]), history.take().count == 2,
              history.append(frames[0]) else { throw failure("Frame count bound or take/reset") }
        history.clear()
        guard history.take().isEmpty else { throw failure("Cancelled history retained images") }
        var limited = PromptFrameHistory(maximumFrames: 10, maximumBytes: frames[0].image.count)
        guard limited.append(frames[0]), !limited.append(frames[0]), limited.take().count == 1 else { throw failure("Frame memory limit") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-timeline-" + UUID().uuidString)
        let transcript = Array(repeating: "here", count: 12).joined(separator: ", ")
        let session = PromptModeSession(frames: frames, words: words, audioOrigin: 500)
        session.stopListening()
        let result = try await session.describe(transcript: transcript, api: DictationAPI(transport: PromptProbeTransport(needsImage: true)), key: "fixture", model: "fixture/vision", directory: directory)
        guard result.references.count == 12, result.images.count == 12, result.warnings.isEmpty,
              result.references.map(\.seconds) == words.map(\.start),
              Set(try result.images.map { try Data(contentsOf: $0) }).count == 12 else { throw failure("Rapid references lost frames or used the wrong audio origin") }
        for index in frames.indices {
            guard try Data(contentsOf: result.images[index]) == frames[index].screenshot().png else { throw failure("References swapped recorded frames") }
        }
        let wholeDisplayFrames = try PromptScreenRecorder.verifyWholeDisplay()
        let wholeDisplay = PromptModeSession(frames: wholeDisplayFrames,
            words: [.init(text: "here", start: 0, end: 0.1), .init(text: "here", start: 1, end: 1.1)], audioOrigin: 600)
        let wholeDisplayResult = try await wholeDisplay.describe(transcript: "here here", api: DictationAPI(transport: PromptProbeTransport(needsImage: true)),
            key: "fixture", model: "fixture/vision", directory: directory)
        guard wholeDisplayResult.images.count == 2 else { throw failure("Full-display references were lost") }
        for index in wholeDisplayFrames.indices {
            guard try Data(contentsOf: wholeDisplayResult.images[index]) == wholeDisplayFrames[index].screenshot().png else {
                throw failure("Saved references did not preserve both windows and the complete desktop at each timestamp")
            }
        }
        print("Full display: generated desktop edges and two changing windows survive recording, timestamp selection and saved PNG extraction PASS.")
        let capturedFrames = try PromptScreenRecorder.verifyFrameFreezing()
        let switched = PromptModeSession(frames: capturedFrames,
            words: [.init(text: "here", start: 0, end: 0.15)], audioOrigin: 500)
        switched.stopListening()
        let original = try await switched.describe(transcript: "here", api: DictationAPI(transport: PromptProbeTransport(needsImage: true)),
            key: "fixture", model: "fixture/vision", directory: directory)
        guard original.images.count == 1,
              try Data(contentsOf: original.images[0]) == capturedFrames[0].screenshot().png,
              try Data(contentsOf: original.images[0]) != capturedFrames[1].screenshot().png else {
            throw failure("Finishing in another window replaced the referenced screen frame")
        }
        guard !switched.retainsTemporaryRecording else { throw failure("Extracted recording was retained") }
        let cancelled = PromptModeSession(frames: capturedFrames)
        cancelled.cancel()
        guard !cancelled.retainsTemporaryRecording else { throw failure("Cancelled recording was retained") }
        print("Temporary full-screen recording released after extraction and cancellation; no recording file is created.")
        print("Recorder: reused synthetic pixel buffer, original capture times, app-to-browser switch, idle, stop and saved reference bytes PASS.")
        let missing = PromptModeSession(frames: frames, words: [.init(text: "here", start: 20, end: 20.1)], audioOrigin: 500)
        let absent = try await missing.describe(transcript: "here", api: DictationAPI(transport: PromptProbeTransport(needsImage: true)), key: "fixture", model: "fixture/vision", directory: directory)
        guard absent.images.isEmpty, absent.warnings.contains(where: { $0.contains("1 visual references") }) else { throw failure("Missing recording silently reused a stale frame") }
        print("Timeline: twelve references 250 ms apart retain all twelve distinct generated frames, including the final cue; audio offset, ordering and missing-frame warnings PASS.")
    }

    private static func verifyImagePasting(images: [URL], png: Data) async throws {
        let board = NSPasteboard(name: .init("com.s2t.prompt.attachments." + UUID().uuidString))
        let recipient: pid_t = 123456
        var pasted: [String] = []
        var pasteCalls = 0
        let paste: (pid_t) -> Bool = { pid in
            guard pid == recipient, let items = board.pasteboardItems,
                  items.allSatisfy({ $0.data(forType: ClipboardMonitor.outputType) != nil && $0.data(forType: .png) == png }) else { return false }
            pasted += items.compactMap { $0.string(forType: .fileURL) }
            pasteCalls += 1
            return true
        }
        let complete = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
            currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard complete.sentCount == 2, complete.issue == nil, pasteCalls == 1, pasted == images.map(\.absoluteString),
              complete.clipboardChange == board.changeCount else { throw failure("Ordered automatic image paste with exact files") }

        pasted = []
        let focused: pid_t = 654321
        let interrupted = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
            currentRecipient: { focused }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard interrupted.sentCount == 0, interrupted.issue != nil, pasted.isEmpty else { throw failure("Image paste crossed a focus change") }

        pasted = []
        let changedClipboard = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
            currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {
                board.clearContents(); board.setString("new user copy", forType: .string)
            })
        guard changedClipboard.sentCount == 2,
              board.string(forType: .string) == "new user copy",
              changedClipboard.clipboardChange != board.changeCount else { throw failure("Image paste overwrote a new clipboard copy") }

        let single = try await PromptImageInsertion.insert([images[0]], recipient: recipient, board: board,
            currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard single.sentCount == 1, board.data(forType: .png) == png else { throw failure("Single-image PNG fallback") }
        let unchanged = board.changeCount
        let missing = try await PromptImageInsertion.insert(images + [images[0].appendingPathExtension("missing")], recipient: recipient, board: board,
            currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard missing.sentCount == 0, missing.issue != nil, board.changeCount == unchanged else { throw failure("Unreadable batch partially changed clipboard") }
        let before = board.changeCount
        pasted = []
        for hasPermission in [false, true] {
            TextInsertion.menuIsOpen = hasPermission
            defer { TextInsertion.menuIsOpen = false }
            let blocked = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
                currentRecipient: { recipient }, canPost: { hasPermission }, postPaste: paste, waitForPaste: {})
            guard blocked.sentCount == 0, blocked.issue != nil, board.changeCount == before else { throw failure("Blocked attachment modified clipboard") }
        }
        var pending: Task<PromptImageInsertion.Result, Error>!
        pending = Task { @MainActor in
            try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
                currentRecipient: { recipient }, canPost: { true }, postPaste: paste,
                waitForPaste: { pending.cancel(); try Task.checkCancellation() })
        }
        do { _ = try await pending.value; throw failure("Cancelled image paste completed") }
        catch is CancellationError { }
        guard pasted.count == 2 else { throw failure("Cancellation repeated a batch paste") }
        print("Automatic image paste: single batch with PNG bytes for every image and ordered file references, output markers, focus changes, clipboard changes, menu/permission guards and cancellation PASS using an isolated clipboard and injected events.")
    }

    private static func verifyModelEditor() async throws {
        var saved = "vendor/vision"
        let editor = MenuValueEditor(title: "Image model", value: "openai/gpt-oss-120b", secure: false, onPaste: { _ in }) { value in
            saved = value
            return nil
        }
        editor.validateValue = { value in
            try? await Task.sleep(nanoseconds: 10_000_000)
            return value == "openai/gpt-oss-120b" ? "This model cannot describe screenshots." : nil
        }
        editor.saveValue(nil)
        guard editor.saveButton.title == "Checking…", !editor.saveButton.isEnabled else { throw failure("Model save did not await image validation") }
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == "vendor/vision", editor.feedback.stringValue.contains("cannot describe"), editor.saveButton.title == "Save" else { throw failure("Text-only model was saved") }
        editor.field.stringValue = "vendor/other-vision"
        editor.saveValue(nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == "vendor/other-vision", editor.saveButton.title == "✓ Saved" else { throw failure("Valid image model was not saved") }
        editor.saveButton.isEnabled = true
        editor.field.stringValue = "vendor/stale"
        editor.saveValue(nil)
        editor.field.stringValue = "vendor/new-edit"
        try await Task.sleep(nanoseconds: 30_000_000)
        guard saved == "vendor/other-vision" else { throw failure("Stale image validation saved an edited value") }
        print("Image model editor: asynchronous validation, text-only rejection, valid save and stale-edit protection PASS without a real provider or clipboard.")
    }
    private static func verifyShortcuts() async throws {
        let shortcut = ActivationShortcut(verification: true)
        defer { shortcut.stop() }
        shortcut.configure(key: .function, hold: true, tap: false)
        shortcut.configurePrompt(key: .rightCommand, hold: true, tap: false)
        shortcut.refresh()
        var normal: [ActivationAction] = []
        var prompt: [ActivationAction] = []
        var listening = false
        shortcut.onAction = { normal.append($0) }
        shortcut.onPromptAction = { prompt.append($0); listening = $0 == .start }
        shortcut.isListening = { listening }
        func event(_ code: Int64, _ flags: CGEventFlags = [], type: CGEventType = .flagsChanged) -> CGEvent {
            let event = CGEvent(source: nil)!
            event.type = type
            event.flags = flags
            event.setIntegerValueField(.keyboardEventKeycode, value: code)
            return event
        }
        func settle() async throws { try await Task.sleep(nanoseconds: 10_000_000) }
        let right = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
        let left = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8)
        _ = shortcut.receive(type: .flagsChanged, event: event(55, left))
        _ = shortcut.receive(type: .flagsChanged, event: event(55))
        try await settle()
        guard normal.isEmpty, prompt.isEmpty else { throw failure("Left Command triggered Prompt mode") }
        guard !shortcut.receive(type: .flagsChanged, event: event(54, right)) else { throw failure("Right Command modifier was swallowed") }
        try await settle()
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt == [.start, .stop], normal.isEmpty else { throw failure("Right Command did not exclusively start and stop Prompt mode") }
        _ = shortcut.receive(type: .flagsChanged, event: event(63, .maskSecondaryFn))
        _ = shortcut.receive(type: .flagsChanged, event: event(63))
        try await settle()
        guard normal == [.start, .stop], prompt == [.start, .stop] else { throw failure("Fn lost normal dictation") }
        prompt = []
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right))
        try await settle()
        guard !shortcut.receive(type: .keyDown, event: event(8, right, type: .keyDown)) else { throw failure("Command-C was swallowed") }
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt == [.start, .cancel] else { throw failure("Command combination did not cancel the held prompt") }
        prompt = []
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right.union(left)))
        _ = shortcut.receive(type: .flagsChanged, event: event(54, left))
        try await settle()
        guard prompt.isEmpty else { throw failure("Both Command keys started a prompt") }
        shortcut.configurePrompt(key: .rightCommand, hold: true, tap: true)
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right))
        try await settle()
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt == [.start] else { throw failure("Prompt tap did not latch") }
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right))
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt == [.start, .stop] else { throw failure("Second prompt tap did not stop") }
        prompt = []
        shortcut.configurePrompt(key: nil)
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right))
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt.isEmpty else { throw failure("Disabled Prompt mode intercepted its key") }
        var captured: ShortcutKey?
        shortcut.onPromptCapture = { captured = $0 }
        shortcut.onCapture = { _ in preconditionFailure("Prompt capture changed the normal binding") }
        shortcut.beginCapture(prompt: true)
        _ = shortcut.receive(type: .keyDown, event: event(97, [], type: .keyDown))
        _ = shortcut.receive(type: .keyUp, event: event(97, [], type: .keyUp))
        guard captured?.keyCode == 97, !shortcut.isCapturing else { throw failure("Custom prompt key capture") }
        shortcut.configurePrompt(key: captured, hold: true, tap: false)
        _ = shortcut.receive(type: .keyDown, event: event(97, [], type: .keyDown))
        _ = shortcut.receive(type: .keyUp, event: event(97, [], type: .keyUp))
        try await settle()
        guard prompt == [.start, .stop] else { throw failure("Custom prompt binding did not activate") }
        print("Prompt shortcuts: Right/Left Command, Fn separation, hold/tap, combination passthrough, disabled mode and custom key capture PASS using unposted synthetic events.")
    }

    private static func failure(_ message: String) -> Error { ServiceError.message(message) }
}

private struct PromptProbeTransport: HTTPTransport {
    var needsImage: Bool
    var status = 200
    var cleanupFails = false
    var delay: UInt64 = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.hasSuffix("/endpoints") == true {
            return (Data(#"{"data":{"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        if request.url?.path == "/transcribe" {
            return (Data(#"{"text":"Please fix this button, look here."}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as? [[String: Any]] ?? []
        if messages.last?["content"] is String {
            return (Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Please fix this button."}}]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: cleanupFails ? 500 : 200, httpVersion: nil, headerFields: nil)!)
        }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let parts = messages.last?["content"] as? [[String: Any]] ?? []
        let count = parts.filter { $0["type"] as? String == "image_url" }.count
        let content = try JSONSerialization.data(withJSONObject: ["descriptions": Array(repeating: "A blue Save button beside a gray Cancel button.", count: count)])
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": String(data: content, encoding: .utf8)!]]]])
        return (response, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
