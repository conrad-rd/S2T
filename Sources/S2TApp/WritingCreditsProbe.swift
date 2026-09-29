import AppKit
import S2TCore

@MainActor enum WritingCreditsProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let transport = WritingCreditsProbeTransport()
        let personalTransport = WritingCreditsProbeTransport()
        let state = AppState(preview: true, creditsAPI: CreditsAPI(transport: transport))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("S2T-writing-credits-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pane = WritingPane(state: state, directory: directory, api: DictationAPI(transport: personalTransport))
        let editing = pane.editing
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 760), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentViewController = pane
        window.setContentSize(NSSize(width: 650, height: 760))
        defer { editing.cancel(); window.close() }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "WritingCreditsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func wait() async throws {
            for _ in 0..<200 where editing.busy { try await Task.sleep(for: .milliseconds(10)) }
            try require(!editing.busy, "Paid writing did not finish")
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fundingControl(_ element: Any, depth: Int = 0) -> NSObject? {
            guard depth < 20, let node = element as? NSObject else { return nil }
            if node.responds(to: NSSelectorFromString("accessibilityIdentifier")),
               node.value(forKey: "accessibilityIdentifier") as? String == "writing.funding" { return node }
            guard node.responds(to: NSSelectorFromString("accessibilityChildren")) else { return nil }
            for child in (node.value(forKey: "accessibilityChildren") as? [Any] ?? []).prefix(100) {
                if let match = fundingControl(child, depth: depth + 1) { return match }
            }
            return nil
        }

        editing.settings.provider = "codex"; editing.settings.codexModel = "personal-codex"
        editing.settings.host = "personal/host"; editing.settings.routerOptions[editing.settings.routerModel] = .init(reasoning: .high)
        let personal = editing.settings
        let dictationModel = state.processingModel, dictationHost = state.routerEndpoint
        editing.selectFunding(.credits)
        editing.instruction = "Preserve names"
        editing.improve(); try await wait()
        try require(editing.error.contains("Connect your S2T account"), "Missing credit connection had no actionable error")
        let missingRequests = await transport.requests
        try require(missingRequests.isEmpty, "Disconnected writing made a paid request")
        state.creditsAddress = "https://credits.example.com"
        let key = "s2t_test_" + String(repeating: "c", count: 64)
        let keys = APIKeyEditing(state: state)
        keys.paste(key, for: "s2t"); keys.save("s2t")
        for _ in 0..<100 where state.creditConnection == nil { try await Task.sleep(for: .milliseconds(10)) }
        try require(state.creditConnection?.key == key, "Fake credit connection did not save")
        try require(editing.modelChoices.count == 1 && editing.modelChoices[0].model == CreditModel.defaults[0].model,
                    "Paid picker exposed models outside its service catalog")
        let picker = WritingModelPickerController(editing: editing, choices: editing.modelChoices, close: {})
        _ = picker.view
        picker.filter("vendor/unavailable", group: "openrouter")
        try require(picker.visibleChoices.isEmpty, "Paid picker accepted an unauthorized custom model")
        try require(descendants(picker.view).compactMap { $0 as? NSButton }.filter { ["codex", "local"].contains($0.identifier?.rawValue ?? "") }.allSatisfy(\.isHidden),
                    "Credit picker offers personal-only connections")
        editing.selectModel(.init(provider: .codex, model: "default", title: "Codex"))
        try require(editing.settings.selectedProvider == .openRouter, "Credit selection switched to personal inference")
        editing.settings.selectedHost = "unauthorized/host"
        editing.improve(); try await wait()
        try require(editing.error.contains("not available"), "Unauthorized credit host was accepted")
        editing.selectModel(editing.modelChoices[0])
        try require(editing.settings.selectedHost == CreditModel.defaults[0].host, "Choosing an allowed route did not repair the invalid host")
        editing.settings.router = .init(reasoning: .low)
        editing.showingAssistant = true
        try await Task.sleep(for: .milliseconds(80)); window.contentView?.layoutSubtreeIfNeeded()
        try require(pane.view.bounds.width == 650 && !window.isVisible, "Writing credit layout exposed or resized its hidden window: \(pane.view.bounds), visible=\(window.isVisible)")
        let funding = fundingControl(pane.view)
        try require(funding != nil, "Writing connection picker is missing from the native composer")
        if let funding, funding.responds(to: NSSelectorFromString("accessibilityFrame")),
           let frame = (funding.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue {
            try require(frame.width > 70 && frame.width < 170,
                        "Writing connection control expanded beyond its compact width")
        }
        for kind in WritingDocumentKind.allCases {
            editing.selection = kind
            editing.text = "# Original \(kind.rawValue)\n"; editing.save()
            let original = editing.text
            editing.improve(); try await wait()
            try require(editing.suggestion == "# Paid suggestion\n- S2T\n" && editing.text == original, "Paid writing bypassed review or lost its result")
            try require(try WritingDocumentFile(directory: directory, kind: kind).read() == original, "Paid writing saved before Apply")
            editing.instruction = "Keep refining"
            editing.improve(); try await wait()
            let request = await transport.requests.last { $0.httpMethod == "POST" }!
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            try require(body["text"]?.contains("# Paid suggestion") == true && body["text"]?.contains(original) == false, "Credit follow-up ignored the current suggestion")
            try require(body["instructions"]?.contains(kind == .instructions ? "instructions for a dictation" : "spelling dictionary") == true,
                        "Credits used dictation cleanup instead of the document contract")
            editing.applySuggestion()
            try require(!editing.dirty && editing.text == "# Paid suggestion\n- S2T\n", "Paid suggestion did not apply and save")
        }
        await transport.configure(delay: true)
        editing.improve()
        try await Task.sleep(for: .milliseconds(30))
        editing.stopTask()
        editing.text = "Newer manual draft"
        try await Task.sleep(for: .milliseconds(180))
        try require(editing.suggestion == nil && editing.text == "Newer manual draft", "Late paid response replaced a manual draft after cancellation")
        await transport.configure(status: 402)
        editing.improve(); try await wait()
        try require(editing.suggestion == nil && editing.error.contains("credit limit") && state.keyStatuses["s2t"]?.needsAttention == true,
                    "Credit account failure was hidden or became a suggestion")
        let personalRequests = await personalTransport.requests
        try require(personalRequests.isEmpty, "Credit failure fell back to a personal provider")
        let paid = editing.settings.creditSettings
        editing.selectFunding(.personal)
        try require(editing.settings.model == personal.codexModel && editing.settings.host == personal.host && editing.settings.routerOptions == personal.routerOptions,
                    "Switching funding overwrote personal settings")
        editing.selectFunding(.credits)
        try require(editing.settings.creditSettings == paid && WritingEditor(state: state, directory: directory).settings == editing.settings,
                    "Paid Writing settings did not persist independently")
        try require(!state.speechUsesCredits && !state.cleanupUsesCredits && state.processingModel == dictationModel && state.routerEndpoint == dictationHost,
                    "Writing funding changed dictation settings")
        let requests = await transport.requests
        try require(requests.allSatisfy { $0.url?.host == "credits.example.com" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + key },
                    "Credit key crossed into a provider request")
        try require(requests.filter { $0.url?.path == "/api/v1/balance" }.count > 1, "Paid writing did not refresh its balance")
        print("PASS: Writing credits for both documents, independent saved funding/models/options, catalog restrictions, native connection control, review/refinement/apply, cancellation, account errors, balance refresh and credential isolation; mock services only.")
    }
}

private actor WritingCreditsProbeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var delay = false
    var status = 200
    func configure(delay: Bool = false, status: Int = 200) { self.delay = delay; self.status = status }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body: String
        let responseStatus: Int
        if request.url?.path == "/api/v1/balance" {
            body = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test"}"#; responseStatus = 200
        } else {
            responseStatus = status
            if delay { try? await Task.sleep(for: .milliseconds(150)) }
            body = status == 200 ? ##"{"state":"settled","result":{"text":"# Paid suggestion\n- S2T\n","model":"openai/gpt-oss-120b","host":"Cerebras"}}"##
                : #"{"error":"This key has reached its credit limit."}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: responseStatus, httpVersion: nil, headerFields: nil)!)
    }
}
