import Foundation
import CryptoKit
import CoreFoundation

public enum LocalUsageSource: String, Codable, Sendable, CaseIterable { case s2t, openRouter, xai, assemblyAI, typeSafe, local }

public struct LocalUsageRecord: Codable, Sendable {
    public let id: String
    public var date: Date
    public let source: LocalUsageSource
    public let amount: Decimal?
    public let tokens: Int?
    public let seconds: Double?
    public let estimated: Bool
    public let pending: Bool

    public static func read(request: URLRequest, data: Data, status: Int, credits: Bool, now: Date = Date()) -> Self? {
        guard (200..<300).contains(status), data.count <= 16_000_000,
              let url = request.url, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let source: LocalUsageSource
        var amount: Decimal?, tokens: Int?, seconds: Double?
        var estimated = false, pending = false
        var receipt = object["id"] as? String
        if credits {
            guard url.path == "/api/v1/requests" || url.path.hasPrefix("/api/v1/requests/"),
                  let state = object["state"] as? String,
                  ["settled", "reserved", "submitted", "uncertain", "released"].contains(state), receipt != nil else { return nil }
            source = .s2t
            pending = ["reserved", "submitted", "uncertain"].contains(state)
            amount = decimal(object[pending ? "reservedCredits" : "chargedCredits"])
            if state == "released" { amount = 0 }
        } else if url.host == "openrouter.ai", request.httpMethod == "POST",
                  ["/api/v1/chat/completions", "/api/v1/audio/transcriptions", "/api/alpha/decisions"].contains(url.path) {
            source = .openRouter
            let usage = object["usage"] as? [String: Any]
            amount = decimal(usage?["cost"])
            tokens = tokenCount(usage)
        } else if url.host == "api.typesafe.ai", url.path == "/v1/systemone", request.httpMethod == "POST" {
            source = .typeSafe
            tokens = tokenCount(object["usage"] as? [String: Any])
            amount = decimal((object["usage"] as? [String: Any])?["cost"])
        } else if url.host == "api.x.ai", request.httpMethod == "POST",
                  ["/v1/chat/completions", "/v1/responses", "/v1/stt"].contains(url.path) {
            source = .xai
            let usage = object["usage"] as? [String: Any]
            tokens = tokenCount(usage)
            // xAI reports the billed amount in ticks of 1e-10 USD.
            if let ticks = integer(usage?["cost_in_usd_ticks"]) { amount = Decimal(ticks) / 10_000_000_000 }
            if url.path == "/v1/stt" {
                if let duration = (object["duration"] as? NSNumber)?.doubleValue, duration.isFinite, (0...86_400).contains(duration) { seconds = duration }
                // Batch speech-to-text is billed at $0.10 per audio hour when no exact cost is returned.
                if amount == nil, let seconds { amount = Decimal(seconds) * Decimal(string: "0.10")! / 3600; estimated = true }
                receipt = nil
            }
        } else if ["api.assemblyai.com", "sync.assemblyai.com"].contains(url.host ?? "") {
            let sync = url.host == "sync.assemblyai.com" && ["/v1/transcribe", "/transcribe"].contains(url.path)
            guard sync || (url.path.hasPrefix("/v2/transcript") && object["status"] as? String == "completed") else { return nil }
            source = .assemblyAI
            estimated = true
            seconds = (object["audio_duration"] as? NSNumber)?.doubleValue
            if sync, seconds == nil, let body = request.httpBody,
               let start = body.range(of: Data("RIFF".utf8)), start.lowerBound < 4096 {
                let wav = Data(body[start.lowerBound...])
                if wav.count >= 44 {
                    func uint32(_ offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(wav[offset + $1]) << ($1 * 8) } }
                    let length = Int(uint32(4)) + 8
                    if length <= wav.count, length > 44, uint32(28) > 0,
                       String(data: wav[8..<12], encoding: .utf8) == "WAVE",
                       String(data: wav[36..<40], encoding: .utf8) == "data" {
                        seconds = Double(uint32(40)) / Double(uint32(28))
                    }
                }
            }
            if let duration = seconds, !duration.isFinite || duration < 0 || duration > 86_400 { seconds = nil }
            let model = object["speech_model_used"] as? String ?? object["speech_model"] as? String
            var hourly: Decimal? = sync ? Decimal(string: "0.45") : model == "universal-3-5-pro" ? Decimal(string: "0.21") : model == "universal-2" ? Decimal(string: "0.15") : nil
            if !sync, let rate = hourly {
                hourly = rate + (object["speaker_labels"] as? Bool == true ? Decimal(string: "0.02")! : 0)
            }
            if let seconds, let hourly { amount = Decimal(seconds) * hourly / 3600 }
            receipt = receipt ?? (sync ? request.value(forHTTPHeaderField: "X-Request-ID") : nil)
        } else if request.httpMethod == "POST", isLocal(url.host ?? ""),
                  ["/chat/completions", "/completions", "/responses", "/audio/transcriptions", "/api/chat", "/api/generate"].contains(where: { url.path.hasSuffix($0) }) {
            // Local models cost nothing, so they are tracked by tokens. Local servers often reuse
            // response IDs, so every response counts as its own request.
            source = .local
            tokens = tokenCount(object["usage"] as? [String: Any])
            if tokens == nil, let prompt = integer(object["prompt_eval_count"]), let output = integer(object["eval_count"]) {
                tokens = Int(prompt + output)
            }
            receipt = nil
        } else { return nil }
        let identity = source.rawValue + ":" + (receipt ?? UUID().uuidString)
        let id = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self(id: id, date: now, source: source, amount: amount, tokens: tokens, seconds: seconds, estimated: estimated, pending: pending)
    }

    /// Loopback, Bonjour and private-network hosts: local model servers on this Mac or the LAN.
    private static func isLocal(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if ["localhost", "::1"].contains(host) || host.hasSuffix(".local") || host.hasPrefix("fd") && host.contains(":") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 127 || parts[0] == 10 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }

    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1e16 else { return nil }
        return number.int64Value
    }

    private static func tokenCount(_ usage: [String: Any]?) -> Int? {
        guard let usage else { return nil }
        let total = integer(usage["total_tokens"]) ?? {
            guard let input = integer(usage["prompt_tokens"] ?? usage["input_tokens"]),
                  let output = integer(usage["completion_tokens"] ?? usage["output_tokens"]) else { return nil }
            return input + output
        }()
        guard let total, total <= 1_000_000_000 else { return nil }
        return Int(total)
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let text = String(describing: value)
        guard text.count < 64, text.range(of: #"^[+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil, let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= 0, number <= 1_000_000 else { return nil }
        return number
    }
}

public struct LocalUsageSnapshot: Codable, Sendable {
    public let records: [LocalUsageRecord]
    public let startedAt: Date
    public let error: String
}

public actor LocalUsageLedger {
    public static let changed = Notification.Name("S2TLocalUsageChanged")
    public static let maximumRecords = 10_000
    public static let retention: TimeInterval = 365 * 86400
    private let file: URL?
    private var loaded = false
    private var records: [String: LocalUsageRecord] = [:]
    private var startedAt = Date()
    private var error = ""
    private var archiveNotice = ""
    private var blockedArchive = false
    public init(file: URL? = nil) { self.file = file }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64_000_000 else { throw CocoaError(.fileReadTooLarge) }
            let saved = try JSONDecoder().decode(LocalUsageSnapshot.self, from: Data(contentsOf: file))
            if saved.startedAt.timeIntervalSince1970.isFinite { startedAt = min(Date(), saved.startedAt) }
            for record in saved.records where valid(record) { records[record.id] = record }
            compact()
        } catch {
            blockedArchive = true
            quarantineUnreadableArchive()
        }
    }

    private func quarantineUnreadableArchive() {
        guard blockedArchive, let file else { return }
        do {
            let backup = file.appendingPathExtension("unreadable-" + UUID().uuidString)
            try FileManager.default.moveItem(at: file, to: backup)
            blockedArchive = false
            archiveNotice = "An unreadable usage archive was preserved separately. New usage is being saved."
            error = archiveNotice
        } catch { self.error = "The unreadable usage archive could not be moved. New usage is kept in memory until saving is available." }
    }

    private func valid(_ record: LocalUsageRecord) -> Bool {
        !record.id.isEmpty && record.id.utf8.count <= 128 && record.date.timeIntervalSince1970.isFinite &&
        record.date.timeIntervalSince1970 >= 0 && record.date <= Date().addingTimeInterval(86400) &&
        (record.amount.map { !$0.isNaN && $0 >= 0 && $0 <= 1_000_000 } ?? true) &&
        (record.tokens.map { (0...1_000_000_000).contains($0) } ?? true) &&
        (record.seconds.map { $0.isFinite && (0...86400).contains($0) } ?? true)
    }

    private func compact() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        let bounded = records.values.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }.prefix(Self.maximumRecords)
        records = Dictionary(uniqueKeysWithValues: bounded.map { ($0.id, $0) })
        startedAt = max(startedAt, cutoff)
    }

    public func snapshot() -> LocalUsageSnapshot {
        load()
        compact()
        return .init(records: records.values.sorted { $0.date > $1.date }, startedAt: startedAt, error: error)
    }

    public func record(_ incoming: LocalUsageRecord) {
        load()
        guard valid(incoming) else { return }
        var record = incoming
        if let previous = records[record.id] {
            guard previous.pending || previous.amount == nil else { return }
            if !previous.pending && record.pending { return }
            record.date = previous.date
        }
        records[record.id] = record
        compact()
        quarantineUnreadableArchive()
        if let file, !blockedArchive {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot())
                guard data.count <= 8_000_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                error = archiveNotice
            } catch { self.error = "Usage is visible for this session, but could not be saved on this Mac." }
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
}

public struct LocalUsageTransport: HTTPTransport {
    private let base: any HTTPTransport
    private let ledger: LocalUsageLedger
    private let credits: Bool
    public init(base: any HTTPTransport = SessionTransport(), ledger: LocalUsageLedger, credits: Bool = false) {
        self.base = base; self.ledger = ledger; self.credits = credits
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await base.data(for: request)
        if let record = LocalUsageRecord.read(request: request, data: result.0, status: result.1.statusCode, credits: credits) {
            await ledger.record(record)
        }
        return result
    }
}
