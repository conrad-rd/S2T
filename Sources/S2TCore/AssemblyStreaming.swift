import Foundation

public protocol AssemblyStreamingSocket: Sendable {
    func connect(_ request: URLRequest) async throws
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func close() async
}

private final class AssemblyStreamingRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public actor URLSessionAssemblyStreamingSocket: AssemblyStreamingSocket {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    public init() {}
    public func connect(_ request: URLRequest) async throws {
        guard task == nil else { throw AssemblyStreamingError.invalidState }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: AssemblyStreamingRedirectGuard(), delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 1_048_576
        self.task = task
        task.resume()
    }
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        guard let task else { throw AssemblyStreamingError.disconnected }
        try await task.send(message)
    }
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        guard let task else { throw AssemblyStreamingError.disconnected }
        return try await task.receive()
    }
    public func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }
}

public enum AssemblyStreamingError: Error, LocalizedError, Equatable {
    case invalidState, invalidConfiguration, invalidAudio, disconnected, timedOut, malformedResponse, emptyTranscript, sessionLimit
    public var errorDescription: String? {
        switch self {
        case .invalidState: return "The transcription session is no longer accepting audio."
        case .invalidConfiguration: return "The streaming transcription settings are invalid."
        case .invalidAudio: return "Streaming requires mono 16-bit PCM audio."
        case .disconnected: return "AssemblyAI disconnected. Your local recording can be retried."
        case .timedOut: return "AssemblyAI did not respond in time. Your local recording can be retried."
        case .malformedResponse: return "AssemblyAI returned an invalid streaming response."
        case .emptyTranscript: return "AssemblyAI returned no speech."
        case .sessionLimit: return "The authorized streaming duration was reached."
        }
    }
}

public struct AssemblyStreamingResult: Sendable, Equatable {
    public let text: String
    public let sessionID: String
    public let sessionDurationSeconds: Double
    public let audioDurationSeconds: Double
}

/// One client owns one temporary-token session. The caller retains its local recording independently.
public actor AssemblyStreamingClient {
    private enum Phase { case idle, connecting, recording, finishing, complete, failed }
    private struct Turn { let text: String; let final: Bool; let formatted: Bool }
    private let socket: any AssemblyStreamingSocket
    private let timeoutSeconds: Double
    private var phase: Phase = .idle
    private var failure: Error?
    private var receiver: Task<Void, Never>?
    private var connector: Task<Void, Never>?
    private var connected = false
    private var activeSends: Set<UUID> = []
    private var completedSends: Set<UUID> = []
    private var maxSeconds = 0
    private var transcriptBytes = 0
    private var outbound: Task<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var sessionID: String?
    private var turns: [Int: Turn] = [:]
    private var result: AssemblyStreamingResult?
    private var buffer = Data()
    private var sampleRate = 0
    private var maxBytes = 0
    private var receivedBytes = 0
    private var queuedBytes = 0

    public init(socket: any AssemblyStreamingSocket = URLSessionAssemblyStreamingSocket(), timeoutSeconds: Double = 15) {
        self.socket = socket
        self.timeoutSeconds = timeoutSeconds.isFinite ? min(60, max(0.01, timeoutSeconds)) : 15
    }

    public func start(token: String, sampleRate: Int, model: String = "universal-3-5-pro", maxSeconds: Int = 600) async throws -> String {
        guard phase == .idle else { throw AssemblyStreamingError.invalidState }
        guard !token.isEmpty, token.count <= 8192, (8000...96000).contains(sampleRate), (60...10800).contains(maxSeconds),
              ["universal-3-5-pro", "universal-streaming-english", "universal-streaming-multilingual"].contains(model) else {
            throw AssemblyStreamingError.invalidConfiguration
        }
        self.sampleRate = sampleRate
        self.maxSeconds = maxSeconds
        maxBytes = sampleRate * 2 * maxSeconds
        phase = .connecting
        var url = URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        url.queryItems = [URLQueryItem(name: "token", value: token), URLQueryItem(name: "sample_rate", value: String(sampleRate)), URLQueryItem(name: "encoding", value: "pcm_s16le"), URLQueryItem(name: "speech_model", value: model)]
        do {
            let request = URLRequest(url: url.url!)
            connector = Task {
                do {
                    try await socket.connect(request)
                    self.connected = true
                } catch { await self.fail(AssemblyStreamingError.disconnected) }
            }
            try await waitUntil { self.connected }
            try checkFailure()
            receiver = Task { await self.readMessages() }
            try await waitUntil { self.sessionID != nil }
            phase = .recording
            deadline = Task {
                do { try await Task.sleep(nanoseconds: UInt64(maxSeconds) * 1_000_000_000) }
                catch { return }
                await self.fail(AssemblyStreamingError.sessionLimit)
            }
            return sessionID!
        } catch {
            await fail(error is CancellationError ? CancellationError() : (error as? AssemblyStreamingError ?? .disconnected))
            throw failure ?? AssemblyStreamingError.disconnected
        }
    }

    public func append(pcm: Data) async throws {
        try checkFailure()
        guard phase == .recording else { throw AssemblyStreamingError.invalidState }
        guard pcm.count % 2 == 0 else { throw AssemblyStreamingError.invalidAudio }
        guard receivedBytes + pcm.count <= maxBytes else { await fail(AssemblyStreamingError.sessionLimit); throw AssemblyStreamingError.sessionLimit }
        guard pcm.count + queuedBytes + buffer.count <= sampleRate * 2 * 5 else { await fail(AssemblyStreamingError.disconnected); throw AssemblyStreamingError.disconnected }
        receivedBytes += pcm.count
        buffer.append(pcm)
        let chunkSize = sampleRate / 10 * 2
        var messages: [URLSessionWebSocketTask.Message] = []
        while buffer.count >= chunkSize {
            messages.append(.data(Data(buffer.prefix(chunkSize))))
            buffer.removeFirst(chunkSize)
        }
        try await enqueue(messages)
    }

    public func finish() async throws -> AssemblyStreamingResult {
        try checkFailure()
        if let result { return result }
        guard phase == .recording else { throw AssemblyStreamingError.invalidState }
        phase = .finishing
        var messages: [URLSessionWebSocketTask.Message] = []
        if !buffer.isEmpty {
            let minimumBytes = Int(ceil(Double(sampleRate) * 0.05)) * 2
            if buffer.count < minimumBytes { buffer.append(Data(repeating: 0, count: minimumBytes - buffer.count)) }
            messages.append(.data(buffer))
            buffer = Data()
        }
        messages.append(.string("{\"type\":\"Terminate\"}"))
        do {
            try await enqueue(messages)
            try await waitUntil { self.result != nil }
            return result!
        } catch {
            await fail(error)
            throw error
        }
    }

    public func cancel() async { await fail(CancellationError()) }

    private func checkFailure() throws {
        try Task.checkCancellation()
        if let failure { throw failure }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            try checkFailure()
            guard Date() < end else { throw AssemblyStreamingError.timedOut }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try checkFailure()
    }

    private func enqueue(_ messages: [URLSessionWebSocketTask.Message]) async throws {
        let size = messages.reduce(0) { sum, message in if case .data(let data) = message { return sum + data.count }; return sum }
        queuedBytes += size
        let id = UUID()
        activeSends.insert(id)
        defer { queuedBytes -= size; activeSends.remove(id); completedSends.remove(id) }
        let previous = outbound
        let socket = self.socket
        outbound = Task {
            do {
                if let previous { try await previous.value }
                for message in messages { try Task.checkCancellation(); try await socket.send(message) }
                if self.activeSends.contains(id) { self.completedSends.insert(id) }
            } catch {
                await self.fail(error is CancellationError ? CancellationError() : AssemblyStreamingError.disconnected)
                throw error
            }
        }
        do { try await waitUntil { self.completedSends.contains(id) } }
        catch { await fail(error); throw failure ?? error }
    }

    private func readMessages() async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let bytes): data = bytes
                case .string(let text): data = Data(text.utf8)
                @unknown default: throw AssemblyStreamingError.malformedResponse
                }
                guard data.count <= 1_048_576, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = json["type"] as? String else { throw AssemblyStreamingError.malformedResponse }
                switch type {
                case "Begin":
                    guard phase == .connecting, sessionID == nil, let id = json["id"] as? String, !id.isEmpty, id.count <= 256 else { throw AssemblyStreamingError.malformedResponse }
                    sessionID = id
                case "Turn":
                    guard sessionID != nil, let order = json["turn_order"] as? Int, (0...10000).contains(order), let text = json["transcript"] as? String, text.utf8.count <= 65_536, let final = json["end_of_turn"] as? Bool else { throw AssemblyStreamingError.malformedResponse }
                    let formatted = json["turn_is_formatted"] as? Bool ?? false
                    if let old = turns[order], (old.final && !final) || (old.formatted && !formatted) { continue }
                    let nextBytes = transcriptBytes - (turns[order]?.text.utf8.count ?? 0) + text.utf8.count
                    guard nextBytes <= 1_048_576 else { throw AssemblyStreamingError.malformedResponse }
                    transcriptBytes = nextBytes
                    turns[order] = Turn(text: text, final: final, formatted: formatted)
                case "Termination":
                    guard phase == .finishing, let id = sessionID, let duration = json["session_duration_seconds"] as? Double, let audio = json["audio_duration_seconds"] as? Double, duration.isFinite, audio.isFinite, duration >= 0, duration <= Double(maxSeconds + 15), audio >= 0, audio <= Double(receivedBytes) / Double(sampleRate * 2) + 1 else { throw AssemblyStreamingError.malformedResponse }
                    guard turns.values.allSatisfy({ $0.final || $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw AssemblyStreamingError.malformedResponse }
                    let text = turns.keys.sorted().compactMap { turns[$0]?.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
                    guard !text.isEmpty else { throw AssemblyStreamingError.emptyTranscript }
                    result = AssemblyStreamingResult(text: text, sessionID: id, sessionDurationSeconds: duration, audioDurationSeconds: audio)
                    phase = .complete
                    deadline?.cancel()
                    await socket.close()
                    return
                case "SpeechStarted", "Heartbeat": break
                default: throw AssemblyStreamingError.malformedResponse
                }
            }
        } catch {
            if phase != .complete { await fail(error as? AssemblyStreamingError ?? .disconnected) }
        }
    }

    private func fail(_ error: Error) async {
        guard phase != .complete else { return }
        if failure == nil { failure = error }
        phase = .failed
        receiver?.cancel()
        connector?.cancel()
        outbound?.cancel()
        deadline?.cancel()
        buffer = Data()
        await socket.close()
    }
}
