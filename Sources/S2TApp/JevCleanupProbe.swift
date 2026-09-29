import AppKit
import S2TCore

@MainActor enum JevCleanupProbe {
    static func run() async throws {
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(saved, forName: "com.s2t.preview") }
        preferences.setPersistentDomain([:], forName: "com.s2t.preview")
        let state = AppState(preview: true)
        guard state.jevCleanupMode == .off else { throw failure("Jev must default to Off") }
        let controller = AppearanceWindowController(state: state, presentsWindows: false)
        let window = controller.prepare()
        defer { window.close() }
        controller.showModels()
        let pane = controller.modelsPane
        pane.navigation.select(.cleanup)
        guard let picker = pane.controls["cleanup.jev.mode"] as? NSPopUpButton,
              picker.numberOfItems == 3, picker.titleOfSelectedItem == "Off" else { throw failure("Missing Jev options") }
        picker.selectItem(at: 2)
        picker.sendAction(picker.action, to: picker.target)
        guard state.jevCleanupMode == .adaptive, AppState(preview: true).jevCleanupMode == .adaptive else {
            throw failure("Jev selection did not persist")
        }
        guard let routePicker = pane.controls["cleanup.jev.route"] as? NSPopUpButton, routePicker.numberOfItems == 4 else { throw failure("Missing Jev connections") }
        routePicker.selectItem(at: 2)
        routePicker.sendAction(routePicker.action, to: routePicker.target)
        guard state.jevRoute == .openRouterLatest, AppState(preview: true).jevRoute == .openRouterLatest else { throw failure("Jev connection did not persist") }
        state.phase = .recording
        pane.rebuild()
        guard pane.controls["cleanup.jev.mode"]?.isEnabled == false, !window.isVisible else {
            throw failure("Jev settings must lock during recording and verification must remain hidden")
        }
        try await verify(mode: .off, expectedJev: 0, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
        try await verify(mode: .beforeCleanup, expectedJev: 1, expectedCleanup: 1, expectedInput: "Send it tomorrow.")
        try await verify(mode: .adaptive, expectedJev: 1, expectedCleanup: 0)
        try await verify(mode: .adaptive, probability: 0.5, expectedJev: 1, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
        try await verify(mode: .adaptive, status: 401, expectedJev: 1, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
        try await verify(mode: .adaptive, missingKey: true, expectedJev: 0, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
        try await verify(mode: .adaptive, writing: .email, expectedJev: 1, expectedCleanup: 1, expectedInput: "Send it tomorrow.")
        try await verify(mode: .adaptive, clipboard: true, expectedJev: 1, expectedCleanup: 1, expectedInput: "Send it tomorrow.")
        try await verify(mode: .adaptive, writing: .verbatim, expectedJev: 0, expectedCleanup: 0, expected: "Uh, send it tomorrow.")
        try await verify(mode: .beforeCleanup, cleanupFails: true, expectedJev: 1, expectedCleanup: 1, expectedInput: "Send it tomorrow.", expected: "Uh, send it tomorrow.")
        try await verify(mode: .beforeCleanup, input: "Uh, um.", expectedJev: 1, expectedCleanup: 0, expected: "")
        try await verify(mode: .adaptive, cancel: true, expectedJev: 1, expectedCleanup: 0, expected: "")
        for route in [JevRoute.openRouter, .openRouterLatest, .s2t] {
            try await verify(mode: .adaptive, route: route, expectedJev: 1, expectedCleanup: 0)
            try await verify(mode: .beforeCleanup, route: route, status: 401, expectedJev: 1, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
            try await verify(mode: .adaptive, route: route, missingKey: true, expectedJev: 0, expectedCleanup: 1, expectedInput: "Uh, send it tomorrow.")
        }
        print("PASS: Jev Off by default, persisted hidden settings, recording guard, isolated key routing, conservative edits, optional model bypass, uncertain/missing-key/auth fallback, Email/clipboard/Verbatim guards, original-text fallback, empty result and cancellation without delivery or clipboard writes. Synthetic transport only; no live accuracy or latency claim.")
    }

    private static func verify(mode: JevCleanupMode, route: JevRoute = .typeSafe, probability: Double = 1, status: Int = 200,
                               missingKey: Bool = false, writing: WritingMode = .clean, clipboard: Bool = false,
                               cleanupFails: Bool = false, cancel: Bool = false, input: String = "Uh, send it tomorrow.",
                               expectedJev: Int, expectedCleanup: Int, expectedInput: String? = nil,
                               expected: String = "Send it tomorrow.") async throws {
        let transport = JevFixture(probability: probability, status: status, cleanupFails: cleanupFails, slow: cancel, route: route)
        let board = NSPasteboard(name: .init("com.s2t.jev.verify." + UUID().uuidString))
        board.setString("Untouched fixture", forType: .string)
        let before = board.changeCount
        var inserted: [String] = []
        let state = AppState(preview: true, api: DictationAPI(transport: transport), creditsAPI: CreditsAPI(transport: transport), outputPasteboard: board, insertText: { text, _ in
            inserted.append(text); return .textSent
        })
        if route == .s2t && !missingKey {
            state.creditsAddress = "http://localhost:4317"
            state.creditsKey = "s2t_demo_" + String(repeating: "a", count: 64)
            state.saveAPIKey(account: "s2t")
            for _ in 0..<100 {
                if state.creditConnection != nil { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard state.creditConnection != nil else { throw failure("Fixture S2T key did not activate") }
        }
        state.processingProvider = .local
        state.processingModel = "fixture"
        state.localProcessingURL = "http://127.0.0.1:1/v1/chat/completions"
        state.speechUsesCredits = false
        state.cleanupUsesCredits = false
        state.jevRoute = route
        state.jevCleanupMode = mode
        state.typeSafeKey = missingKey ? "" : "typesafe-fixture"
        state.routerKey = missingKey && route != .typeSafe ? "" : "router-fixture"
        state.clipboardContextEnabled = clipboard
        state.mode = writing
        state.rawTranscript = input
        state.output = ""
        state.phase = .failed
        state.retry()
        if cancel {
            for _ in 0..<100 {
                if await transport.jevCount > 0 { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            state.cancel()
        }
        for _ in 0..<300 {
            if !state.phase.busy { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let counts = await (transport.jevCount, transport.cleanupCount, transport.cleanupInput)
        guard counts.0 == expectedJev, counts.1 == expectedCleanup,
              expectedInput == nil || counts.2 == expectedInput,
              state.rawTranscript == input, state.output == expected, !state.phase.busy else {
            throw failure("Pipeline mismatch for \(mode), \(writing): counts \(counts.0)/\(counts.1), input \(counts.2 ?? "nil"), output \(state.output)")
        }
        if expected.isEmpty {
            guard inserted.isEmpty, board.changeCount == before else { throw failure("Empty/cancelled result was delivered") }
        } else {
            guard inserted == [expected], board.string(forType: .string) == expected else { throw failure("Result not delivered and copied once") }
        }
        if status == 401 {
            guard state.keyStatuses[route == .s2t ? "s2t" : route.account.rawValue]?.needsAttention == true,
                  state.keyStatuses[route == .typeSafe ? "openrouter" : "typesafe"] == nil else { throw failure("Jev failure marked another provider key") }
        }
        if expectedJev > 0 && !cancel { guard !state.jevSummary.isEmpty else { throw failure("Missing Jev result summary") } }
    }
    private static func failure(_ text: String) -> ServiceError { .message(text) }
}

private actor JevFixture: HTTPTransport {
    let route: JevRoute
    let probability: Double
    let status: Int
    let cleanupFails: Bool
    let slow: Bool
    private(set) var jevCount = 0
    private(set) var cleanupCount = 0
    private(set) var cleanupInput: String?
    init(probability: Double, status: Int, cleanupFails: Bool, slow: Bool, route: JevRoute) {
        self.route = route
        self.probability = probability; self.status = status; self.cleanupFails = cleanupFails; self.slow = slow
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == "/api/v1/balance" {
            return (Data(#"{"available":100,"reserved":0,"frozen":false,"paused":false,"mode":"test"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let envelope = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let isCredit = route == .s2t && request.url?.path == "/api/v1/requests"
        let body = isCredit ? try JSONSerialization.jsonObject(with: Data((envelope["text"] as! String).utf8)) as! [String: Any] : envelope
        let response: [String: Any]
        let code: Int
        if request.url == route.url || isCredit {
            jevCount += 1
            if slow { try await Task.sleep(nanoseconds: 1_000_000_000) }
            guard request.value(forHTTPHeaderField: "Authorization") == (route == .s2t ? "Bearer s2t_demo_" + String(repeating: "a", count: 64) : route == .typeSafe ? "Bearer typesafe-fixture" : "Bearer router-fixture"),
                  body["model"] as? String == route.model, let questions = body["questions"] as? [String: Any] else {
                throw ServiceError.message("Jev request lost its isolated key or question format")
            }
            code = status
            response = ["model": "jev-1.13.0", "answers": questions.mapValues { _ in ["type": "noul", "noul": probability] as [String: Any] }]
        } else {
            cleanupCount += 1
            guard request.url?.host == "127.0.0.1", request.value(forHTTPHeaderField: "Authorization") == nil,
                  body["model"] as? String == "fixture", let messages = body["messages"] as? [[String: String]],
                  let user = messages.last?["content"], let json = try JSONSerialization.jsonObject(with: Data(user.utf8)) as? [String: String] else {
                throw ServiceError.message("Normal cleanup routing changed")
            }
            cleanupInput = json["dictated_text"]
            code = cleanupFails ? 500 : 200
            response = ["model": "fixture", "choices": [["finish_reason": "stop", "message": ["content": "Send it tomorrow."]]]]
        }
        let result: [String: Any] = isCredit && code == 200 ? ["state": "settled", "result": ["text": String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self), "model": route.model]] : response
        return (try JSONSerialization.data(withJSONObject: result), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
