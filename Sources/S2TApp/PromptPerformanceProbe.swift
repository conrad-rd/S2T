import AppKit
import S2TCore

@MainActor enum PromptPerformanceProbe {
    static func run() async throws {
        try await Task.detached { try PromptScreenRecorder.benchmarkEncoding() }.value
        PromptRegionCapture.benchmark()
        try WithinInputExpansionProbe.benchmark()
        let screenshot = try benchmarkImagePreparation()
        PromptCaptureFeedback.benchmark(screenshot)
        PromptCaptureRenderingProbe.benchmark()
        await PromptCaptureRenderingProbe.benchmarkUnderLoad()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s2t-timing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = try (0..<8).map { index -> URL in
            let url = directory.appendingPathComponent("reference-\(index).png")
            try Data([1, 2, 3]).write(to: url)
            return url
        }
        let board = NSPasteboard(name: .init("com.s2t.timing." + UUID().uuidString))
        var pastes = 0
        let pasteStart = ProcessInfo.processInfo.systemUptime
        _ = try await PromptImageInsertion.insert(urls, recipient: 123456, board: board,
            observe: { _, _ in nil }, currentRecipient: { 123456 }, canPost: { true }, postPaste: { _ in pastes += 1; return true })
        let delivery = ProcessInfo.processInfo.systemUptime - pasteStart
        print(String(format: "Eight references: attachment waiting %.3fs; %d paste events.", delivery, pastes))
        print("Attachment code uses its production delay. No real providers, screen capture, clipboard or posted events.")
    }

    private static func benchmarkImagePreparation() throws -> PromptScreenshot {
        let width = 2560, height = 1440
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let bytes = bitmap.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let grid = (x / 80 + y / 40) % 2 == 0
                bytes[i] = UInt8((x * 17 + y * 7) % 48 + (grid ? 150 : 30))
                bytes[i + 1] = UInt8((x + y) % 64 + 70)
                bytes[i + 2] = UInt8((x * 3 + y) % 96 + 90)
                bytes[i + 3] = 255
            }
        }
        let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])!
        let frame = PromptScreenRecorder.Frame(time: 1, pointer: CGPoint(x: 800, y: 600),
            region: CGRect(x: 0, y: 0, width: width, height: height), image: jpeg)
        let rect = CGRect(x: 400, y: 300, width: 800, height: 600)
        var times: [Double] = []
        for _ in 0..<9 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = try frame.screenshot(cropping: rect)
            times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let screenshot = try frame.screenshot()
        let png = screenshot.png
        print(String(format: "Generated 2560×1440 frame → 800×600 selection: median %.2f ms, max %.2f ms. Eight full PNG inputs: %d bytes.", times.sorted()[4], times.max()!, png.count * 8))
        return screenshot
    }
}
