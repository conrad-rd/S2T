import AppKit
import S2TCore

/// Times the work Prompt mode adds after recording stops, using generated frames,
/// an isolated pasteboard and a simulated recipient. No screen capture, providers or posted events.
@MainActor enum PromptPipelineBenchmark {
    static func run() async throws {
        let displaySize = CGSize(width: 1728, height: 1117)
        let variants = (0..<4).map { image(width: Int(displaySize.width), height: Int(displaySize.height), seed: $0, jpeg: true) }
        let encoded = variants.map { PromptScreenRecorder.Frame.Image(data: $0, size: displaySize) }
        let region = CGRect(origin: .zero, size: displaySize)
        let frames = (0..<120).map { index in
            PromptScreenRecorder.Frame(time: 100 + Double(index) / 4, pointer: CGPoint(x: 600, y: 400), region: region, encoded: encoded[index / 30])
        }
        let transcript = "Please look here at the header. Then check this out in the sidebar. And fix it here too."
        let words = transcript.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: 1 + Double(index) * 1.4, end: 1.3 + Double(index) * 1.4)
        }
        let manualPNG = image(width: 1600, height: 1200, seed: 7, jpeg: false)
        let manual = PromptScreenshot(png: manualPNG, pointer: CGPoint(x: 800, y: 600), region: CGRect(x: 100, y: 100, width: 800, height: 600))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-prompt-pipeline-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var selection: [Double] = []
        var images: [URL] = []
        for run in 0..<5 {
            let session = PromptModeSession(frames: frames, words: words, audioOrigin: 100)
            session.addManualCapture(manual); session.addManualCapture(manual)
            session.stopListening()
            let start = ProcessInfo.processInfo.systemUptime
            let result = try await session.saveReferences(transcript: transcript, directory: root.appendingPathComponent("\(run)"))
            selection.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            guard result.images.count == 5 else { throw ServiceError.message("Pipeline benchmark expected five screenshots, received \(result.images.count)") }
            images = result.images
        }
        selection.sort()
        print(String(format: "Screenshots after stop (3 spoken references on %.0f×%.0f frames + 2 selections): median %.1f ms, max %.1f ms.",
            displaySize.width, displaySize.height, selection[2], selection[4]))

        for (width, height) in [(1600, 1200), (3456, 2234)] {
            let source = NSBitmapImageRep(data: image(width: width, height: height, seed: 3, jpeg: false))!.cgImage!
            var preview: [Double] = [], full: [Double] = []
            for _ in 0..<5 {
                let start = ProcessInfo.processInfo.systemUptime
                let thumbnail = PromptScreenshot.thumbnail(from: source)
                preview.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                _ = PromptScreenshot.encode(source, region: .zero, thumbnail: thumbnail)
                full.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            preview.sort(); full.sort()
            print(String(format: "⌘-capture %d×%d px: thumbnail ready %.1f ms; PNG ready %.1f ms (the flight used to wait for this).", width, height, preview[2], full[2]))
        }

        var tails: [Double] = []
        var confirmedAt: [Double] = []
        for _ in 0..<5 {
            let board = NSPasteboard(name: .init("com.s2t.pipeline." + UUID().uuidString))
            defer { board.releaseGlobally() }
            var pasted = false
            let observe: @MainActor (pid_t, [String]) async -> PromptAttachmentSnapshot? = { _, names in
                try? await Task.sleep(nanoseconds: 60_000_000)
                return PromptAttachmentSnapshot(field: 1, names: [], images: pasted ? names.count : 0, busy: false)
            }
            let textPasted = ProcessInfo.processInfo.systemUptime
            let result = try await PromptImageInsertion.handOver(images, recipient: 4242, board: board, observe: observe,
                currentRecipient: { 4242 }, canPost: { true }, postPaste: { _ in
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        for item in board.pasteboardItems ?? [] { _ = item.data(forType: .png) }
                        pasted = true
                    }
                    return true
                }, textPastedAt: textPasted)
            tails.append((result.completedAt - textPasted) * 1000)
            let confirmation = try await result.confirm?().confirmation ?? result.confirmation
            confirmedAt.append((ProcessInfo.processInfo.systemUptime - textPasted) * 1000)
            guard confirmation == .confirmed else { throw ServiceError.message("Simulated attachment was not confirmed") }
        }
        tails.sort(); confirmedAt.sort()
        print(String(format: "Text paste → screenshots handed over: median %.0f ms; → attachment confirmed: median %.0f ms.", tails[2], confirmedAt[2]))
        print("Simulated recipient: 60 ms Accessibility reads, clipboard read 30 ms after paste. Generated images, isolated pasteboard, no posted events or screen capture.")
    }

    private static func image(width: Int, height: Int, seed: Int, jpeg: Bool) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let bytes = bitmap.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let text = (x / 7 + y / 13 + seed) % 5 == 0 && (y / 13) % 3 != 0
                let shade = UInt8((x / 97 + y / 61 + seed * 3) % 4 * 20 + 170)
                bytes[i] = text ? 40 : shade; bytes[i + 1] = text ? 44 : shade &+ 6; bytes[i + 2] = text ? 52 : shade &+ 12; bytes[i + 3] = 255
            }
        }
        return jpeg ? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])! : bitmap.representation(using: .png, properties: [:])!
    }
}
