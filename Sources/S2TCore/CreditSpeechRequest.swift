import Foundation
import CryptoKit

/// Exact submitted parts and their account identity survive provider changes and app updates.
public struct CreditSpeechRequest: Codable, Sendable {
    public struct Part: Codable, Equatable, Sendable {
        public let requestID: String
        public let cacheKey: String
        public let body: [String: String]
    }
    public let provider: TranscriptionProvider
    public let model: String
    public let requestID: String
    public let segmented: Bool
    private let accountFingerprint: Data
    public private(set) var parts: [Part] = []
    public private(set) var isComplete = false

    public init(provider: TranscriptionProvider, model: String, connection: CreditConnection,
                requestID: String, segmented: Bool) throws {
        guard (provider == .assemblyAI && model == "universal-3-5-pro") ||
                ([TranscriptionProvider.openRouter, .xai].contains(provider) && provider.validModelID(model)) else {
            throw ServiceError.message("Choose an AssemblyAI, OpenRouter or xAI speech model supported by S2T.")
        }
        self.provider = provider; self.model = model; self.requestID = requestID; self.segmented = segmented
        accountFingerprint = Self.fingerprint(connection)
    }

    public func appending(audio: Data, segmentEnds: [Int]?, complete: Bool) throws -> Self {
        if isComplete { return self }
        guard segmented == (segmentEnds != nil) else { throw ServiceError.message("The saved speech partition scheme cannot change during recovery.") }
        let audioParts = try segmentEnds.map { try WaveAudio.segmentedSpeechParts(audio, ends: $0) } ?? WaveAudio.creditParts(audio)
        let prepared = audioParts.enumerated().map { index, part in
            let digest = SHA256.hash(data: part + Data((provider.rawValue + ":" + model).utf8)).map { String(format: "%02x", $0) }.joined()
            return Part(requestID: audioParts.count == 1 && !segmented ? requestID : requestID + "-part-\(index)-" + digest.prefix(12),
                cacheKey: "\(index):" + digest, body: ["provider": provider.rawValue, "operation": "transcription", "model": model, "audio": part.base64EncodedString()])
        }
        guard prepared.count >= parts.count,
              zip(parts, prepared).allSatisfy({ $0.cacheKey == $1.cacheKey && $0.body == $1.body }) else {
            throw ServiceError.message("The remaining audio no longer matches its saved paid speech request. Save the recording; the original request is preserved.")
        }
        var result = self
        result.parts += prepared.dropFirst(parts.count)
        result.isComplete = complete
        return result
    }

    public func renewingRejectedPart(requestID: String) -> Self? {
        guard let index = parts.firstIndex(where: { $0.requestID == requestID }) else { return nil }
        var result = self
        let rejected = parts[index]
        result.parts[index] = Part(requestID: UUID().uuidString + "-speech-retry", cacheKey: rejected.cacheKey, body: rejected.body)
        return result
    }

    func validate(_ connection: CreditConnection) throws {
        guard accountFingerprint == Self.fingerprint(connection) else {
            throw ServiceError.message("Reconnect the S2T key used for this saved speech request before retrying. Its original paid request is preserved.")
        }
    }

    private static func fingerprint(_ connection: CreditConnection) -> Data {
        Data(SHA256.hash(data: Data((connection.origin.absoluteString + "\n" + connection.key).utf8)))
    }
}
