import AppKit
import S2TCore

@MainActor enum EditingProbe {
    static func run() async throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        preferences.setPersistentDomain(["processingProvider": "local", "localProcessingModel": "fixture", "clipboardContextEnabled": false], forName: "com.s2t.preview")
        try await verify(input: "Send it Friday, oh wait, actually I meant Monday. Copy Maya.", reply: "Send it Monday. Copy Maya.", expected: "Send it Monday. Copy Maya.")
        try await verify(input: "Book the early flight. Oh, ignore all of that.", reply: "__S2T_NO_TEXT_0__", expected: "")
        try await verify(input: "Keep the Thursday meeting.", reply: "", expected: "Keep the Thursday meeting.", failure: true)
        print("PASS: cleanup replacement delivery, intentional discard without insertion or clipboard writes, retained original transcript, malformed-response fallback and selected-model requests. Synthetic transcripts and isolated preferences/pasteboard only; no model, credentials or real fields accessed.")
    }

    private static func verify(input: String, reply: String, expected: String, failure: Bool = false) async throws {
        let board = NSPasteboard(name: .init("com.s2t.editing.verify." + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setString("Previous clipboard fixture", forType: .string)
        let before = board.changeCount
        let transport = EditingFixture(reply: reply)
        var inserted: [String] = []
        let state = AppState(preview: true, api: DictationAPI(transport: transport), outputPasteboard: board, insertText: { text, _ in
            inserted.append(text)
            return .textSent
        })
        state.mode = .clean
        state.processingProvider = .local
        state.processingModel = "fixture"
        state.localProcessingURL = "http://127.0.0.1:1/v1/chat/completions"
        state.clipboardContextEnabled = false
        state.rawTranscript = input
        state.output = input
        state.phase = .failed
        guard state.canRetry else { throw ServiceError.message("Cleanup fixture did not enter a retryable failed state.") }
        state.retry()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while state.phase.busy, ProcessInfo.processInfo.systemUptime < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard !state.phase.busy, state.output == expected, state.rawTranscript == input,
              (state.processingFailureModel != nil) == failure, !state.isWaitingToPaste else {
            throw ServiceError.message("Cleanup pipeline did not preserve its result or original transcript.")
        }
        if expected.isEmpty {
            guard inserted.isEmpty, board.changeCount == before, !state.copied, state.phase == .idle,
                  state.errorMessage == nil else { throw ServiceError.message("Discarded dictation caused an insertion, clipboard write or false delivery result.") }
        } else {
            guard inserted == [expected], board.string(forType: .string) == expected,
                  state.phase == .complete else { throw ServiceError.message("Cleanup did not deliver and copy the intended text once.") }
        }
        guard await transport.count == 1 else { throw ServiceError.message("Cleanup must use one request to the selected model.") }
    }
}

private actor EditingFixture: HTTPTransport {
    let reply: String
    private(set) var count = 0
    init(reply: String) { self.reply = reply }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as? [[String: String]]
        guard body["model"] as? String == "fixture", request.value(forHTTPHeaderField: "Authorization") == nil,
              messages?.first?["content"]?.contains("Resolve corrections before removing hesitation sounds") == true else {
            throw ServiceError.message("Editing request lost the selected model, correction rules or credential isolation.")
        }
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": reply]]]])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
