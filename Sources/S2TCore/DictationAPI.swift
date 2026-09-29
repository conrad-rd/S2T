import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct SessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: TypeSafeRedirectPolicy(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

private final class TypeSafeRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        let isJev = original?.host == "api.typesafe.ai" || (original?.host == "openrouter.ai" && original?.path == "/api/alpha/decisions")
        completionHandler(isJev || original?.host == "artificialanalysis.ai" ? nil : request)
    }
}

public struct DictationAPI: Sendable {
    private let transport: any HTTPTransport
    private let codex: any CodexServing
    private let pollInterval: UInt64
    private let maxPolls: Int
    public init(transport: any HTTPTransport = SessionTransport(), pollInterval: UInt64 = 1_500_000_000, maxPolls: Int = 200, codex: any CodexServing = CodexCLI()) {
        self.codex = codex
        self.transport = transport
        self.pollInterval = pollInterval
        self.maxPolls = maxPolls
    }

    public func validateKey(_ key: String, account: APIAccount) async throws {
        if account == .artificialAnalysis {
            do { try await ArtificialAnalysisClient(transport: transport).validateKey(key) }
            catch ArtificialAnalysisError.http(let status) where [401, 402, 403].contains(status) {
                throw ServiceError.account(account, status: status)
            }
            return
        }
        var request = URLRequest(url: account.validationURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue(account == .assemblyAI ? key : "Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let _: KeyValidationResponse = try await send(request, provider: account.title)
    }

    public func cleanWithJev(_ plan: JevCleanupPlan, apiKey: String, route: JevRoute = .typeSafe) async throws -> JevCleanupResult {
        guard route != .s2t else { throw ServiceError.message("Use the S2T credit service for this Jev connection.") }
        try Task.checkCancellation()
        guard !plan.candidates.isEmpty || plan.allowFastPath else {
            return JevCleanupResult(text: plan.text, canSkipRewrite: false, model: route.model, editCount: 0)
        }
        return try plan.finish(await jevDecisions(body: plan.requestBody(model: route.model), apiKey: apiKey, route: route))
    }

    func jevDecisions(body: Data, apiKey: String, route: JevRoute) async throws -> JevCleanupResponse {
        guard route != .s2t else { throw ServiceError.message("Use the S2T credit service for Jev decisions.") }
        try Task.checkCancellation()
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.message("Add a \(route.account.title) API key in Settings → API keys to use Jev cleanup.")
        }
        var request = URLRequest(url: route.url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        guard request.httpBody!.count <= 65_536 else {
            throw ServiceError.message("This transcript has too many Jev decisions. Normal cleanup will be used.")
        }
        let preparedRequest = request
        let response = try await withThrowingTaskGroup(of: JevCleanupResponse.self) { group in
            group.addTask { try await send(preparedRequest, provider: route.account.title, maxBytes: 65_536) }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        try Task.checkCancellation()
        return response
    }

    public func transcribe(audio: Data, apiKey: String, mode: TranscriptionMode = .fast, provider: TranscriptionProvider = .assemblyAI, model: String? = nil, localURL: String? = nil) async throws -> String {
        try await transcribeDetailed(audio: audio, apiKey: apiKey, mode: mode, provider: provider, model: model, localURL: localURL).text
    }

    public func transcribeDetailed(audio: Data, apiKey: String, mode: TranscriptionMode = .fast, provider: TranscriptionProvider = .assemblyAI, model: String? = nil, localURL: String? = nil, includeTimestamps: Bool = false) async throws -> TimedTranscription {
        if provider != .assemblyAI {
            return try await transcribeWithProvider(audio: audio, apiKey: apiKey, provider: provider, model: model ?? provider.defaultModel, localURL: localURL, includeTimestamps: includeTimestamps)
        }
        if mode == .fast && WaveAudio.supportsImmediateTranscription(audio) {
            return try await transcribeImmediatelyDetailed(audio: audio, apiKey: apiKey, includeTimestamps: includeTimestamps)
        }
        return try await transcribeBatch(audio: audio, apiKey: apiKey)
    }

    private func transcribeBatch(audio: Data, apiKey: String) async throws -> TimedTranscription {
        var upload = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/upload")!)
        upload.httpMethod = "POST"
        upload.setValue(apiKey, forHTTPHeaderField: "Authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.httpBody = audio
        let uploaded: Upload = try await send(upload, provider: "AssemblyAI")
        let submit = try request(url: "https://api.assemblyai.com/v2/transcript", key: apiKey, body: [
            "audio_url": uploaded.upload_url,
            "speech_models": ["universal-3-5-pro", "universal-2"],
            "language_detection": true,
            "punctuate": true,
            "format_text": true
        ])
        let job: Transcript = try await send(submit, provider: "AssemblyAI")
        guard let id = job.id, id.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw ServiceError.message("AssemblyAI did not return a valid transcript ID. Try again.")
        }
        if job.status == "error" { throw ServiceError.message("AssemblyAI could not transcribe this recording. Check the audio and try again.") }
        if job.status == "completed" {
            let text = job.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Check your microphone and try speaking a little louder.") }
            return TimedTranscription(text: text, words: timedWords(job.words, scale: 0.001))
        }
        for index in 0..<maxPolls {
            try Task.checkCancellation()
            if index > 0 && pollInterval > 0 { try await Task.sleep(nanoseconds: pollInterval) }
            var poll = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/transcript/\(id)")!)
            poll.setValue(apiKey, forHTTPHeaderField: "Authorization")
            let result: Transcript = try await send(poll, provider: "AssemblyAI")
            switch result.status {
            case "completed":
                let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Check your microphone and try speaking a little louder.") }
                return TimedTranscription(text: text, words: timedWords(result.words, scale: 0.001))
            case "error": throw ServiceError.message("AssemblyAI could not transcribe this recording. Check the audio and try again.")
            case "queued", "processing": continue
            default: throw ServiceError.message("AssemblyAI returned an unexpected transcript status. Try again.")
            }
        }
        throw ServiceError.message("Transcription is taking longer than expected. Your recording is still available to retry.")
    }

    private func transcribeWithProvider(audio: Data, apiKey: String, provider: TranscriptionProvider, model: String, localURL: String?, includeTimestamps: Bool) async throws -> TimedTranscription {
        guard provider.validModelID(model) else { throw ServiceError.message("Enter a valid \(provider.title) speech-to-text model ID.") }
        var req: URLRequest
        if provider == .openRouter {
            req = try request(url: "https://openrouter.ai/api/v1/audio/transcriptions", key: "Bearer \(apiKey)", body: [
                "model": model,
                "input_audio": ["data": audio.base64EncodedString(), "format": "wav"]
            ])
        } else {
            let boundary = "S2T-" + UUID().uuidString
            if provider == .xai && audio.count > 500_000_000 { throw ServiceError.message("xAI accepts recordings up to 500 MB. Save and shorten this recording, then retry.") }
            req = URLRequest(url: provider == .xai ? URL(string: "https://api.x.ai/v1/stt")! : try LocalEndpoint.url(localURL ?? ""))
            if provider == .xai { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            req.httpMethod = "POST"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            let fields = provider == .xai ? [("model", model)] : [("model", model), ("response_format", "json")]
            for (name, value) in fields {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
            body.append(audio)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            req.httpBody = body
        }
        req.timeoutInterval = 180
        let result: ImmediateTranscript = try await send(req, provider: provider.title)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Check your microphone and try again.") }
        return TimedTranscription(text: text, words: timedWords(result.words, scale: 1))
    }

    public func transcribeImmediately(audio: Data, apiKey: String) async throws -> String {
        try await transcribeImmediatelyDetailed(audio: audio, apiKey: apiKey, includeTimestamps: false).text
    }

    private func transcribeImmediatelyDetailed(audio: Data, apiKey: String, includeTimestamps: Bool) async throws -> TimedTranscription {
        let boundary = "S2T-" + UUID().uuidString
        var req = URLRequest(url: URL(string: "https://sync.assemblyai.com/v1/transcribe")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(apiKey, forHTTPHeaderField: "Authorization")
        req.setValue("universal-3-5-pro", forHTTPHeaderField: "X-AAI-Model")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body.append(audio)
        if includeTimestamps {
            body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"config\"\r\nContent-Type: application/json\r\n\r\n{\"timestamps\":true}".utf8))
        }
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body
        let result: ImmediateTranscript
        do { result = try await send(req, provider: "AssemblyAI") }
        catch is MissingAssemblySyncRoute {
            try Task.checkCancellation()
            return try await transcribeBatch(audio: audio, apiKey: apiKey)
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Check your microphone and try again.") }
        return TimedTranscription(text: text, words: timedWords(result.words, scale: 0.001))
    }

    public func warmTranscriptionConnection() async {
        var req = URLRequest(url: URL(string: "https://sync.assemblyai.com/warm")!, timeoutInterval: 5)
        req.setValue("universal-3-5-pro", forHTTPHeaderField: "X-AAI-Model")
        _ = try? await transport.data(for: req)
    }

    public func process(text: String, mode: WritingMode, model: String, apiKey: String, provider: ProcessingProvider = .openRouter, endpoint: String? = nil, clipboardContext: ClipboardContext = ClipboardContext(), instructions: String? = nil, localURL: String? = nil, codexExecutable: String = "", codexOptions: CodexOptions = CodexOptions(), routerOptions: OpenRouterOptions = OpenRouterOptions()) async throws -> ProcessedText {
        guard provider.validModelID(model) else { throw ServiceError.message("Enter a \(provider.title) model ID such as \(provider.defaultModel).") }
        let editing = try DictationEditingRequest(text: text, mode: mode, instructions: instructions, clipboardContext: clipboardContext)
        if provider == .codex {
            let output = try await codex.complete(instructions: editing.instructions, prompt: editing.source, model: model, executable: codexExecutable, options: codexOptions)
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.message("Codex returned an empty result.") }
            return ProcessedText(text: clipboardContext.resolve(try editing.finish(output)), model: model == "default" ? "Codex default" : model, host: "Codex CLI")
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": editing.instructions], ["role": "user", "content": editing.source]],
            "stream": false
        ]
        if provider == .openRouter { try routerOptions.validateConsent(model: model); routerOptions.apply(to: &body, endpoint: endpoint) }
        var req = try request(url: provider == .local ? LocalEndpoint.url(localURL ?? "").absoluteString : provider.completionURL, key: "Bearer \(apiKey)", body: body)
        if provider == .local { req.setValue(nil, forHTTPHeaderField: "Authorization") }
        let result: Completion = try await send(req, provider: provider.title)
        guard let choice = result.choices.first,
              choice.finish_reason == "stop",
              let output = choice.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            throw ServiceError.message("\(provider.title) returned an empty or incomplete result. Your original transcript is preserved. Try processing it again.")
        }
        return ProcessedText(text: clipboardContext.resolve(try editing.finish(output)), model: result.model ?? model, host: result.provider ?? (provider == .xai ? "xAI" : provider == .local ? req.url?.host : nil))
    }

    public func processMeeting(_ utterances: [MeetingUtterance], settings: MeetingProcessingSettings, apiKey: String,
                               codexExecutable: String = "", codexOptions: CodexOptions = .init()) async throws -> (utterances: [MeetingUtterance], model: String, host: String?) {
        let provider = settings.selectedProvider
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.validModelID(model) else { throw ServiceError.message("Choose a valid meeting processing model.") }
        let input = try MeetingProcessing.input(utterances)
        let output: String
        let actualModel: String
        let host: String?
        if provider == .codex {
            output = try await codex.complete(instructions: MeetingProcessing.instructions, prompt: input, model: model, executable: codexExecutable, options: codexOptions)
            actualModel = model; host = "Codex CLI"
        } else {
            guard !provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.message("Add your \(provider.title) key under API keys for meeting processing. The original transcript is preserved.")
            }
            var body: [String: Any] = ["model": model, "stream": false,
                "messages": [["role": "system", "content": MeetingProcessing.instructions], ["role": "user", "content": input]]]
            if provider == .openRouter {
                try settings.router.validateConsent(model: model)
                settings.router.apply(to: &body, endpoint: settings.host)
            }
            var req = try request(url: provider == .local ? LocalEndpoint.url(settings.localURL).absoluteString : provider.completionURL, key: "Bearer \(apiKey)", body: body)
            if provider == .local { req.setValue(nil, forHTTPHeaderField: "Authorization") }
            let result: Completion = try await send(req, provider: provider.title)
            guard let choice = result.choices.first, choice.finish_reason == "stop", let content = choice.message.content else {
                throw ServiceError.message("Meeting processing returned an incomplete result. The original transcript is preserved.")
            }
            output = content; actualModel = result.model ?? model
            host = result.provider ?? (provider == .local ? req.url?.host : provider == .xai ? "xAI" : nil)
        }
        try Task.checkCancellation()
        return (try MeetingProcessing.apply(output, to: utterances), actualModel, host)
    }

    public func improveWritingDocument(_ text: String, kind: WritingDocumentKind, instruction: String,
                                       model: String, apiKey: String, provider: ProcessingProvider = .openRouter,
                                       endpoint: String? = nil, codexExecutable: String = "",
                                       codexOptions: CodexOptions = .init(), routerOptions: OpenRouterOptions = .init(), localURL: String? = nil) async throws -> String {
        guard provider.validModelID(model) else {
            throw ServiceError.message("Choose a valid \(provider.title) model for AI writing.")
        }
        let editing = try WritingDocumentRequest(text: text, kind: kind, instruction: instruction)
        let instructions = editing.instructions, prompt = editing.prompt
        let output: String
        if provider == .codex {
            output = try await codex.complete(instructions: instructions, prompt: prompt, model: model, executable: codexExecutable, options: codexOptions)
        } else {
            guard provider == .local || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.message("Add your \(provider.title) key in API keys to use AI writing.")
            }
            var body: [String: Any] = ["model": model, "stream": false,
                "messages": [["role": "system", "content": instructions], ["role": "user", "content": prompt]]]
            if provider == .openRouter {
                try routerOptions.validateConsent(model: model)
                routerOptions.apply(to: &body, endpoint: endpoint)
            }
            var req = try request(url: provider == .local ? LocalEndpoint.url(localURL ?? "").absoluteString : provider.completionURL, key: "Bearer \(apiKey)", body: body)
            if provider == .local { req.setValue(nil, forHTTPHeaderField: "Authorization") }
            let response: Completion = try await send(req, provider: provider.title)
            guard let choice = response.choices.first, choice.finish_reason == "stop", let content = choice.message.content else {
                throw ServiceError.message("The model returned an incomplete suggestion. Your document is unchanged.")
            }
            output = content
        }
        try Task.checkCancellation()
        return try editing.finish(output)
    }

    private func request(url: String, key: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, provider: String, maxBytes: Int = 8_000_000) async throws -> T {
        try Task.checkCancellation()
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 403, provider == APIAccount.openRouter.title,
           data.count <= maxBytes,
           let failure = try? JSONDecoder().decode(OpenRouterAccessFailure.self, from: data),
           let requirements = failure.error.metadata?.missing_attestation_types, !requirements.isEmpty {
            let requirement = requirements.contains("age_18plus") ? "18+ age confirmation" : "account confirmation"
            let setting = request.url?.path == "/api/v1/audio/transcriptions"
                ? "API keys → Speech to text → Speech-to-text model"
                : "Models → Selected model"
            throw ServiceError.message("This OpenRouter model requires \(requirement). Choose another model under \(setting), or complete the confirmation at https://openrouter.ai/settings/preferences. This is a model access requirement, not an invalid API key.")
        }
        if [401, 402, 403].contains(response.statusCode),
           let account = APIAccount.allCases.first(where: { $0.title == provider }) {
            throw ServiceError.account(account, status: response.statusCode)
        }
        if response.statusCode == 404 && request.url?.host == "sync.assemblyai.com" && request.url?.path == "/v1/transcribe" {
            throw MissingAssemblySyncRoute()
        }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw ServiceError.message("\(provider) rejected the API key. Check its access settings.")
        case 402: throw ServiceError.message("\(provider) needs more credit. Check your account balance.")
        case 429: throw ServiceError.message("\(provider) is rate limiting requests. Wait a moment and try again.")
        default: throw ServiceError.message("\(provider) returned an error, HTTP \(response.statusCode). Try again shortly.")
        }
        guard data.count <= maxBytes else { throw ServiceError.message("\(provider) returned a response that is too large.") }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ServiceError.message("\(provider) returned an unreadable response. Check the service or feed URL.") }
    }
}

private struct MissingAssemblySyncRoute: Error {}

private struct Upload: Decodable { let upload_url: String }
private struct Transcript: Decodable { let id: String?; let status: String; let text: String?; let words: [ProviderWord]? }
private struct Completion: Decodable {
    let model: String?
    let provider: String?
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        let finish_reason: String?
    }
    struct Message: Decodable { let content: String? }
}

private struct ImmediateTranscript: Decodable { let text: String; let words: [ProviderWord]? }

private struct ProviderWord: Decodable {
    let text: String
    let start: Double?
    let end: Double?
    private enum CodingKeys: String, CodingKey { case text, word, start, end }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = (try? values.decode(String.self, forKey: .text)) ?? (try? values.decode(String.self, forKey: .word)) ?? ""
        start = try? values.decode(Double.self, forKey: .start)
        end = try? values.decode(Double.self, forKey: .end)
    }
}

private func timedWords(_ words: [ProviderWord]?, scale: Double) -> [TimedWord] {
    (words ?? []).compactMap { word in
        guard !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let start = word.start, let end = word.end, start.isFinite, end.isFinite, start >= 0, end >= start else { return nil }
        return TimedWord(text: word.text, start: start * scale, end: end * scale)
    }
}

private struct KeyValidationResponse: Decodable {}



private struct OpenRouterAccessFailure: Decodable {
    let error: Detail
    struct Detail: Decodable {
        let metadata: Metadata?
    }
    struct Metadata: Decodable {
        let missing_attestation_types: [String]?
    }
}
