import AppKit
import S2TCore

@MainActor enum PromptPerformanceProbe {
    static func run() async throws {
        let transport = PromptLatencyTransport()
        let api = DictationAPI(transport: transport)
        let start = ProcessInfo.processInfo.systemUptime
        _ = try await api.describePromptImages((1...8).map {
            PromptImageInput(number: $0, png: Data([1, 2, 3]), pointer: .zero, seconds: Double($0), phrase: "here")
        }, transcript: "here", model: "fixture/vision", apiKey: "fixture")
        let analysis = ProcessInfo.processInfo.systemUptime - start
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
            currentRecipient: { 123456 }, canPost: { true }, postPaste: { _ in pastes += 1; return true })
        let delivery = ProcessInfo.processInfo.systemUptime - pasteStart
        print(String(format: "Eight references: analysis %.3fs, attachment waiting %.3fs; %d metadata reads, %d vision requests, %d paste events.", analysis, delivery, await transport.metadata, await transport.vision, pastes))
        print("Controlled workload: each metadata response waits 40 ms; each vision response waits 250 ms. Attachment code uses its production delay. No real providers, screen capture, clipboard or posted events.")
    }
}

private actor PromptLatencyTransport: HTTPTransport {
    private(set) var metadata = 0
    private(set) var vision = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: Data
        if request.url!.path.hasSuffix("/endpoints") {
            metadata += 1
            try await Task.sleep(nanoseconds: 40_000_000)
            json = Data(#"{"data":{"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}}"#.utf8)
        } else {
            vision += 1
            try await Task.sleep(nanoseconds: 250_000_000)
            let content = try JSONSerialization.data(withJSONObject: ["descriptions": Array(repeating: "The nearby panel.", count: 8)])
            json = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": String(decoding: content, as: UTF8.self)]]]])
        }
        return (json, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
