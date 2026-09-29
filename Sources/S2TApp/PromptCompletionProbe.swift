import AppKit
import S2TCore

@MainActor enum PromptCompletionProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain(["promptDescriptionsEnabled": true, "visionUsesCredits": true, "promptVisionProvider": "openrouter"], forName: "com.s2t.preview")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 128, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 180, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let frames = [1.2, 2.2].map {
            PromptScreenRecorder.Frame(time: 100 + $0, pointer: .zero, region: CGRect(x: 0, y: 0, width: 32, height: 24), image: png)
        }
        let expectedPNG = try frames[0].screenshot().png
        let session = PromptModeSession(frames: frames, words: [.init(text: "here", start: 1.2, end: 1.4), .init(text: "here", start: 2.2, end: 2.4)], audioOrigin: 100)
        let transport = CompletionTransport()
        let board = NSPasteboard(name: .init("com.s2t.completion." + UUID().uuidString))
        var delivered = "", order: [String] = []
        let state = AppState(preview: true, api: DictationAPI(transport: transport), outputPasteboard: board, promptSession: session,
            insertPromptImages: { images, _, board, _ in
                guard images.count == 2, try images.map({ try Data(contentsOf: $0) }).allSatisfy({ $0 == expectedPNG }) else {
                    throw ServiceError.message("Completion changed the generated screenshots")
                }
                order.append("images")
                return .init(sentCount: images.count, issue: nil, clipboardChange: board.changeCount, confirmation: .confirmed)
            }, insertText: { text, _ in delivered = text; order.append("text"); return .textSent })
        state.speechUsesCredits = false; state.cleanupUsesCredits = false
        state.transcriptionProvider = .assemblyAI; state.assemblyKey = "fixture"
        state.processingProvider = .openRouter; state.routerKey = "fixture"; state.processingModel = "fixture/cleanup"
        state.mode = .clean
        let started = ProcessInfo.processInfo.systemUptime
        state.processRecording(WaveAudio.encode(samples: Array(repeating: 0, count: 24_000), sampleRate: 48_000))
        for _ in 0..<500 {
            if state.phase == .complete || state.phase == .failed { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard state.phase == .complete,
              delivered == "Match this layout here [attached screenshot: [1]]. Make that button like here [attached screenshot: [2]]. Keep the footer.",
              state.promptImages.count == 2, order == ["text", "images"] else {
            throw ServiceError.message("Completion failed: \(state.errorMessage ?? state.phase.label)")
        }
        try await transport.verifyRequests()
        print(String(format: "Prompt completion %.3f s; speech and cleanup requests only; order %@. Existing image-description preferences are ignored. Generated images, injected delivery.", elapsed, order.joined(separator: ",")))
        state.cancel()
        let text = String(repeating: "Keep this layout. ", count: 100)
        let unicodeStart = ProcessInfo.processInfo.systemUptime
        _ = try await TextInsertion.sendUnicode(text, to: 123, pasteboard: board, copyAfterDelivery: false, canPost: { true }, post: { _, _ in })
        let unicodeTime = ProcessInfo.processInfo.systemUptime - unicodeStart
        let pasteStart = ProcessInfo.processInfo.systemUptime
        let outcome = TextInsertion.pasteBatch(text, to: board) { board.string(forType: .string) == text }
        guard outcome == .textSent else { throw ServiceError.message("Batch clipboard staging failed") }
        print(String(format: "1700-character delivery preparation: Unicode pacing %.3f s, atomic clipboard action %.3f s. Injected actions only; not live receiving-app latency.", unicodeTime, ProcessInfo.processInfo.systemUptime - pasteStart))
    }
}

private actor CompletionTransport: HTTPTransport {
    private var speech = 0
    private var cleanup = 0

    func verifyRequests() throws {
        guard speech == 1, cleanup == 1 else {
            throw ServiceError.message("Prompt completion must make only one speech and one cleanup request")
        }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        if request.url?.path == "/v1/transcribe" {
            speech += 1
            try await Task.sleep(nanoseconds: 200_000_000)
            json = #"{"text":"Use this layout here. Make that button like here. Keep the footer."}"#
        } else {
            guard request.url?.path == "/api/v1/chat/completions",
                  let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any],
                  body["model"] as? String == "fixture/cleanup" else {
                throw ServiceError.message("Prompt completion made an unexpected request")
            }
            cleanup += 1
            let messages = body["messages"] as? [[String: String]] ?? []
            let payload = try JSONDecoder().decode([String: String].self, from: Data((messages.last?["content"] ?? "").utf8))
            let source = payload["dictated_text"] ?? ""
            guard source.components(separatedBy: "__S2T_SCREENSHOT_").count == 3,
                  messages.first?["content"]?.contains(PromptReferenceText.editingInstruction) == true else {
                throw ServiceError.message("Cleanup did not receive inline markers and their preservation rule")
            }
            let content = source.replacingOccurrences(of: "Use this layout", with: "Match this layout")
            try await Task.sleep(nanoseconds: 250_000_000)
            let data = try JSONSerialization.data(withJSONObject: ["model": "fixture/cleanup", "choices": [["finish_reason": "stop", "message": ["content": content]]]])
            json = String(decoding: data, as: UTF8.self)
        }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
