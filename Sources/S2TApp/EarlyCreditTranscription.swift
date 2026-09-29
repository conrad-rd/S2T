import Foundation
import S2TCore

actor EarlyCreditTranscription {
    nonisolated let provider: TranscriptionProvider
    nonisolated let model: String
    nonisolated let connection: CreditConnection
    private let api: CreditsAPI
    private let store: RecordingRecoveryStore?
    private var saved: RecordingRecovery
    private var pump: Task<Void, Never>?
    private var stopping = false
    private var cancelled = false

    init(provider: TranscriptionProvider, model: String, connection: CreditConnection,
         api: CreditsAPI, store: RecordingRecoveryStore?, mode: WritingMode) {
        self.provider = provider
        self.model = model
        self.connection = connection
        self.api = api
        self.store = store
        saved = RecordingRecovery(audio: Data(), requestID: UUID().uuidString, mode: mode)
        saved.speechUploadRate = WaveAudio.speechUploadRate
        saved.speechSegmentEnds = []
    }

    func start(microphone: Microphone) {
        pump = Task {
            var segmentation = SpeechSegmentation()
            do {
                while !stopping {
                    try Task.checkCancellation()
                    let chunk = microphone.drainStreamingAudio()
                    if let end = segmentation.append(chunk.samples, sampleRate: chunk.sampleRate) {
                        saved.audio = microphone.audioPrefix(frames: end)
                        saved.speechSegmentEnds?.append(end)
                        let request = try (saved.creditSpeechRequest ?? CreditSpeechRequest(provider: provider, model: model,
                            connection: connection, requestID: saved.requestID + "-speech", segmented: true))
                            .appending(audio: saved.audio, segmentEnds: saved.speechSegmentEnds, complete: false)
                        saved.creditSpeechRequest = request
                        try await store?.save(saved)
                        try Task.checkCancellation()
                        _ = try await api.transcribe(request, connection: connection, completedParts: saved.completedParts,
                            onPartCompleted: { key, text in try await self.completed(key, text: text) })
                    }
                    if !chunk.hasMore { try await Task.sleep(for: .milliseconds(100)) }
                }
            } catch {
                // Finish retries an uncertain section with its saved payment identity.
            }
        }
    }

    private func completed(_ key: String, text: String) async throws {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        saved.completedParts[key] = text
        try await store?.save(saved)
    }

    func stop() { stopping = true }

    func finish(audio: Data) async throws -> RecordingRecovery {
        stopping = true
        await pump?.value
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        saved.audio = audio
        try await store?.save(saved)
        return saved
    }

    func snapshot(audio: Data) -> RecordingRecovery {
        saved.audio = audio
        return saved
    }

    func interrupt(audio: Data) async throws -> RecordingRecovery {
        cancelled = true
        stopping = true
        pump?.cancel()
        saved.audio = audio
        try await store?.save(saved)
        return saved
    }

    func cancel() async {
        cancelled = true
        stopping = true
        pump?.cancel()
        await pump?.value
        if !saved.audio.isEmpty { try? await store?.complete(saved) }
    }
}
