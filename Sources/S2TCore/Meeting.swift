import Foundation

public enum MeetingModel: String, Codable, CaseIterable, Sendable {
    case universal35 = "universal-3-5-pro"
    case universal2 = "universal-2"
    case grok2 = "grok-voice-transcribe-2.0"
    case grok1 = "grok-voice-transcribe-1.0"
    public var provider: TranscriptionProvider {
        switch self { case .universal35, .universal2: return .assemblyAI; case .grok1, .grok2: return .xai }
    }
    public var title: String {
        switch self {
        case .universal35: return "Universal 3.5 Pro"
        case .universal2: return "Universal 2"
        case .grok2: return "Grok Voice Transcribe 2"
        case .grok1: return "Grok Voice Transcribe 1"
        }
    }
}

public struct MeetingUtterance: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var speaker: String
    public var start: Double
    public var end: Double
    public var text: String
    public var processedText: String?
    public var displayText: String { processedText ?? text }
    public init(speaker: String, start: Double, end: Double, text: String) {
        id = UUID(); self.speaker = speaker; self.start = start; self.end = end; self.text = text
    }
}

public struct MeetingChunk: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var index: Int
    public var start: Double
    public var duration: Double
    public var filename: String
    public var source = "room"
    public var ready = false
    public var sampleRate = 48000
    public var anchors: [MeetingSpeakerAnchor] = []
    public var prefixDuration: Double = 0
    public var requestFilename: String?
    public var utteranceIDs: [UUID]?
    public var processingCompleted: Bool?
    public var processingError: String?
    public var processingModel: String?
    public var processingHost: String?
    public var jobID: String?
    public var completed = false
    public var error: String?
    public init(index: Int, start: Double, duration: Double, filename: String) {
        self.index = index; self.start = start; self.duration = duration; self.filename = filename
    }
}

public struct MeetingRecord: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var createdAt = Date()
    public var endedAt: Date?
    public var model: MeetingModel
    public var processingSettings: MeetingProcessingSettings?
    public var chunks: [MeetingChunk] = []
    public var utterances: [MeetingUtterance] = []
    public var speakerNames: [String: String] = [:]
    public init(title: String, model: MeetingModel) { self.title = title; self.model = model }
    public var duration: Double { chunks.map { $0.start + $0.duration }.max() ?? 0 }
    public var speakers: [String] { Array(Set(utterances.map(\.speaker))).sorted() }
    public func name(for speaker: String) -> String { speakerNames[speaker] ?? speaker }
    public var plainText: String {
        ([title, createdAt.formatted(date: .abbreviated, time: .shortened), ""] + utterances.sorted { $0.start < $1.start }.map {
            "[\(Self.timestamp($0.start))] \(name(for: $0.speaker)): \($0.displayText)"
        }).joined(separator: "\n\n") + "\n"
    }
    public var markdown: String {
        (["# \(Self.escape(title))", createdAt.formatted(date: .abbreviated, time: .shortened)] + utterances.sorted { $0.start < $1.start }.map {
            "**\(Self.timestamp($0.start)) · \(Self.escape(name(for: $0.speaker)))**\n\n\(Self.escape($0.displayText))"
        }).joined(separator: "\n\n") + "\n"
    }
    public static func timestamp(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }
    private static func escape(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            if "\\`*_{}[]<>#|".contains(character) { result.append("\\") }
            result.append(character)
        }
    }
}

public struct MeetingStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func folder(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    public func save(_ record: MeetingRecord) throws {
        let folder = folder(record.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(record)
        let url = folder.appendingPathComponent("meeting.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func load() throws -> [MeetingRecord] { try loadWithIssues().records }

    public func loadWithIssues() throws -> (records: [MeetingRecord], unreadableFolders: [String]) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], []) }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var records: [MeetingRecord] = [], unreadable: [String] = []
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            do { records.append(try JSONDecoder().decode(MeetingRecord.self, from: Data(contentsOf: folder.appendingPathComponent("meeting.json")))) }
            catch { unreadable.append(folder.lastPathComponent) }
        }
        return (records.sorted { $0.createdAt > $1.createdAt }, unreadable)
    }
}

public enum MeetingJobFailure: Error { case failed }

public struct MeetingTranscriber: Sendable {
    private let transport: any HTTPTransport
    private let pollNanoseconds: UInt64
    public init(transport: any HTTPTransport = SessionTransport(), pollNanoseconds: UInt64 = 2_000_000_000) {
        self.transport = transport; self.pollNanoseconds = pollNanoseconds
    }
    public func submit(audio: Data, key: String, model: MeetingModel) async throws -> String {
        guard model.provider == .assemblyAI else { throw ServiceError.message("This model uses direct meeting transcription.") }
        let uploaded: Upload = try await send(path: "upload", method: "POST", key: key, body: audio, binary: true)
        let body = try JSONSerialization.data(withJSONObject: ["audio_url": uploaded.upload_url, "speech_models": [model.rawValue],
            "language_detection": true, "speaker_labels": true, "punctuate": true, "format_text": true])
        let job: Job = try await send(path: "transcript", method: "POST", key: key, body: body)
        guard let id = job.id, Self.validID(id) else { throw ServiceError.message("The meeting provider returned an invalid job ID.") }
        return id
    }
    public func transcribeGrok(audio: Data, key: String, model: MeetingModel) async throws -> [MeetingUtterance] {
        guard model.provider == .xai, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.message("Choose a Grok speech model and add your xAI key under API keys.")
        }
        guard audio.count <= 500_000_000 else { throw ServiceError.message("This meeting part exceeds xAI's 500 MB limit.") }
        let boundary = "S2T-" + UUID().uuidString
        var body = Data()
        for (name, value) in [("model", model.rawValue), ("diarize", "true")] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"meeting.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/stt")!)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ServiceError.message("Meeting transcription returned HTTP \(response.statusCode). Check your xAI key and balance, then retry.")
        }
        guard data.count <= 16_000_000 else { throw ServiceError.message("The meeting response is too large.") }
        let result = try JSONDecoder().decode(GrokTranscript.self, from: data)
        let words = result.words ?? []
        guard !words.isEmpty || result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.message("xAI returned text without speaker labels. Retry this meeting part.")
        }
        return try words.map { word in
            guard let speaker = word.speaker, speaker >= 0,
                  word.start.isFinite, word.end.isFinite, word.start >= 0, word.end >= word.start else {
                throw ServiceError.message("xAI returned missing speaker labels or invalid meeting timestamps.")
            }
            return MeetingUtterance(speaker: "Speaker \(speaker)", start: word.start, end: word.end, text: word.text)
        }
    }
    private struct GrokTranscript: Decodable { let text: String; let words: [GrokWord]? }
    private struct GrokWord: Decodable { let text: String; let start: Double; let end: Double; let speaker: Int? }

    public func result(id: String, key: String) async throws -> [MeetingUtterance] {
        guard Self.validID(id) else { throw ServiceError.message("The saved meeting job ID is invalid.") }
        for index in 0..<900 {
            try Task.checkCancellation()
            if index > 0 { try await Task.sleep(nanoseconds: pollNanoseconds) }
            let job: Job = try await send(path: "transcript/" + id, method: "GET", key: key)
            switch job.status {
            case "completed":
                let utterances = job.utterances ?? []
                guard !utterances.isEmpty || (job.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ServiceError.message("The provider returned text without speaker labels. Retry this meeting part.")
                }
                return try utterances.flatMap { utterance -> [MeetingUtterance] in
                    let values = utterance.words?.isEmpty == false ? utterance.words! : [utterance]
                    return try values.map {
                    guard let speaker = $0.speaker ?? utterance.speaker, !speaker.isEmpty,
                          $0.start.isFinite, $0.end.isFinite, $0.start >= 0, $0.end >= $0.start else { throw ServiceError.message("Missing speaker labels or invalid meeting timestamps.") }
                    return MeetingUtterance(speaker: "Speaker " + speaker, start: $0.start / 1000, end: $0.end / 1000, text: $0.text)
                    }
                }
            case "error": throw MeetingJobFailure.failed
            case "queued", "processing": continue
            default: throw ServiceError.message("Unexpected meeting transcription status.")
            }
        }
        throw ServiceError.message("Meeting transcription is still pending. Retry to check the same job again.")
    }
    private static func validID(_ id: String) -> Bool { !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
    private func send<T: Decodable>(path: String, method: String, key: String, body: Data? = nil, binary: Bool = false) async throws -> T {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.message("Add your AssemblyAI key under API keys to transcribe meetings.") }
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/" + path)!)
        request.httpMethod = method; request.httpBody = body
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue(binary ? "application/octet-stream" : "application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else { throw ServiceError.message("Meeting transcription returned HTTP \(response.statusCode). Check your AssemblyAI key and balance, then retry.") }
        guard data.count <= 16_000_000 else { throw ServiceError.message("The meeting response is too large.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private struct Upload: Decodable { let upload_url: String }
    private struct Job: Decodable { let id: String?; let status: String; let text: String?; let utterances: [Utterance]? }
    private struct Utterance: Decodable { let speaker: String?; let start: Double; let end: Double; let text: String; let words: [Utterance]? }
}

public struct MeetingSpeakerAnchor: Codable, Sendable {
    public var speaker: String
    public var start: Double
    public var end: Double
    public init(speaker: String, start: Double, end: Double) { self.speaker = speaker; self.start = start; self.end = end }
}

public enum MeetingSpeakers {
    public static func resolve(_ input: [MeetingUtterance], anchors: [MeetingSpeakerAnchor], prefix: Double, offset: Double, namespace: String) -> [MeetingUtterance] {
        var candidates: [String: Set<String>] = [:]
        for anchor in anchors {
            var votes: [String: Double] = [:]
            for value in input {
                let overlap = min(anchor.end, value.end) - max(anchor.start, value.start)
                if overlap > 0 { votes[value.speaker, default: 0] += overlap }
            }
            let ordered = votes.sorted { $0.value > $1.value }
            if let first = ordered.first, first.value >= 0.5,
               ordered.count == 1 || first.value > ordered[1].value * 2 {
                candidates[first.key, default: []].insert(anchor.speaker)
            }
        }
        var output: [MeetingUtterance] = []
        for var value in input.sorted(by: { $0.start < $1.start }) where value.start >= prefix - 0.001 {
            let identities = candidates[value.speaker] ?? []
            value.speaker = identities.count == 1 ? identities.first! : namespace + " · " + value.speaker
            value.start = max(0, value.start - prefix) + offset
            value.end = max(0, value.end - prefix) + offset
            if let last = output.last, last.speaker == value.speaker, value.start - last.end < 1.5, value.end - last.start < 30 {
                output[output.count - 1].text += " " + value.text
                output[output.count - 1].end = max(last.end, value.end)
            } else { output.append(value) }
        }
        return output
    }
}
