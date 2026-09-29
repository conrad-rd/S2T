@preconcurrency import AVFoundation
import Speech
import S2TCore

@available(macOS 26, *)
enum NativeSpeechModels {
    static func catalog() async -> (models: [LocalModel], installed: Set<String>) {
        guard SpeechTranscriber.isAvailable else { return ([], []) }
        let locales = await SpeechTranscriber.supportedLocales
        let models = locales.map { LocalModel.appleSpeech(locale: $0.identifier) }
        var installed = Set<String>()
        for model in models {
            if let transcriber = try? await module(model), await AssetInventory.status(forModules: [transcriber]) == .installed {
                installed.insert(model.id)
            }
        }
        return (models, installed)
    }

    static func module(_ model: LocalModel) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable, let identifier = model.nativeLocale,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
            throw ServiceError.message("Apple Speech is unavailable for this language or Mac.")
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
    }

    static func install(_ model: LocalModel) async throws {
        let transcriber = try await module(model)
        guard let locale = transcriber.selectedLocales.first,
              try await AssetInventory.reserve(locale: locale) else {
            throw ServiceError.message("macOS could not reserve this speech language. Its language-model limit may have been reached.")
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await withTaskCancellationHandler {
                try await request.downloadAndInstall()
            } onCancel: { request.progress.cancel() }
        }
        try Task.checkCancellation()
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw ServiceError.message("macOS has not finished preparing this speech language. Try Install again.")
        }
    }

    static func transcribe(audio: Data, modelID: String) async throws -> TimedTranscription {
        let model = LocalModel.appleSpeech(locale: String(modelID.dropFirst("apple-speech-".count)))
        let transcriber = try await module(model)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw ServiceError.message("Install this Apple Speech language in Settings → Local first.")
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            do {
                let input = try pcmBuffer(audio)
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: input.format),
                      let converter = AVAudioConverter(from: input.format, to: format),
                      let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 32) else {
                    throw ServiceError.message("Apple Speech could not prepare the recording format.")
                }
                var supplied = false
                var conversionError: NSError?
                let conversion = converter.convert(to: converted, error: &conversionError) { _, status in
                    if supplied { status.pointee = .endOfStream; return nil }
                    supplied = true
                    status.pointee = .haveData
                    return input
                }
                guard conversion != .error else { throw conversionError ?? NSError(domain: "S2T.Audio", code: 1) }
                let results = Task { () throws -> TimedTranscription in
                    var text = ""
                    var words: [TimedWord] = []
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        text += String(result.text.characters)
                        for run in result.text.runs {
                            if let range = run.audioTimeRange {
                                words.append(TimedWord(text: String(result.text[run.range].characters), start: range.start.seconds, end: CMTimeRangeGetEnd(range).seconds))
                            }
                        }
                    }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { throw ServiceError.message("Apple Speech did not recognize any words. Try recording again.") }
                    return TimedTranscription(text: trimmed, words: words)
                }
                defer { results.cancel() }
                let sequence = AsyncStream<AnalyzerInput> { continuation in
                    continuation.yield(AnalyzerInput(buffer: converted))
                    continuation.finish()
                }
                try Task.checkCancellation()
                try await analyzer.start(inputSequence: sequence)
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let result = try await results.value
                try Task.checkCancellation()
                return result
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }

    // The microphone produces this fixed mono PCM16 WAV layout through WaveAudio.encode.
    static func pcmBuffer(_ audio: Data) throws -> AVAudioPCMBuffer {
        func word(_ offset: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | Int(audio[offset + $1]) << (8 * $1) }
        }
        guard audio.count >= 46, audio.count % 2 == 0,
              String(data: audio[0..<4], encoding: .ascii) == "RIFF",
              String(data: audio[8..<16], encoding: .ascii) == "WAVEfmt ",
              word(16, 4) == 16, word(20, 2) == 1, word(22, 2) == 1, word(34, 2) == 16,
              String(data: audio[36..<40], encoding: .ascii) == "data",
              word(40, 4) == audio.count - 44, (8000...192000).contains(word(24, 4)),
              let format = AVAudioFormat(standardFormatWithSampleRate: Double(word(24, 4)), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount((audio.count - 44) / 2)),
              let channel = buffer.floatChannelData?[0] else {
            throw ServiceError.message("Apple Speech received an unsupported recording format.")
        }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = Float(Int16(bitPattern: UInt16(word(44 + index * 2, 2)))) / 32768
        }
        return buffer
    }
}
