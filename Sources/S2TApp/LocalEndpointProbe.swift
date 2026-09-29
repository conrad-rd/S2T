import Foundation
import S2TCore

@MainActor enum LocalEndpointProbe {
    static func run() async throws {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--local-fixture-url"), args.indices.contains(index + 1),
              let base = URL(string: args[index + 1]), base.scheme == "http", base.host == "127.0.0.1", base.port != nil else {
            throw ServiceError.message("Supply --local-fixture-url with the loopback fixture server URL.")
        }
        let api = DictationAPI()
        let audio = WaveAudio.encode(samples: [0, 120, -120, 0], sampleRate: 16000)
        let transcript = try await api.transcribe(audio: audio, apiKey: "never-send-fixture", provider: .local,
            model: "fixture/whisper:latest", localURL: base.appendingPathComponent("v1/audio/transcriptions").absoluteString)
        guard transcript == "Fixture speech." else { throw ServiceError.message("Unexpected local transcription.") }
        let result = try await api.process(text: transcript, mode: .clean, model: "fixture/cleanup:latest",
            apiKey: "never-send-fixture", provider: .local, endpoint: "cerebras/fp16",
            localURL: base.appendingPathComponent("v1/chat/completions").absoluteString)
        guard result.text == "Fixture cleaned.", result.model == "fixture/cleanup:latest" else {
            throw ServiceError.message("Unexpected local cleanup.")
        }
        print("PASS: packaged URLSession completed local HTTP WAV transcription and text cleanup with synthetic content.")
    }
}
