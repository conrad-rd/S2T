import AppKit
import AVFoundation
import S2TCore

struct TimedTransport: HTTPTransport {
    let base = SessionTransport()
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let start = ProcessInfo.processInfo.systemUptime
        let response = try await base.data(for: request)
        let stage = request.url?.host == "sync.assemblyai.com" ? "sync" : request.url?.path == "/v2/upload" ? "upload" : request.httpMethod == "POST" ? "submit" : "poll"
        print(String(format: "%@: %.3f s, HTTP %d", stage, ProcessInfo.processInfo.systemUptime - start, response.1.statusCode))
        return response
    }
}

@MainActor enum LatencyProbe {
    static func run(file: String) async throws {
        print("Accessibility granted: \(AXIsProcessTrusted())")
        let key = try Keychain.read("assemblyai", allowInteraction: false)
        guard !key.isEmpty else { throw ServiceError.message("No saved AssemblyAI key is available for the timing check.") }
        let audio = try Data(contentsOf: URL(fileURLWithPath: file))
        let start = ProcessInfo.processInfo.systemUptime
        let transcript = try await DictationAPI(transport: TimedTransport(), pollInterval: 1_500_000_000).transcribe(audio: audio, apiKey: key, mode: .extended)
        print(String(format: "Batch transcription: %.3f s; %d characters", ProcessInfo.processInfo.systemUptime - start, transcript.count))
        let immediate = DictationAPI(transport: TimedTransport())
        await immediate.warmTranscriptionConnection()
        let fastStart = ProcessInfo.processInfo.systemUptime
        let fast = try await immediate.transcribe(audio: audio, apiKey: key)
        print(String(format: "Immediate transcription: %.3f s; %d characters", ProcessInfo.processInfo.systemUptime - fastStart, fast.count))
        print("Same words: \(transcript.lowercased().split(whereSeparator: { !$0.isLetter }).elementsEqual(fast.lowercased().split(whereSeparator: { !$0.isLetter })))")

    }
}
