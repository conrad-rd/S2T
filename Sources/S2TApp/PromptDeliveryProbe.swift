import AppKit
import S2TCore

@MainActor enum PromptDeliveryProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-attachment-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 160, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 150, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let urls = [folder.appendingPathComponent("fixture-1.png"), folder.appendingPathComponent("fixture-2.png")]
        for url in urls { try png.write(to: url) }
        let board = NSPasteboard(name: .init("com.s2t.attachments.check." + UUID().uuidString))
        let pid: pid_t = 345678
        let baseline = PromptAttachmentSnapshot(field: 1, names: [], images: 0, busy: false)
        var pastes = 0
        let post: (pid_t) -> Bool = { _ in pastes += 1; return true }
        for rejection in [AXError.actionUnsupported, .notImplemented] {
            var nativeAttempts = 0
            let before = pastes
            let result = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
                observe: { _, _ in nil }, currentRecipient: { pid },
                nativePaste: { nativeAttempts += 1; return rejection }, canPost: { true }, postPaste: post, waitForPaste: {})
            guard nativeAttempts == 1, pastes == before + 1, result.sentCount == urls.count else {
                throw failure("An unsupported accessibility Paste action dropped the screenshots instead of using the keyboard paste")
            }
        }
        var destinationMatches = true
        let beforeChangedTarget = pastes
        let changedTarget = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, destinationIsCurrent: { destinationMatches },
            nativePaste: { destinationMatches = false; return .actionUnsupported },
            canPost: { true }, postPaste: post, waitForPaste: {})
        guard changedTarget.sentCount == 0, pastes == beforeChangedTarget else {
            throw failure("Fallback pasted into a field selected after the native action failed")
        }
        let nativeOnly = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, nativePaste: { .success },
            canPost: { false }, postPaste: post, waitForPaste: {})
        guard nativeOnly.sentCount == urls.count, pastes == beforeChangedTarget else {
            throw failure("A working native Paste was blocked by an unrelated event-posting check")
        }
        pastes = 0
        let unobserved = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, canPost: { true }, postPaste: post, waitForPaste: {})
        guard unobserved.confirmation == .unknown, pastes == 1 else { throw failure("An unobservable paste was skipped or claimed as confirmed") }
        for (after, expected) in [
            (PromptAttachmentSnapshot(field: 1, names: Set(urls.map(\.lastPathComponent)), images: 0, busy: false), PromptImageInsertion.Confirmation.confirmed),
            (PromptAttachmentSnapshot(field: 1, names: [], images: 2, busy: false), .confirmed),
            (baseline, .absent),
            (PromptAttachmentSnapshot(field: 1, names: [], images: 0, busy: true), .unknown),
            (PromptAttachmentSnapshot(field: 2, names: [], images: 0, busy: false), .unknown)
        ] {
            var reads = 0
            let result = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
                observe: { _, _ in reads += 1; return reads == 1 ? baseline : after }, currentRecipient: { pid },
                canPost: { true }, postPaste: post, waitForPaste: {})
            guard result.confirmation == expected, result.sentCount == 2, result.targetChanged == (after.field != 1) else {
                throw failure("Attachment observation confused accepted, absent, busy or changed fields")
            }
        }
        let previous = pastes
        let late = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, names in .init(field: 1, names: Set(names), images: 2, busy: false) }, currentRecipient: { pid },
            canPost: { true }, postPaste: post, waitForPaste: {})
        guard late.confirmation == .confirmed, pastes == previous else { throw failure("A late attachment was pasted twice") }
        var delayedReads = 0
        let delayed = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in
                delayedReads += 1
                return delayedReads < 3 ? baseline : .init(field: 1, names: [], images: 2, busy: false)
            }, currentRecipient: { pid }, canPost: { true }, postPaste: post, waitForPaste: {})
        let delayedConfirmation = await delayed.recheck?()
        guard delayed.confirmation == .absent, delayedConfirmation == .confirmed else { throw failure("Late image acceptance was not rechecked before retry") }

        for (confirmation, expectedOrder) in [
            (PromptImageInsertion.Confirmation.confirmed, ["text", "images:last"]),
            (.absent, ["text", "images:last"]),
            (.notSent, ["text", "images:last"]),
            (.unknown, ["text", "images:last"])
        ] {
            let session = PromptModeSession()
            session.addManualCapture(PromptScreenshot(png: png, pointer: .zero, region: CGRect(x: 0, y: 0, width: 40, height: 30)))
            var order: [String] = []
            let state = AppState(preview: true, api: DictationAPI(transport: DeliveryTransport()), promptSession: session,
                insertPromptImages: { images, _, board, before in
                    order.append(before ? "images:first" : "images:last")
                    return .init(sentCount: before && confirmation == .notSent ? 0 : images.count, issue: nil, clipboardChange: board.changeCount,
                                 confirmation: confirmation)
                }, insertText: { _, _ in order.append("text"); return .textSent })
            state.transcriptionProvider = .assemblyAI; state.processingProvider = .openRouter
            state.mode = .verbatim; state.assemblyKey = "fixture"
            state.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24000), sampleRate: 48000))
            for _ in 0..<200 {
                if state.phase == .complete || state.phase == .failed { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard state.phase == .complete, order == expectedOrder else { throw failure("Atomic-text then image delivery order: \(order)") }
            state.cancel()
        }
        let session = PromptModeSession()
        session.addManualCapture(PromptScreenshot(png: png, pointer: .zero, region: CGRect(x: 0, y: 0, width: 40, height: 30)))
        var attempts = 0
        let state = AppState(preview: true, api: DictationAPI(transport: DeliveryTransport()), promptSession: session,
            insertPromptImages: { images, _, board, _ in
                attempts += 1
                return .init(sentCount: images.count, issue: nil, clipboardChange: board.changeCount,
                    confirmation: .absent, recheck: { .confirmed })
            }, insertText: { _, _ in .textSent })
        state.transcriptionProvider = .assemblyAI
        state.mode = .verbatim; state.assemblyKey = "fixture"
        state.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24000), sampleRate: 48000))
        for _ in 0..<200 {
            if state.phase == .complete || state.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard state.phase == .complete, attempts == 1 else {
            throw failure("Late confirmation caused a duplicate attachment")
        }
        state.cancel()
        try await verifyDelayedClipboard(urls: urls, png: png, pid: pid)
        print("Attachment delivery: text-before-image order, accepted metadata, no duplicate after a sent request, late acceptance and changed-field guards PASS with fake recipients and isolated clipboard.")
    }

    private static func verifyDelayedClipboard(urls: [URL], png: Data, pid: pid_t) async throws {
        let board = NSPasteboard(name: .init("com.s2t.delayed-images." + UUID().uuidString))
        let result = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, canPost: { true }, postPaste: { _ in true }, waitForPaste: {})
        guard !result.canReleaseClipboard else { throw failure("Unread images were treated as consumed") }
        let text = "Prompt text after image paste."
        let outcome = try await TextInsertion.sendUnicode(text, to: pid, pasteboard: board, copyAfterDelivery: false,
            canPost: { true }, post: { _, _ in })
        guard outcome == .textSent, board.changeCount == result.clipboardChange, !result.canReleaseClipboard,
              let items = board.pasteboardItems, items.count == urls.count else { throw failure("Prompt text replaced the pending screenshot clipboard") }
        guard items[0].data(forType: .png) == png, result.clipboardWasRead?() == false else { throw failure("Reading one image acknowledged the whole batch") }
        guard items[1].data(forType: .png) == png, result.clipboardWasRead?() == true, !result.canReleaseClipboard else {
            throw failure("Delayed screenshot reader lost images or a clipboard read was mistaken for attachment acceptance")
        }
        for (item, url) in zip(items, urls) {
            guard item.string(forType: .fileURL) == url.absoluteString else { throw failure("Lazy payload lost saved filenames") }
        }
        let next = try await PromptImageInsertion.insert(urls, recipient: pid, board: board,
            observe: { _, _ in nil }, currentRecipient: { pid }, canPost: { true }, postPaste: { _ in true }, waitForPaste: {})
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard files == urls, next.clipboardWasRead?() == true else { throw failure("Native file-list consumer did not read the ordered images") }
        print("Delayed image handoff: text delivery preserves unread PNGs, partial reads do not release the batch, and native file/PNG consumers receive every generated image. Isolated pasteboard only.")
    }
    private static func failure(_ message: String) -> Error { ServiceError.message(message) }
}

private struct DeliveryTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json = request.url?.path == "/v1/transcribe" ? #"{"text":"Use this layout."}"#
            : #"{"choices":[{"finish_reason":"stop","message":{"content":"{\"descriptions\":[\"A reference layout.\"]}"}}]}"#
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
