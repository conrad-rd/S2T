import Foundation
import CryptoKit

/// A submitted cleanup's identity, wire input and local substitutions travel together through recovery.
public struct CreditCleanupRequest: Codable, Sendable {
    public let requestID: String
    public let body: [String: String]
    private let accountFingerprint: Data
    private let editing: DictationEditingRequest
    public let clipboardContext: ClipboardContext

    public init(text: String, mode: WritingMode, model: String, endpoint: String?, connection: CreditConnection,
                clipboardContext: ClipboardContext, instructions: String?, options: OpenRouterOptions = .init(),
                requestID: String, provider: ProcessingProvider = .openRouter) throws {
        guard [.openRouter, .xai].contains(provider), provider.validModelID(model) else {
            throw ServiceError.message("Enter a valid text model ID.")
        }
        if provider == .openRouter { try options.validateConsent(model: model) }
        self.requestID = requestID
        self.clipboardContext = clipboardContext
        accountFingerprint = Self.fingerprint(connection)
        editing = try DictationEditingRequest(text: text, mode: mode, instructions: instructions, clipboardContext: clipboardContext)
        var body = ["provider": provider.rawValue, "operation": "cleanup", "model": model,
                    "text": editing.source, "instructions": editing.instructions, "host": endpoint ?? ""]
        if provider == .openRouter {
            body["reasoning"] = options.normalized(for: model).reasoning.rawValue
            body["fast"] = options.fast ? "true" : "false"
            body["allowDataCollection"] = options.allowDataCollection && model == OpenRouterOptions.contributorModel ? "true" : "false"
        } else { body["host"] = "" }
        self.body = body
    }

    func validate(_ connection: CreditConnection) throws {
        guard accountFingerprint == Self.fingerprint(connection) else {
            throw ServiceError.message("Reconnect the S2T key used for this saved cleanup before retrying. Its original paid request is preserved.")
        }
    }

    func finish(_ text: String) throws -> String { clipboardContext.resolve(try editing.finish(text)) }

    private static func fingerprint(_ connection: CreditConnection) -> Data {
        Data(SHA256.hash(data: Data((connection.origin.absoluteString + "\n" + connection.key).utf8)))
    }
}
