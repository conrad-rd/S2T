import Foundation
import CryptoKit

public enum CreditService {
    public static func url(_ address: String) throws -> URL {
        guard let url = URL(string: address), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw ServiceError.message("A hosted HTTPS credits service is required. Local HTTP is allowed only for development.")
        }
        return url
    }
}

public struct CreditSignIn: Decodable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Int
}
public struct CreditSignInResult: Decodable, Sendable {
    public let state: String
    public let key: String?
}

public struct CreditConnection: Codable, Equatable, Sendable {
    public let origin: URL
    public let key: String

    public init(address: String, key: String) throws {
        guard let url = URL(string: address), let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw ServiceError.message("Enter the S2T service address without a path, query, or password.")
        }
        let local = ["localhost", "127.0.0.1", "[::1]"].contains(host)
        guard url.scheme == "https" || (local && url.scheme == "http") else {
            throw ServiceError.message("S2T credits require HTTPS. HTTP is allowed only for a local preview.")
        }
        guard key.range(of: #"^s2t_(live|test|demo)_[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              !key.hasPrefix("s2t_demo_") || local,
              !key.hasPrefix("s2t_live_") || url.scheme == "https" else {
            throw ServiceError.message("Enter an S2T key from the credits page. Provider API keys cannot be used here.")
        }
        self.origin = url
        self.key = key
    }
}

public struct CreditModel: Codable, Equatable, Sendable {
    public let provider: String
    public let operation: String
    public let model: String
    public let host: String
    public let title: String
    public let maxSeconds: Int?
    public var id: String { provider + ":" + operation + ":" + model + ":" + host }
    public static let suggestions: [CreditModel] = [
        defaults[0],
        CreditModel(provider: "openrouter", operation: "cleanup", model: OpenRouterOptions.contributorModel, host: "", title: "Muse Spark Contributor", maxSeconds: nil),
        CreditModel(provider: "openrouter", operation: "cleanup", model: "openai/gpt-oss-20b", host: "", title: "GPT-OSS 20B", maxSeconds: nil),
        CreditModel(provider: "openrouter", operation: "cleanup", model: "anthropic/claude-fable-5", host: "", title: "Claude Fable 5", maxSeconds: nil)
    ]
    public static let defaults: [CreditModel] = [
        CreditModel(provider: "openrouter", operation: "cleanup", model: "openai/gpt-oss-120b", host: "cerebras/fp16", title: "GPT-OSS 120B", maxSeconds: nil),
        CreditModel(provider: "assemblyai", operation: "transcription", model: "universal-3-5-pro", host: "", title: "Universal 3.5 Pro", maxSeconds: 120)
    ]
}

public struct CreditKeyLimit: Decodable, Sendable {
    public let limitCredits: Double?
    public let remainingCredits: Double?
    public let resetDays: Int?
    public let resetsAt: Double?
    public let expiresAt: Double?
}

public struct CreditStreamingCapability: Decodable, Sendable {
    public let model: String
    public let maxSeconds: Int
    public let billing: String
}

public struct CreditStreamingReceipt: Codable, Sendable {
    public let authorizationID: String
    public let sessionID: String
    public let sessionDurationSeconds: Double
    public let audioDurationSeconds: Double
    public init(authorizationID: String, sessionID: String, sessionDurationSeconds: Double, audioDurationSeconds: Double) {
        self.authorizationID = authorizationID; self.sessionID = sessionID
        self.sessionDurationSeconds = sessionDurationSeconds; self.audioDurationSeconds = audioDurationSeconds
    }
}

public struct CreditBalance: Decodable, Sendable {
    public let openRouterCatalog: Bool?
    public let available: Double
    public let reserved: Double
    public let frozen: Bool
    public let paused: Bool
    public let mode: String
    public let realProviders: Bool?
    public let models: [CreditModel]?
    public let keyLimit: CreditKeyLimit?
    public let assemblyStreaming: CreditStreamingCapability?
}

public struct CreditAccountError: LocalizedError, Sendable {
    public let message: String
    public let automaticallyRefreshable: Bool
    public let code: String?
    public init(_ message: String, automaticallyRefreshable: Bool = false, code: String? = nil) { self.message = message; self.automaticallyRefreshable = automaticallyRefreshable; self.code = code }
    public var errorDescription: String? { message }
}

public struct CreditRequestRejected: LocalizedError, Sendable {
    public let message: String
    public let requestID: String?
    public init(message: String, requestID: String? = nil) { self.message = message; self.requestID = requestID }
    public var errorDescription: String? { message }
}

public struct CreditDevice: Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = ["Mac", "MacBook Air", "MacBook Pro", "Mac mini", "Mac Studio", "Mac Pro", "iMac"].contains(name) ? name : "Mac"
    }
}

/// Duration-only breakdown of the latest credit request per operation, from the service's Server-Timing header.
/// `network` is the client round trip minus the time the service reported, so it covers upload, download and connection setup.
public final class CreditRequestTimings: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: [String: [String: Double]] = [:]
    public init() {}

    func record(_ operation: String, serverTiming: String?, roundTrip: TimeInterval) {
        var values: [String: Double] = [:]
        for entry in (serverTiming ?? "").split(separator: ",") {
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, !name.isEmpty, name.count <= 32,
                  let duration = parts.dropFirst().first(where: { $0.hasPrefix("dur=") }).flatMap({ Double($0.dropFirst(4)) }),
                  duration.isFinite, duration >= 0 else { continue }
            values[name] = duration / 1000
        }
        values["roundTrip"] = roundTrip
        if let edge = values["edge"] { values["network"] = max(0, roundTrip - edge) }
        lock.lock(); latest[operation] = values; lock.unlock()
    }

    public func take(_ operation: String) -> [String: Double]? {
        lock.lock(); defer { lock.unlock() }
        return latest.removeValue(forKey: operation)
    }
}

public struct CreditsAPI: Sendable {
    private let transport: any HTTPTransport
    private let device: CreditDevice?
    public let timings = CreditRequestTimings()
    public init(transport: any HTTPTransport = CreditTransport(), device: CreditDevice? = nil) {
        self.transport = transport
        self.device = device
    }

    public func startSignIn(address: String) async throws -> CreditSignIn {
        let origin = try CreditService.url(address)
        let result: CreditSignIn = try await deviceRequest(origin: origin, path: "api/device/start", body: [:])
        guard result.deviceCode.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              result.userCode.range(of: #"^[A-F0-9]{12}$"#, options: .regularExpression) != nil,
              (1...600).contains(result.expiresIn),
              result.verificationURL.scheme == origin.scheme, result.verificationURL.host == origin.host,
              result.verificationURL.port == origin.port, result.verificationURL.user == nil, result.verificationURL.password == nil,
              result.verificationURL.path == "/", result.verificationURL.fragment == nil,
              URLComponents(url: result.verificationURL, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "connect", value: result.userCode)] else {
            throw ServiceError.message("The credit service returned an invalid sign-in request.")
        }
        return result
    }
    public func pollSignIn(address: String, deviceCode: String) async throws -> CreditSignInResult {
        try await deviceRequest(origin: CreditService.url(address), path: "api/device/poll", body: ["deviceCode": deviceCode])
    }
    private func deviceRequest<T: Decodable>(origin: URL, path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: origin.appendingPathComponent(path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard data.count <= 16000 else { throw ServiceError.message("Sign-in response is too large.") }
        guard response.statusCode == 200 else {
            throw ServiceError.message((try? JSONDecoder().decode(CreditFailure.self, from: data).error) ?? "Could not connect to S2T credits.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    public func balance(_ connection: CreditConnection) async throws -> CreditBalance {
        try await send(connection, path: "api/v1/balance", body: nil)
    }

    public func warmConnection(_ connection: CreditConnection) async {
        struct WarmStatus: Decodable { let ready: Bool }
        let _: WarmStatus? = try? await send(connection, path: "api/v1/warm", body: nil, timeout: 5)
    }

    public func transcribe(audio: Data, provider: TranscriptionProvider, model: String, endpoint: String?, connection: CreditConnection, requestID: String = UUID().uuidString, completedParts: [String: String] = [:], segmentEnds: [Int]? = nil, onPartCompleted: @Sendable (String, String) async throws -> Void = { _, _ in }) async throws -> TimedTranscription {
        let request = try CreditSpeechRequest(provider: provider, model: model, connection: connection,
            requestID: requestID, segmented: segmentEnds != nil).appending(audio: audio, segmentEnds: segmentEnds, complete: true)
        return try await transcribe(request, connection: connection, completedParts: completedParts, onPartCompleted: onPartCompleted)
    }

    public func transcribe(_ request: CreditSpeechRequest, connection: CreditConnection, completedParts: [String: String] = [:],
                           onPartCompleted: @Sendable (String, String) async throws -> Void = { _, _ in }) async throws -> TimedTranscription {
        try request.validate(connection)
        var texts: [String] = []
        for part in request.parts {
            try Task.checkCancellation()
            if let completed = completedParts[part.cacheKey] { texts.append(completed); continue }
            let result = try await run(connection, requestID: part.requestID, body: part.body, allowEmpty: true)
            try await onPartCompleted(part.cacheKey, result.text)
            texts.append(result.text)
        }
        let text = texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        guard !text.isEmpty else { throw ServiceError.message("No speech was detected. Your recording is available to save or retry.") }
        return TimedTranscription(text: text)
    }

    public func cleanWithJev(_ plan: JevCleanupPlan, connection: CreditConnection, requestID: String) async throws -> JevCleanupResult {
        let data = try plan.requestBody(model: JevRoute.s2t.model)
        return try plan.finish(await jevDecisions(body: data, connection: connection, requestID: requestID))
    }

    func jevDecisions(body data: Data, connection: CreditConnection, requestID: String) async throws -> JevCleanupResponse {
        guard data.count <= 65_536 else { throw ServiceError.message("This transcript exceeds the Jev request limit.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let result = try await run(connection, requestID: requestID + "-jev-" + digest.prefix(24), body: [
            "provider": "openrouter", "operation": "decisions", "model": JevRoute.s2t.model,
            "text": String(decoding: data, as: UTF8.self)
        ])
        return try JSONDecoder().decode(JevCleanupResponse.self, from: Data(result.text.utf8))
    }

    public func process(text: String, mode: WritingMode, model: String, endpoint: String?, connection: CreditConnection, clipboardContext: ClipboardContext, instructions: String?, options: OpenRouterOptions = OpenRouterOptions(), requestID: String = UUID().uuidString, provider: ProcessingProvider = .openRouter) async throws -> ProcessedText {
        let request = try CreditCleanupRequest(text: text, mode: mode, model: model, endpoint: endpoint,
            connection: connection, clipboardContext: clipboardContext, instructions: instructions,
            options: options, requestID: requestID, provider: provider)
        return try await process(request, connection: connection)
    }

    public func process(_ request: CreditCleanupRequest, connection: CreditConnection) async throws -> ProcessedText {
        try request.validate(connection)
        let result = try await run(connection, requestID: request.requestID, body: request.body)
        return ProcessedText(text: try request.finish(result.text), model: result.model, host: result.host)
    }


    /// Uses the existing metered text route with the same contract as personal AI writing.
    public func improveWritingDocument(_ text: String, kind: WritingDocumentKind, instruction: String,
                                       model: String, endpoint: String?, options: OpenRouterOptions = .init(),
                                       provider: ProcessingProvider = .openRouter, connection: CreditConnection,
                                       requestID: String) async throws -> String {
        guard [.openRouter, .xai].contains(provider), provider.validModelID(model) else {
            throw ServiceError.message("Choose a text model available with S2T credits.")
        }
        let editing = try WritingDocumentRequest(text: text, kind: kind, instruction: instruction)
        guard editing.prompt.utf8.count <= 16_000 else {
            throw ServiceError.message("S2T credits allow 16 KB for the document and requested change together, including request formatting. Shorten the request or use your own provider. Your document is unchanged.")
        }
        var body = ["provider": provider.rawValue, "operation": "cleanup", "model": model,
                    "text": editing.prompt, "instructions": editing.instructions, "host": ""]
        if provider == .openRouter {
            try options.validateConsent(model: model)
            body["host"] = endpoint ?? ""
            body["reasoning"] = options.normalized(for: model).reasoning.rawValue
            body["fast"] = options.fast ? "true" : "false"
            body["allowDataCollection"] = options.allowDataCollection && model == OpenRouterOptions.contributorModel ? "true" : "false"
        }
        let result = try await run(connection, requestID: requestID, body: body, writingDocument: true)
        return try editing.finish(result.text)
    }

    private func run(_ connection: CreditConnection, requestID: String, body: [String: String], allowEmpty: Bool = false, writingDocument: Bool = false) async throws -> ResultText {
        var response: CreditRequest
        let operation = body["operation"] ?? "request"
        let started = ProcessInfo.processInfo.systemUptime
        let measure: (HTTPURLResponse) -> Void = { [timings] http in
            timings.record(operation, serverTiming: http.value(forHTTPHeaderField: "Server-Timing"),
                           roundTrip: ProcessInfo.processInfo.systemUptime - started)
        }
        do {
            response = try await send(connection, path: "api/v1/requests", body: body, requestID: requestID, onResponse: measure)
        } catch let error as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
            try Task.checkCancellation()
            response = try await send(connection, path: "api/v1/requests", body: body, requestID: requestID, onResponse: measure)
        }
        for _ in 0..<45 {
            guard ["reserved", "submitted"].contains(response.state), let id = response.id, UUID(uuidString: id) != nil else { break }
            try await Task.sleep(for: .seconds(2))
            response = try await send(connection, path: "api/v1/requests/" + id, body: nil)
        }
        if response.state == "released" || response.state == "settled" && response.error != nil {
            let recovery = writingDocument ? "Your document is unchanged."
                : body["operation"] == "cleanup" ? "Your original transcription is preserved."
                : body["operation"] == "decisions" ? "Normal cleanup can continue."
                : "Your recording is available to save or retry."
            let message = (response.error ?? "The provider rejected this request.")
            throw CreditRequestRejected(message: (writingDocument ? message.replacingOccurrences(of: "Your original transcription is preserved.", with: "") : message) + " " + recovery, requestID: requestID)
        }
        guard response.state == "settled", let result = response.result else {
            throw ServiceError.message("The credit service has not confirmed completion. Check Recent requests on your credits page before retrying. Any pending credits remain reserved.")
        }
        guard allowEmpty || !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.message(writingDocument ? "The model returned an empty suggestion. Your document is unchanged." : body["operation"] == "transcription"
                ? "No speech was detected. Try speaking again."
                : "Text cleanup returned no text. Your original words are preserved.")
        }
        return result
    }

    private func send<T: Decodable>(_ connection: CreditConnection, path: String, body: [String: String]?, requestID: String? = nil, timeout: TimeInterval = 180, onResponse: ((HTTPURLResponse) -> Void)? = nil) async throws -> T {
        var request = URLRequest(url: connection.origin.appendingPathComponent(path), timeoutInterval: timeout)
        request.setValue("Bearer \(connection.key)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            if path == "api/v1/requests", let device {
                request.setValue(device.id.uuidString.lowercased(), forHTTPHeaderField: "X-S2T-Device-Id")
                request.setValue(device.name, forHTTPHeaderField: "X-S2T-Device-Name")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            request.httpBody = try encoder.encode(body)
        }
        try Task.checkCancellation()
        let (data, response) = try await transport.data(for: request)
        onResponse?(response)
        try Task.checkCancellation()
        guard data.count <= 1_000_000 else { throw ServiceError.message("The credits response is too large.") }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(CreditFailure.self, from: data)
            let message = failure.map { "S2T credits: \($0.error)" } ?? "S2T credits returned HTTP \(response.statusCode)."
            if [401, 402, 403, 423].contains(response.statusCode) { throw CreditAccountError(message, automaticallyRefreshable: ["key_limit", "insufficient_credits", "paused", "frozen"].contains(failure?.code ?? ""), code: failure?.code) }
            throw ServiceError.message(message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct CreditFailure: Decodable { let error: String; let code: String? }
private struct CreditRequest: Decodable { let id: String?; let state: String; let result: ResultText?; let error: String? }
private struct ResultText: Decodable { let text: String; let model: String; let host: String? }

public final class CreditTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession
    private let redirectGuard = CreditRedirectGuard()
    public override init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 200
        session = URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
        super.init()
    }
    deinit { session.invalidateAndCancel() }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
private final class CreditRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
