import AppKit
import S2TCore

@MainActor enum PromptModeProbe {
    static func run() async throws {
        if CommandLine.arguments.contains("--benchmark-delivery") { try await PromptCompletionProbe.run(); return }
        if CommandLine.arguments.contains("--benchmark-pipeline") { try await PromptPipelineBenchmark.run(); return }
        if CommandLine.arguments.contains("--benchmark") { try await PromptPerformanceProbe.run(); return }
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        try await PromptDestinationProbe.run()
        try await verifyShortcuts()
        try await ShortcutEventTapProbe.run()
        try await verifyManualCaptures()
        try await PromptDeliveryProbe.run()
        try await PromptCaptureFeedback.verify()
        try PromptCaptureRenderingProbe.run()
        try WithinInputExpansionProbe.verify()
        try PromptRegionCapture.verify()
        try await BrowserInsertionProbe.run()
        try Microphone.verifyPromptAudio()
        try await verifyTimeline()
        try await PromptScreenRecorder.verifyNonblockingStop()
        let board = NSPasteboard(name: .init("com.s2t.prompt.fixture." + UUID().uuidString))
        let state = AppState(preview: true, outputPasteboard: board)
        guard !state.promptModeEnabled else { throw failure("Prompt mode defaults") }
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
        let controller = MenuBarController(state: state, presentsAppearanceWindow: false)
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem); controller.appearanceWindow.window?.close() }
        controller.menuNeedsUpdate(controller.menu)
        controller.appearanceWindow.showDictation()
        guard controller.appearanceWindow.showingDictation,
              !controller.menu.items.contains(where: { $0.identifier?.rawValue == "prompt" }) else {
            throw failure("Prompt mode must be in hidden Dictation settings")
        }
        state.saveShortcut(custom, prompt: true)
        state.saveShortcut(.rightCommand, prompt: true)
        guard state.promptShortcutKey == .rightCommand, state.shortcutKey == .function else { throw failure("Prompt default reset changed normal shortcut") }
        state.promptModeEnabled = true
        guard AppState(preview: true).promptModeEnabled else { throw failure("Prompt toggle was not retained") }
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
        let result = try await session.saveReferences(transcript: "Match this layout. Look here.", directory: directory)
        guard result.images.count == 1, result.references.count == 1,
              try Data(contentsOf: result.images[0]) == png, result.images[0].lastPathComponent.hasPrefix(session.id) else { throw failure("Timestamp frame selection and named image association") }
        let source = PromptReferenceText(transcript: "Match this layout. Look here. Keep the footer.", session: session.id)
        let rendered = source.resolve(source.text, references: result.references)
        guard rendered == "Match this layout. Look here [attached screenshot: [1]]. Keep the footer." else { throw failure("Prompt image reference") }
        state.promptImages = result.images
        state.copyPromptImage(result.images[0])
        guard board.data(forType: .png) == png, board.data(forType: ClipboardMonitor.outputType) != nil else { throw failure("Isolated image clipboard") }

        let sufficient = fixture()
        let allImagesDirectory = directory.appendingPathComponent("all-references")
        let described = try await sufficient.saveReferences(transcript: "Rename this button. Look here.", directory: allImagesDirectory)
        guard described.images.count == 1, described.references.count == 1,
              try Data(contentsOf: described.images[0]) == png,
              described.references[0].imageName == described.images[0].lastPathComponent else { throw failure("Saving references must preserve each screenshot") }
        try await verifyImagePasting(images: result.images + described.images, png: png)

        let cancelled = fixture()
        let cancelledDirectory = directory.appendingPathComponent("cancelled")
        let pending = Task { try await cancelled.saveReferences(transcript: "Look here", directory: cancelledDirectory) }
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
            let pipeline = AppState(preview: true, api: DictationAPI(transport: PromptProbeTransport(cleanupFails: cleanupFails), codex: PromptProbeCodex(fails: cleanupFails)), outputPasteboard: pipelineBoard, promptSession: pipelineSession, insertPromptImages: { images, _, board, beforeText in
                guard !beforeText, !delivered.isEmpty, images.count == 1 else { throw failure("Screenshots were not attached after the complete prompt text") }
                attachmentCalls += 1
                return .init(sentCount: images.count, issue: nil, clipboardChange: board.changeCount, confirmation: .confirmed)
            }, insertText: { text, _ in
                delivered = text
                return deliveryOutcome
            })
            pipeline.processingProvider = provider
            pipeline.assemblyKey = "fixture"
            pipeline.routerKey = provider == .openRouter ? "fixture" : ""
            pipeline.mode = .clean
            pipeline.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24000), sampleRate: 48000))
            for _ in 0..<200 {
                if pipeline.phase == .complete || pipeline.phase == .failed { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard pipeline.phase == .complete, delivered == "Please fix this button, look here [attached screenshot: [1]]. Keep the footer.",
                  pipeline.promptImages.count == 1,
                  pipeline.promptImages.first?.lastPathComponent == pipelineSession.id + "-reference-1.png",
                  attachmentCalls == (deliveryOutcome == .textSent ? 1 : 0),
                  pipelineBoard.string(forType: .string) == (deliveryOutcome == .textSent ? delivered : nil),
                  (pipeline.processingFailureModel != nil) == cleanupFails else {
                throw failure("End-to-end prompt delivery: provider=\(provider), expectedFailure=\(cleanupFails), outcome=\(deliveryOutcome), phase=\(pipeline.phase), images=\(pipeline.promptImages.count), attempts=\(attachmentCalls), text=\(delivered.count), clipboard=\(pipelineBoard.string(forType: .string)?.count ?? -1), cleanupFailure=\(pipeline.processingFailureModel ?? "none"), error=\(pipeline.errorMessage ?? "none")")
            }
            guard pipeline.promptImages[0].path.hasPrefix(FileManager.default.temporaryDirectory.path) else { throw failure("Preview wrote real prompt storage") }
            pipeline.cancel()
        }
        print("Prompt mode: Settings navigation, persistence, model isolation, generated frames, timestamp selection, stop/cancel, saved references, account fallback, isolated image copy and delivery with cleanup success/failure PASS.")
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
        guard limited.append(frames[0]), limited.append(frames[0]), !limited.append(frames[1]),
              limited.take().count == 2 else { throw failure("Idle image reuse must not spend the frame-memory budget twice") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-timeline-" + UUID().uuidString)
        let transcript = Array(repeating: "here", count: 12).joined(separator: ", ")
        let session = PromptModeSession(frames: frames, words: words, audioOrigin: 500)
        session.stopListening()
        let result = try await session.saveReferences(transcript: transcript, directory: directory)
        guard result.references.count == 12, result.images.count == 12, result.warnings.isEmpty,
              result.references.map(\.seconds) == words.map(\.start),
              Set(try result.images.map { try Data(contentsOf: $0) }).count == 12 else { throw failure("Rapid references lost frames or used the wrong audio origin") }
        for index in frames.indices {
            guard try Data(contentsOf: result.images[index]) == frames[index].screenshot().png else { throw failure("References swapped recorded frames") }
        }
        let wholeDisplayFrames = try PromptScreenRecorder.verifyWholeDisplay()
        let wholeDisplay = PromptModeSession(frames: wholeDisplayFrames,
            words: [.init(text: "here", start: 0, end: 0.1), .init(text: "here", start: 1, end: 1.1)], audioOrigin: 600)
        let wholeDisplayResult = try await wholeDisplay.saveReferences(transcript: "here here", directory: directory)
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
        let original = try await switched.saveReferences(transcript: "here", directory: directory)
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
        let absent = try await missing.saveReferences(transcript: "here", directory: directory)
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
            observe: { _, _ in nil }, currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard complete.sentCount == 2, complete.issue == nil, pasteCalls == 1, pasted == images.map(\.absoluteString),
              complete.clipboardChange == board.changeCount else { throw failure("Ordered automatic image paste with exact files") }

        pasted = []
        let focused: pid_t = 654321
        let interrupted = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
            observe: { _, _ in nil }, currentRecipient: { focused }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard interrupted.sentCount == 0, interrupted.issue != nil, pasted.isEmpty else { throw failure("Image paste crossed a focus change") }

        pasted = []
        let changedClipboard = try await PromptImageInsertion.insert(images, recipient: recipient, board: board,
            observe: { _, _ in nil }, currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {
                board.clearContents(); board.setString("new user copy", forType: .string)
            })
        guard changedClipboard.sentCount == 2,
              board.string(forType: .string) == "new user copy",
              changedClipboard.clipboardChange != board.changeCount else { throw failure("Image paste overwrote a new clipboard copy") }

        let single = try await PromptImageInsertion.insert([images[0]], recipient: recipient, board: board,
            observe: { _, _ in nil }, currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
        guard single.sentCount == 1, board.data(forType: .png) == png else { throw failure("Single-image PNG fallback") }
        let unchanged = board.changeCount
        let missing = try await PromptImageInsertion.insert(images + [images[0].appendingPathExtension("missing")], recipient: recipient, board: board,
            observe: { _, _ in nil }, currentRecipient: { recipient }, canPost: { true }, postPaste: paste, waitForPaste: {})
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
                observe: { _, _ in nil }, currentRecipient: { recipient }, canPost: { true }, postPaste: paste,
                waitForPaste: { pending.cancel(); try Task.checkCancellation() })
        }
        do { _ = try await pending.value; throw failure("Cancelled image paste completed") }
        catch is CancellationError { }
        guard pasted.count == 2 else { throw failure("Cancellation repeated a batch paste") }
        print("Automatic image paste: single batch with PNG bytes for every image and ordered file references, output markers, focus changes, clipboard changes, menu/permission guards and cancellation PASS using an isolated clipboard and injected events.")
    }

    private static func verifyManualCaptures() async throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 200, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let sourcePNG = bitmap.representation(using: .png, properties: [:])!
        let frame = PromptScreenRecorder.Frame(time: 101.2, pointer: CGPoint(x: 5, y: 6), region: CGRect(x: 0, y: 0, width: 32, height: 24), image: sourcePNG)
        let session = PromptModeSession(frames: [frame], words: [.init(text: "here", start: 1.2, end: 1.4)], audioOrigin: 100)
        var shown = 0
        session.onManualCapture = { _, previewed in if !previewed { shown += 1 } }
        session.addManualCapture(try frame.screenshot().cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12)))
        session.addManualCapture(try frame.screenshot().cropped(to: CGRect(x: 4, y: 4, width: 20, height: 14)))
        guard shown == 2, session.manualCaptures.count == 2 else { throw failure("Manual captures were not retained") }
        session.stopListening()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-prompt-manual-" + UUID().uuidString)
        let result = try await session.saveReferences(transcript: "Look here.", directory: directory)
        guard result.images.count == 3, result.references.count == 3,
              result.references.map(\.number) == [1, 2, 3],
              result.references.allSatisfy({ !$0.description.isEmpty }) else {
            throw failure("Manual selections must ride along after spoken references")
        }
        let source = PromptReferenceText(transcript: "Look here. Fix this.", session: session.id)
        let rendered = source.resolve(source.text, references: result.references)
        guard rendered == "Look here [attached screenshot: [1]]. Fix this." else {
            throw failure("Spoken mentions must stay inline without appending unspoken manual selections")
        }
        let manualSizes = [(16, 12), (20, 14)]
        for (capture, expected) in zip(result.images.suffix(2), manualSizes) {
            guard let data = try? Data(contentsOf: capture), let rep = NSBitmapImageRep(data: data),
                  rep.pixelsWide == expected.0, rep.pixelsHigh == expected.1 else {
                throw failure("Manual crop did not save the selected area at its own size")
            }
        }
        let pendingSession = PromptModeSession()
        var callbacks: [@MainActor (PromptScreenshot?) -> Void] = []
        let operation: PromptModeSession.AreaCapture = { _, completion in callbacks.append(completion) }
        pendingSession.captureArea(CGRect(x: 0, y: 0, width: 16, height: 12), using: operation)
        pendingSession.captureArea(CGRect(x: 4, y: 4, width: 20, height: 14), using: operation)
        pendingSession.stopListening()
        let pending = Task { try await pendingSession.saveReferences(transcript: "", directory: directory) }
        await Task.yield()
        callbacks[1](try frame.screenshot().cropped(to: CGRect(x: 4, y: 4, width: 20, height: 14)))
        callbacks[0](try frame.screenshot().cropped(to: CGRect(x: 0, y: 0, width: 16, height: 12)))
        let pendingResult = try await pending.value
        guard pendingResult.images.count == 2,
              NSBitmapImageRep(data: try Data(contentsOf: pendingResult.images[0]))?.pixelsWide == 16,
              NSBitmapImageRep(data: try Data(contentsOf: pendingResult.images[1]))?.pixelsWide == 20 else {
            throw failure("Finishing lost in-flight captures or reversed click order")
        }
        let cancelledManual = PromptModeSession()
        var late: (@MainActor (PromptScreenshot?) -> Void)?
        cancelledManual.captureArea(.zero, using: { _, callback in late = callback })
        cancelledManual.cancel()
        late?(try frame.screenshot())
        guard cancelledManual.manualCaptures.isEmpty else { throw failure("Late capture escaped cancellation") }

        session.cancel()
        guard session.manualCaptures.isEmpty else { throw failure("Cancelled session retained manual captures") }
        let directCrop = try frame.screenshot(cropping: CGRect(x: 4, y: 4, width: 20, height: 14))
        let originalCrop = try frame.screenshot().cropped(to: CGRect(x: 4, y: 4, width: 20, height: 14))
        guard directCrop.png == originalCrop.png, directCrop.region == originalCrop.region else { throw failure("Direct crop changed selected pixels") }
        // On-demand captures arrive as CGImages at full pixel density; check the encoder they use.
        guard let retina = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 1200, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 6400, bitsPerPixel: 32) else { throw failure("Retina fixture") }
        memset(retina.bitmapData!, 90, 6400 * 1200)
        let retinaRegion = CGRect(x: 300, y: 200, width: 800, height: 600)
        guard let encoded = PromptScreenshot.encode(retina.cgImage!, region: retinaRegion),
              let decoded = NSBitmapImageRep(data: encoded.png), decoded.pixelsWide == 1600, decoded.pixelsHigh == 1200,
              encoded.region == retinaRegion, encoded.pointer == CGPoint(x: 800, y: 600),
              let preview = encoded.thumbnail, max(preview.width, preview.height) == 420 else {
            throw failure("On-demand capture lost pixel density, region, pointer or its deck thumbnail")
        }
        let cocoa = CGRect(x: -1200, y: 880, width: 800, height: 600)
        let screen = CGRect(x: -1440, y: 700, width: 1440, height: 900)
        let quartz = CGRect(x: -1440, y: -700, width: 1440, height: 900)
        let converted = PromptScreenshot.quartzRect(fromCocoa: cocoa, screenFrame: screen, quartzBounds: quartz)
        guard PromptScreenshot.cocoaRect(fromQuartz: converted, screenFrame: screen, quartzBounds: quartz) == cocoa else { throw failure("Offset display conversion") }

        let capped = PromptModeSession(frames: [frame], words: [.init(text: "here", start: 1.2, end: 1.4)], audioOrigin: 100)
        for _ in 0..<64 { guard capped.addManualCapture(directCrop) else { throw failure("Early manual capture limit") } }
        guard !capped.addManualCapture(directCrop) else { throw failure("Capture limit accepted a 65th screenshot") }
        let cappedResult = try await capped.saveReferences(transcript: "here", directory: directory)
        guard cappedResult.images.count == 64, cappedResult.references.allSatisfy({ $0.seconds < 0 }), !cappedResult.warnings.isEmpty else {
            throw failure("Spoken references silently displaced accepted manual captures")
        }

        // The first reference comes 2.8 s after the only frame, beyond the matching window.
        let missingFirst = PromptModeSession(frames: [frame], words: [.init(text: "here", start: 4, end: 4.1), .init(text: "here", start: 1.2, end: 1.4)], audioOrigin: 100)
        missingFirst.addManualCapture(directCrop)
        let mixed = try await missingFirst.saveReferences(transcript: "here here", directory: directory)
        guard mixed.references.map(\.number) == [1, 2], Set(mixed.images).count == 2,
              mixed.references[0].cueIndex == 1, mixed.references[1].cueIndex == nil,
              try Data(contentsOf: mixed.images[0]) != Data(contentsOf: mixed.images[1]) else {
            throw failure("An unmatched spoken reference caused manual screenshot filename collisions")
        }

        let silentSession = PromptModeSession()
        silentSession.addManualCapture(directCrop)
        var silentDelivery = ""
        var silentAttachments = 0
        let silent = AppState(preview: true, api: DictationAPI(transport: PromptProbeTransport(emptySpeech: true)),
            outputPasteboard: NSPasteboard(name: .init("com.s2t.prompt.silent." + UUID().uuidString)), promptSession: silentSession,
            insertPromptImages: { images, _, board, beforeText in silentAttachments = images.count; return .init(sentCount: images.count, issue: nil, clipboardChange: board.changeCount, confirmation: .confirmed) },
            insertText: { text, _ in silentDelivery = text; return .textSent })
        silent.transcriptionProvider = .assemblyAI
        silent.processingProvider = .openRouter
        silent.assemblyKey = "fixture"
        silent.routerKey = "fixture"
        silent.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24000), sampleRate: 48000))
        for _ in 0..<200 {
            if silent.phase == .complete || silent.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard silent.phase == .complete, silentAttachments == 1, silentDelivery.contains("[attached screenshot: [1]]") else {
            throw failure("A screenshot-only prompt was blocked by empty speech: phase=\(silent.phase), images=\(silentAttachments), error=\(silent.errorMessage ?? silent.notice ?? "none")")
        }

        let tooSmall = PromptScreenshot(png: sourcePNG, pointer: .zero, region: CGRect(x: 0, y: 0, width: 32, height: 24))
        let tiny = try? tooSmall.cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
        guard tiny == nil else { throw failure("Tiny selection accepted") }
        print("Manual captures: cropped selections, numbering after spoken references, cancellation and undersized rejection PASS using generated PNGs.")
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
        let pointer = PromptRegionCapture(present: false)
        pointer.start()
        var clicks = 0
        pointer.onClick = { _ in clicks += 1 }
        shortcut.onPromptPointer = { type, event in pointer.receive(type: type, event: event) }
        listening = true
        _ = shortcut.receive(type: .flagsChanged, event: event(54, right))
        let mouse = CGEvent(source: nil)!
        mouse.flags = right
        mouse.location = CGPoint(x: 150, y: 150)
        guard shortcut.receive(type: .leftMouseDown, event: mouse), shortcut.receive(type: .leftMouseUp, event: mouse) else {
            throw failure("Command capture leaked into the receiving app")
        }
        _ = shortcut.receive(type: .flagsChanged, event: event(54))
        try await settle()
        guard prompt.isEmpty, clicks == 1 else { throw failure("Capture Command release stopped a latched prompt") }
        pointer.stop()
        shortcut.onPromptPointer = nil
        listening = false
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
    var cleanupFails = false
    var emptySpeech = false
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == "/v1/transcribe" {
            return (Data((emptySpeech ? #"{"text":""}"# : #"{"text":"Please fix this button, look here. Keep the footer."}"#).utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as? [[String: Any]] ?? []
        if let source = messages.last?["content"] as? String {
            let text = try JSONDecoder().decode([String: String].self, from: Data(source.utf8))["dictated_text"]!
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": text]]]])
            return (data, HTTPURLResponse(url: request.url!, statusCode: cleanupFails ? 500 : 200, httpVersion: nil, headerFields: nil)!)
        }
        throw ServiceError.message("Unexpected non-text cleanup request")
    }
}

private struct PromptProbeCodex: CodexServing {
    let fails: Bool
    func complete(instructions: String, prompt: String, model: String, executable: String, options: CodexOptions) async throws -> String {
        if fails { throw ServiceError.message("Synthetic Codex failure") }
        return try JSONDecoder().decode([String: String].self, from: Data(prompt.utf8))["dictated_text"]!
    }
}
