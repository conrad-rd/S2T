import Foundation

public struct ArtificialAnalysisPublicClient: Sendable {
    public static let speechURL = URL(string: "https://artificialanalysis.ai/speech-to-text/models/assemblyai")!
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = SessionTransport()) { self.transport = transport }

    public func fetch(now: Date = Date()) async throws -> ArtificialAnalysisSnapshot {
        var request = URLRequest(url: Self.speechURL)
        request.timeoutInterval = 25
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else { throw ArtificialAnalysisError.http(response.statusCode) }
        guard data.count <= 8_000_000, let html = String(data: data, encoding: .utf8) else { throw ArtificialAnalysisError.invalidData }
        return try Self.decode(html, now: now)
    }

    public static func decode(_ html: String, now: Date = Date()) throws -> ArtificialAnalysisSnapshot {
        func captures(_ pattern: String, in value: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
            return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
                Range($0.range(at: 1), in: value).map { String(value[$0]) }
            }
        }
        func plain(_ value: String) -> String {
            value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func normalized(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
        func number(_ value: String) -> Double? {
            guard let value = Double(value.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: "")), value.isFinite, value >= 0 else { return nil }
            return value
        }
        let aliases = ["xai/grok-voice-transcribe-2.0": "Grok Voice Transcribe 2.0", "xai/grok-voice-transcribe-1.0": "Grok Voice Transcribe 1.0"]
        let references = BenchmarkCatalog.hosted.filter { $0.task == "speech" && $0.quality[.speech] != nil }
        var models: [BenchmarkModel] = []
        for table in captures("<table\\b[^>]*>(.*?)</table>", in: html) {
            let rows = captures("<tr\\b[^>]*>(.*?)</tr>", in: table)
            guard let first = rows.first else { continue }
            let headers = captures("<th\\b[^>]*>(.*?)</th>", in: first).map(plain)
            guard let nameIndex = headers.firstIndex(of: "Model"), let hostIndex = headers.firstIndex(of: "Provider"),
                  let qualityIndex = headers.firstIndex(where: { $0.contains("Word Error Rate") }),
                  let speedIndex = headers.firstIndex(where: { $0.contains("Median Speed Factor") }),
                  let costIndex = headers.firstIndex(where: { $0.contains("Price") }) else { continue }
            for row in rows.dropFirst() {
                let cells = captures("<td\\b[^>]*>(.*?)</td>", in: row).map(plain)
                guard cells.count > [nameIndex, hostIndex, qualityIndex, speedIndex, costIndex].max()! else { continue }
                let name = normalized(String(cells[nameIndex].split(separator: ",").first ?? ""))
                let host = cells[hostIndex]
                for reference in references {
                    let expectedName = normalized(aliases[reference.id] ?? reference.name)
                    let note = reference.quality[.speech]!.note
                    let expectedHost = note.components(separatedBy: "Reference host: ").last?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
                    guard name == expectedName,
                          normalized(host) == normalized(expectedHost) || (expectedHost == "xAI" && host == "SpaceXAI") else { continue }
                    func measure(_ value: String, description: String) -> BenchmarkMeasurement? {
                        number(value).map { .init($0, source: "https://artificialanalysis.ai/speech-to-text/non-streaming", note: description + " Measured host: " + host + ". Public AA table; not an OpenRouter route measurement.") }
                    }
                    let quality = measure(cells[qualityIndex], description: "AA-WER v2, non-streaming.")
                    models.append(.init(id: reference.id, name: reference.name, provider: reference.provider, task: "speech",
                        quality: quality.map { [.speech: $0] } ?? [:],
                        speed: measure(cells[speedIndex], description: "Median speed factor for 10-minute audio."),
                        cost: measure(cells[costIndex], description: "USD per 1,000 audio minutes."), modelID: reference.modelID))
                }
            }
        }
        guard !models.isEmpty, Set(models.map(\.id)).count == models.count else { throw ArtificialAnalysisError.invalidData }
        return .init(models: models, fetchedAt: now, tier: "public", indexVersion: nil, speechAvailable: true, warning: nil)
    }
}
