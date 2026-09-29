import AppKit
import SwiftUI
import S2TCore

@MainActor enum CreditsProbe {
    static func run() async throws {
        let defaults = UserDefaults(suiteName: "com.s2t.preview")!
        let saved = defaults.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { defaults.setPersistentDomain(saved, forName: "com.s2t.preview") }
        defaults.setPersistentDomain(["creditsEnabled": true, "transcriptionProvider": "retired-provider", "creditSpeechProvider": "retired-provider"], forName: "com.s2t.preview")
        let migrated = AppState(preview: true)
        guard migrated.speechUsesCredits, migrated.cleanupUsesCredits, migrated.transcriptionProvider == .assemblyAI,
              defaults.string(forKey: "transcriptionProvider") == "assemblyai" else { throw failure("Legacy credits choices were lost") }
        migrated.speechUsesCredits = false
        guard !AppState(preview: true).speechUsesCredits, AppState(preview: true).cleanupUsesCredits else { throw failure("Task choices did not persist independently") }
        defaults.setPersistentDomain([:], forName: "com.s2t.preview")
        let transport = CreditSettingsTransport()
        let state = AppState(preview: true, api: DictationAPI(transport: transport), creditsAPI: CreditsAPI(transport: transport), insertText: { _, _ in .textSent })
        guard state.creditCleanupModel == "openai/gpt-oss-120b", state.creditCleanupHost == "cerebras/fp16" else { throw failure("New credit settings do not match the deployed default route") }
        func catalog(_ extra: String = "") throws -> CreditBalance {
            try JSONDecoder().decode(CreditBalance.self, from: Data((#"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"test""# + extra + "}").utf8))
        }
        state.creditCleanupHost = ""
        state.applyCreditBalance(try catalog())
        guard state.creditCleanupHost == "cerebras/fp16" else { throw failure("Legacy blank default host was not repaired against the fixed service catalog") }
        state.creditCleanupHost = "explicit/host"
        state.applyCreditBalance(try catalog())
        guard state.creditCleanupHost == "explicit/host" else { throw failure("Catalog refresh replaced an explicit host") }
        state.creditCleanupHost = ""
        state.applyCreditBalance(try catalog(#", "openRouterCatalog":true"#))
        guard state.creditCleanupHost.isEmpty else { throw failure("Dynamic catalog automatic routing was replaced") }
        state.applyCreditBalance(try catalog())
        state.creditsAddress = "http://localhost:4317"
        state.mode = .clean
        state.transcriptionProvider = .assemblyAI
        state.transcriptionMode = .fast
        state.processingProvider = .openRouter
        state.processingModel = "personal/model"
        state.routerEndpoint = "personal/host"
        let pane = ModelsPane(state: state)
        _ = pane.view
        func choose(_ id: String, _ value: String) throws {
            if id == "cleanup.suggestion" {
                state.creditCleanupModel = "fixture/changed"
                pane.rebuild()
                guard let choice = state.creditModels.first(where: { $0.operation == "cleanup" && value.contains($0.model) }) else { throw failure("Missing catalog model") }
                let listed = ModelChoiceProbe.item(choice.model, in: (pane.controls["cleanup.choice"] as? NSPopUpButton)?.menu) != nil
                try ModelChoiceProbe.choose(listed ? "cleanup.choice" : "cleanup.model", choice.model, in: pane)
                return
            }
            try ModelChoiceProbe.choose(id, value, in: pane)
        }
        try choose("speech.provider", "s2t")
        guard state.speechUsesCredits, !state.cleanupUsesCredits else { throw failure("Speech selection changed cleanup billing") }
        try choose("cleanup.provider", "s2t")
        guard !state.canRecord else { throw failure("Missing S2T key must block recording") }
        guard pane.controls["credits.key"] == nil, pane.controls["credits.address"] == nil,
              pane.controls["credits.mode"] == nil,
              pane.controls["speech.model"] is NSTextField,
              pane.controls["cleanup.model"] is NSTextField,
              pane.controls["cleanup.credits.provider"] == nil,
              pane.controls["cleanup.choice"] is NSPopUpButton else {
            throw failure("S2T must be available for speech and cleanup without a separate section or key editor")
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = pane.view
        defer { window.contentView = nil }
        for width: CGFloat in [420, 600] {
            window.setContentSize(NSSize(width: width, height: 600))
            pane.view.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            pane.view.layoutSubtreeIfNeeded()
            guard pane.view.bounds.height >= 590 else { throw failure("The Models page resized the settings page at \(width) points") }
            for prefix in ["speech", "cleanup"] {
                let ids = [prefix + ".provider", prefix + ".choice"]
                let frames = try ids.map { id -> CGRect in
                    guard let control = pane.controls[id], !control.isHiddenOrHasHiddenAncestor else { throw failure("Missing visible credit model choice: " + id) }
                    return control.convert(control.bounds, to: pane.view)
                }
                guard frames.allSatisfy({ $0.minX >= 0 && $0.maxX <= width && $0.height > 0 }),
                      !frames[0].intersects(frames[1]),
                      frames.map(\.maxY).max()! - frames.map(\.minY).min()! < 120 else { throw failure("Credit model controls clip, overlap or drift apart: \(width) \(prefix) \(frames)") }
            }
        }
        guard !window.isVisible else { throw failure("Credits verification exposed a window") }
        guard pane.controls["speech.choice"] != nil,
              (pane.controls["cleanup.provider"] as? ModelProviderPicker)?.currentValue == "s2t" else {
            throw failure("S2T must use the same provider/recognition settings without redundant provider rows")
        }
        let editing = APIKeyEditing(state: state)
        func key(_ character: String) -> String { "s2t_demo_" + String(repeating: character, count: 64) }
        editing.paste("provider-key-fixture", for: "s2t")
        guard state.creditsKey.isEmpty, state.creditConnection == nil else { throw failure("Pasting activated the S2T key before Save") }
        editing.save("s2t")
        guard editing.status("s2t")?.needsAttention == true, !editing.saved("s2t") else { throw failure("A vendor key was accepted as an S2T key") }
        editing.paste(key("b"), for: "s2t"); editing.save("s2t")
        try await waitForCheck(state)
        guard editing.message("s2t").contains("rejected"), !editing.saved("s2t"), state.creditConnection == nil else { throw failure("Rejected S2T key showed Saved or became active") }
        editing.paste(key("a"), for: "s2t"); editing.save("s2t")
        try await waitForCheck(state)
        guard state.creditConnection?.key == key("a"), editing.saved("s2t"), !editing.canSave("s2t"),
              editing.status("s2t") == .accepted, state.canRecord, state.setupKeysReady,
              state.assemblyKey.isEmpty, state.routerKey.isEmpty, state.creditBalanceLabel == "10 credits" else { throw failure("One saved S2T key must cover both tasks without vendor keys") }
        let checks = await transport.requests
        guard checks.count == 2, checks.allSatisfy({ $0.httpMethod == "GET" && $0.url?.path == "/api/v1/balance" }) else { throw failure("Saving a key must only check balance without spending credits") }
        guard state.creditModels.contains(where: { $0.model == "openai/gpt-oss-20b" }) else { throw failure("Key did not load the service model catalog") }
        pane.rebuild()
        try ModelChoiceProbe.choose("cleanup.choice", "openai/gpt-oss-120b", in: pane)
        guard state.cleanupUsesCredits, state.creditCleanupModel == "openai/gpt-oss-120b", state.creditCleanupHost == "cerebras/fp16",
              state.processingModel == "personal/model", state.routerKey.isEmpty else {
            throw failure("Cerebras quick choice switched off S2T billing or used the personal key")
        }
        pane.rebuild()
        try choose("cleanup.suggestion", "openrouter:cleanup:openai/gpt-oss-20b:")
        try choose("cleanup.reasoning", "low")
        try choose("cleanup.host", ModelsPane.fastestHost)
        guard state.creditCleanupModel == "openai/gpt-oss-20b", state.creditCleanupHost.isEmpty,
              state.creditCleanupOptions == OpenRouterOptions(reasoning: .low, fast: true),
              state.processingModel == "personal/model", state.routerEndpoint == "personal/host",
              AppState(preview: true).creditCleanupModel == state.creditCleanupModel else { throw failure("S2T settings did not persist independently") }
        try choose("cleanup.suggestion", "openrouter:cleanup:meta/muse-spark-1.3-contributor:")
        guard let consent = pane.controls["cleanup.contributorConsent"] as? NSButton,
              !consent.isHiddenOrHasHiddenAncestor, consent.state == .off,
              !state.creditCleanupOptions.allowDataCollection else { throw failure("Contributor must have an unchecked visible opt-in") }
        consent.performClick(nil)
        guard state.creditCleanupOptions.allowDataCollection,
              AppState(preview: true).creditCleanupOptions.allowDataCollection else { throw failure("Contributor opt-in did not persist") }
        try choose("cleanup.suggestion", "openrouter:cleanup:openai/gpt-oss-20b:")
        guard !state.creditCleanupOptions.allowDataCollection, pane.controls["cleanup.contributorConsent"] == nil,
              state.creditCleanupOptions == OpenRouterOptions(reasoning: .low, fast: true) else { throw failure("Contributor opt-in leaked to another model") }
        let creditSidebar = AppearanceSidebarController()
        let keyWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 88, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        keyWindow.contentViewController = creditSidebar
        defer { keyWindow.contentViewController = nil }
        creditSidebar.updateCredits(state.creditBalance)
        creditSidebar.view.layoutSubtreeIfNeeded()
        guard creditSidebar.creditNumber.title == "10",
              creditSidebar.creditNumber.font?.fontName.hasPrefix("BitcountPropSingle") == true,
              creditSidebar.view.bounds.contains(creditSidebar.creditNumber.frame),
              creditSidebar.creditNumber.frame.minY > creditSidebar.policiesLink.frame.maxY,
              !keyWindow.isVisible else { throw failure("Persistent sidebar credits or bundled font are missing") }
        editing.paste(key("c"), for: "s2t"); editing.save("s2t")
        try await Task.sleep(nanoseconds: 20_000_000)
        editing.paste(key("a"), for: "s2t"); editing.save("s2t")
        try await waitForCheck(state)
        try await Task.sleep(nanoseconds: 200_000_000)
        guard state.creditConnection?.key == key("a"), editing.status("s2t") == .accepted else { throw failure("Stale validation replaced the saved S2T key") }
        for status in [503, -1] {
            await transport.failNextBalance(status)
            await state.refreshCredits()
            guard editing.status("s2t")?.needsAttention == true, state.creditBalance == nil,
                  state.creditConnection?.key == key("a"), state.canRecord else { throw failure("Temporary balance failure must preserve the saved connection and recording access") }
            let beforeRecovery = await transport.requests.count
            await state.refreshCredits()
            let afterRecovery = await transport.requests.count
            guard afterRecovery == beforeRecovery + 1, editing.status("s2t") == .accepted,
                  state.creditBalance?.available == 10 else { throw failure("Recovered billing service is blocked by a stale balance warning after failure \(status)") }
        }
        await transport.failNextBalance(401)
        await state.refreshCredits()
        let rejectedCount = await transport.requests.count
        await state.refreshCredits()
        guard await transport.requests.count == rejectedCount, editing.status("s2t")?.needsAttention == true else { throw failure("A rejected credential must not be silently cleared by background refresh") }
        editing.save("s2t"); try await waitForCheck(state)
        _ = state.recordKeyFailure(CreditAccountError("S2T credits exhausted"), using: key("a"))
        await state.refreshCredits()
        guard editing.message("s2t").contains("exhausted"), state.creditBalance == nil else { throw failure("Background balance refresh erased an account failure") }
        editing.save("s2t"); try await waitForCheck(state)
        state.phase = .recording
        editing.change(key("b"), for: "s2t")
        editing.save("s2t")
        guard !editing.canSave("s2t"), state.creditConnection?.key == key("a") else { throw failure("A draft changed the saved S2T key during recording") }
        state.phase = .idle
        try choose("cleanup.provider", "openrouter")
        guard state.speechUsesCredits, !state.cleanupUsesCredits, state.processingModel == "personal/model",
              state.routerEndpoint == "personal/host", !state.canRecord else { throw failure("Returning to a personal provider lost its model or ignored its missing key: speechCredits=\(state.speechUsesCredits), cleanupCredits=\(state.cleanupUsesCredits), model=\(state.processingModel), host=\(state.routerEndpoint), canRecord=\(state.canRecord)") }
        state.routerKey = "personal-cleanup-fixture"
        state.assemblyKey = "personal-speech-fixture"
        let audio = WaveAudio.encode(samples: Array(repeating: 0, count: 1600), sampleRate: 16000)
        await transport.reset()
        state.processRecording(audio)
        try await waitForDelivery(state)
        let assemblyRequests = await transport.requests.filter { $0.url?.path == "/api/v1/requests" }
        guard let speechRequest = assemblyRequests.first,
              let body = try JSONSerialization.jsonObject(with: speechRequest.httpBody!) as? [String: String],
              body["provider"] == "assemblyai", body["model"] == "universal-3-5-pro",
              body["audio"] == audio.base64EncodedString(), state.output == "Personal cleanup" else {
            throw failure("AssemblyAI file transcription failed without a streaming capability")
        }
        state.cancel()
        state.creditSpeechProvider = .openRouter
        state.creditSpeechModel = "nvidia/parakeet-tdt-0.6b-v3"
        for (speech, cleanup) in [(true, false), (false, true), (true, true), (false, false)] {
            state.speechUsesCredits = speech; state.cleanupUsesCredits = cleanup
            await transport.reset()
            state.processRecording(audio)
            try await waitForDelivery(state)
            guard state.output == (cleanup ? "Credit cleanup" : "Personal cleanup") else { throw failure("Mixed providers delivered the wrong result") }
            let requests = await transport.requests
            let paid = requests.filter { $0.url?.path == "/api/v1/requests" }
            let operations = try paid.map { try JSONDecoder().decode([String: String].self, from: $0.httpBody!)["operation"]! }
            let expected = (speech ? ["transcription"] : []) + (cleanup ? ["cleanup"] : [])
            for request in paid {
                let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
                if body["operation"] == "cleanup" {
                    guard body["model"] == "openai/gpt-oss-20b", body["host"] == "", body["reasoning"] == "low", body["fast"] == "true" else { throw failure("S2T ignored the selected model or request options") }
                }
            }
            guard operations == expected else { throw failure("A task spent credits with a personal provider selected") }
            for request in requests {
                let auth = request.value(forHTTPHeaderField: "Authorization")
                if request.url?.host == "localhost" {
                    guard auth == "Bearer " + key("a") else { throw failure("Personal key leaked to the credits service") }
                } else {
                    guard auth == (request.url?.host == "sync.assemblyai.com" ? "personal-speech-fixture" : "Bearer personal-cleanup-fixture") else { throw failure("S2T key leaked to a direct provider") }
                }
            }
            guard requests.contains(where: { $0.url?.host == "sync.assemblyai.com" }) == !speech,
                  requests.contains(where: { $0.url?.host == "openrouter.ai" }) == !cleanup else { throw failure("A selected personal provider was skipped") }
        }
        state.speechUsesCredits = true; state.cleanupUsesCredits = false
        pane.rebuild()
        try choose("speech.provider", "s2t")
        try choose("speech.model", "nvidia/parakeet-tdt-0.6b-v3")
        guard (pane.controls["speech.model"] as? NSTextField)?.stringValue == "nvidia/parakeet-tdt-0.6b-v3" else {
            throw failure("S2T speech picker and Model ID disagree")
        }
        try choose("speech.model", "openai/whisper-large-v3-turbo")
        guard state.creditSpeechModel == "openai/whisper-large-v3-turbo" else { throw failure("Whisper model edit failed") }
        try choose("speech.model", "nvidia/parakeet-tdt-0.6b-v3")
        guard let speechField = pane.controls["speech.model"] as? NSTextField,
              state.creditSpeechModel == speechField.stringValue, speechField.toolTip == nil,
              AppState(preview: true).creditSpeechModel == speechField.stringValue else { throw failure("Parakeet Model ID edit was rejected or not saved") }
        try choose("speech.model", "microsoft/mai-transcribe-2")
        guard state.creditSpeechModel == "microsoft/mai-transcribe-2",
              ModelChoiceProbe.item("microsoft/mai-transcribe-2", in: (pane.controls["speech.choice"] as? NSPopUpButton)?.menu) != nil else {
            throw failure("S2T must accept MAI from the service catalog and list it as a recommended choice")
        }
        await transport.reset()
        state.processRecording(audio)
        try await waitForDelivery(state)
        let speechRequests = await transport.requests
        guard let speechRequest = speechRequests.first(where: { $0.url?.path == "/api/v1/requests" }),
              let speechBody = try JSONSerialization.jsonObject(with: speechRequest.httpBody!) as? [String: String],
              speechBody["provider"] == "openrouter", speechBody["model"] == "microsoft/mai-transcribe-2",
              AppState(preview: true).creditSpeechProvider == .openRouter else { throw failure("S2T ignored the selected OpenRouter speech model") }
        state.speechUsesCredits = false; state.cleanupUsesCredits = true
        await transport.setCleanupTruncated(true)
        state.processRecording(audio)
        try await waitForDelivery(state)
        guard state.output == "Original words", state.errorMessage?.contains("incomplete") == true,
              state.routeDescription == "Original transcription" else { throw failure("A truncated S2T cleanup must deliver the original words") }
        await transport.setCleanupTruncated(false)
        await transport.setCleanupFailure(true)
        state.processRecording(audio)
        try await waitForDelivery(state)
        guard state.output == "Original words", state.keyStatuses["s2t"]?.needsAttention == true,
              state.routeDescription == "Original transcription" else { throw failure("Credit failure must preserve successful transcription and appear under the S2T key") }
        state.cancel()
        let personalKey = state.routerKey
        editing.beginEditing("s2t")
        editing.change(" \n ", for: "s2t")
        editing.endEditing()
        guard state.creditConnection == nil, state.creditsKey.isEmpty, state.creditBalance == nil,
              !editing.saved("s2t"), editing.status("s2t") == nil, state.routerKey == personalKey else {
            throw failure("Clearing the S2T field must disconnect credits without changing personal provider keys")
        }
        try await RecordingRecoveryProbe.run()
        print("PASS: shared S2T provider/model controls and key-linked balance, a single S2T key, draft/Save behavior, read-only checks, stale results, per-task persistence and legacy migration, all four mixed billing routes, credential isolation and original-text delivery after credit failure. Mock transport and synthetic audio only.")
    }

    private static func waitForCheck(_ state: AppState) async throws {
        for _ in 0..<100 {
            if state.keyStatuses["s2t"] != .checking { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw failure("S2T key check did not finish")
    }

    private static func waitForDelivery(_ state: AppState) async throws {
        for _ in 0..<200 {
            if state.phase == .complete { return }
            if state.phase == .failed { throw failure(state.errorMessage ?? "Dictation failed") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw failure("Synthetic dictation did not finish")
    }
    static func runHTTP() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["S2T_CREDITS_FIXTURE_ORIGIN"],
              let key = env["S2T_CREDITS_FIXTURE_KEY"], key.hasPrefix("s2t_demo_"),
              URL(string: address)?.host == "127.0.0.1" else { throw failure("Only isolated loopback demo fixtures are permitted") }
        let connection = try CreditConnection(address: address, key: key)
        let api = CreditsAPI()
        let before = try await api.balance(connection)
        guard before.mode == "demo" else { throw failure("Fixture must be demo mode") }
        let result = try await api.process(text: "Can you fix this?", mode: .clean, model: "openai/gpt-oss-120b", endpoint: "cerebras/fp16", connection: connection, clipboardContext: ClipboardContext(), instructions: nil)
        let after = try await api.balance(connection)
        guard result.text == "Can you fix this?", abs(before.available - after.available - 0.01) < 0.000001, after.reserved == 0 else { throw failure("Native client and server ledger disagree") }
        print("PASS: packaged native HTTP client, S2T key authentication, editing contract, exact metering, and settled result. Isolated synthetic service only.")
    }
    private static func failure(_ text: String) -> NSError { NSError(domain: "CreditsProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}

private actor CreditSettingsTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var cleanupFailure = false
    var cleanupTruncated = false
    private var balanceFailure: Int?
    func failNextBalance(_ status: Int) { balanceFailure = status }
    func setCleanupTruncated(_ value: Bool) { cleanupTruncated = value }
    func reset() { requests = [] }
    func setCleanupFailure(_ value: Bool) { cleanupFailure = value }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
        var status = 200
        let response: String
        if request.url?.path == "/api/v1/balance" {
            if let failure = balanceFailure {
                balanceFailure = nil
                if failure == -1 { throw URLError(.notConnectedToInternet) }
                return (Data(#"{"error":"Synthetic balance failure"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: failure, httpVersion: nil, headerFields: nil)!)
            }
            if key.hasSuffix(String(repeating: "c", count: 64)) { try? await Task.sleep(nanoseconds: 150_000_000) }
            if key.hasSuffix(String(repeating: "b", count: 64)) || key.hasSuffix(String(repeating: "c", count: 64)) {
                status = 401; response = #"{"error":"Key rejected"}"#
            } else { response = #"{"available":10,"reserved":0,"frozen":false,"paused":false,"mode":"demo","openRouterCatalog":true,"models":[{"provider":"openrouter","operation":"transcription","model":"microsoft/mai-transcribe-2","host":"","title":"MAI-Transcribe 2","maxSeconds":120},{"provider":"openrouter","operation":"transcription","model":"nvidia/parakeet-tdt-0.6b-v3","host":"","title":"Parakeet TDT 0.6B v3","maxSeconds":120},{"provider":"openrouter","operation":"transcription","model":"openai/whisper-large-v3-turbo","host":"","title":"Whisper V3 Turbo","maxSeconds":120},{"provider":"openrouter","operation":"cleanup","model":"meta/muse-spark-1.3-contributor","host":"","title":"Muse Spark Contributor"},{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-120b","host":"cerebras/fp16","title":"GPT-OSS 120B"},{"provider":"openrouter","operation":"cleanup","model":"openai/gpt-oss-20b","host":"","title":"GPT-OSS 20B"}]}"# }
        } else if request.url?.path == "/api/v1/requests" {
            let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
            if body["operation"] == "cleanup", cleanupFailure { status = 402; response = #"{"error":"No credits available"}"# }
            else if body["operation"] == "cleanup", cleanupTruncated { response = #"{"state":"settled","error":"The cleanup model returned incomplete output. Your original transcription is preserved."}"# }
            else if body["operation"] == "cleanup" { response = #"{"state":"settled","result":{"text":"Credit cleanup","model":"openai/gpt-oss-120b","host":"Cerebras"}}"# }
            else { response = #"{"state":"settled","result":{"text":"Original words","model":"universal-3-5-pro"}}"# }
        } else if request.url?.host == "openrouter.ai", request.httpMethod == "GET" {
            response = #"{"data":{"architecture":{"input_modalities":["text","image"],"output_modalities":["text"]}}}"#
        } else if request.url?.host == "sync.assemblyai.com" { response = #"{"text":"Original words"}"# }
        else if request.url?.host == "openrouter.ai" { response = #"{"model":"personal/model","choices":[{"finish_reason":"stop","message":{"content":"Personal cleanup"}}]}"# }
        else { throw URLError(.unsupportedURL) }
        return (Data(response.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
