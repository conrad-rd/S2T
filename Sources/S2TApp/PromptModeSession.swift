import AppKit
import S2TCore

@MainActor final class PromptModeSession {
    struct Capture: Sendable {
        let number: Int
        let seconds: Double
        let phrase: String
        let screenshot: PromptScreenshot
    }
    let id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    private(set) var accepting = true
    private var cancelled = false
    private var recorder: PromptScreenRecorder?
    private var frameTask: Task<[PromptScreenRecorder.Frame], Never>?
    private var wordTask: Task<[TimedWord], Never>?
    private var frames: [PromptScreenRecorder.Frame]
    private var words: [TimedWord]
    private var audioOrigin: Double
    private var selected: [Capture]?
    private var sessionWarnings: [String] = []
    var onStatus: ((String) -> Void)?

    init(frames: [PromptScreenRecorder.Frame] = [], words: [TimedWord] = [], audioOrigin: Double = 0) {
        self.frames = frames; self.words = words; self.audioOrigin = audioOrigin
    }

    func startRecording() async throws {
        guard accepting, !cancelled else { throw CancellationError() }
        let recorder = PromptScreenRecorder()
        self.recorder = recorder
        recorder.onWarning = { [weak self] in self?.recordWarning($0) }
        try await recorder.start()
        try Task.checkCancellation()
        guard accepting, !cancelled else { recorder.cancel(); throw CancellationError() }
    }

    func setAudioOrigin(_ time: Double?) {
        if let time { audioOrigin = time }
        else { recordWarning("Audio timing was unavailable. Some visual references may be missing.") }
    }

    func setTranscriptionWords(_ words: [TimedWord]) { if !words.isEmpty { self.words = words } }
    func recordWarning(_ warning: String) { sessionWarnings.append(warning); onStatus?(warning) }

    func stopListening(words: Task<[TimedWord], Never>? = nil) {
        if let words { wordTask = words }
        guard accepting else { return }
        accepting = false
        if let recorder {
            recorder.pauseSampling()
            frameTask = Task {
                await recorder.stop()
                let frames = recorder.takeFrames()
                return Task.isCancelled ? [] : frames
            }
        }
    }

    func cancel() {
        cancelled = true; accepting = false
        recorder?.cancel(); frameTask?.cancel(); wordTask?.cancel()
        frames = []; words = []; selected = nil
        frameTask = nil; wordTask = nil; recorder = nil
    }

    var retainsTemporaryRecording: Bool { !frames.isEmpty || frameTask != nil || recorder != nil }

    struct Result {
        let references: [PromptReferenceText.Reference]
        let images: [URL]
        let warnings: [String]
    }

    private func selectFrames(transcript: String) async throws -> [Capture] {
        if let selected { return selected }
        defer { frames = []; frameTask = nil; wordTask = nil; recorder = nil }
        if let frameTask { frames = await frameTask.value }
        if words.isEmpty, let wordTask { words = await wordTask.value }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let frames = self.frames, words = self.words, origin = audioOrigin
        let selection = Task.detached(priority: .userInitiated) { () -> ([Capture], Int, Int) in
            let references = PromptTiming.references(transcript: transcript, words: words)
            let times = frames.map(\.time)
            var captures: [Capture] = []
            var missing = max(0, references.count - 64), approximate = 0
            for (index, reference) in references.prefix(64).enumerated() {
                try Task.checkCancellation()
                guard let seconds = reference.seconds,
                      let frame = PromptTiming.nearestFrame(to: origin + seconds, times: times) else { missing += 1; continue }
                guard let screenshot = try? frames[frame].screenshot() else { missing += 1; continue }
                captures.append(Capture(number: index + 1, seconds: seconds, phrase: reference.phrase, screenshot: screenshot))
                if reference.approximate { approximate += 1 }
            }
            return (captures, missing, approximate)
        }
        let result = try await withTaskCancellationHandler { try await selection.value } onCancel: { selection.cancel() }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        selected = result.0
        if result.1 > 0 { recordWarning("\(result.1) visual references could not be matched to recorded frames. No replacement screenshots were taken after recording.") }
        if result.2 > 0 { recordWarning("\(result.2) reference times were estimated between recognized words.") }
        return result.0
    }

    func describe(transcript: String, api: DictationAPI, key: String, model: String, directory: URL, provider: VisionProvider = .openRouter, localURL: String? = nil, codexExecutable: String = "", codexOptions: CodexOptions = CodexOptions(), onVisionError: ((Error) -> Bool)? = nil) async throws -> Result {
        stopListening()
        let captures = try await selectFrames(transcript: transcript)
        var warnings = sessionWarnings
        var descriptions = captures.map { "See screenshot for '\($0.phrase)'." }
        if !captures.isEmpty {
            do {
                descriptions = try await api.describePromptImages(captures.map {
                    PromptImageInput(number: $0.number, png: $0.screenshot.png, pointer: $0.screenshot.pointer, seconds: $0.seconds, phrase: $0.phrase)
                }, transcript: transcript, model: model, apiKey: key, provider: provider, localURL: localURL, codexExecutable: codexExecutable, codexOptions: codexOptions)
            } catch {
                try Task.checkCancellation()
                if onVisionError?(error) != true { warnings.append("Reference descriptions failed. \(error.localizedDescription)") }
            }
        }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        var references: [PromptReferenceText.Reference] = []
        var images: [URL] = []
        for (capture, description) in zip(captures, descriptions) {
            try Task.checkCancellation()
            let filename = "\(id)-reference-\(capture.number).png"
            var name: String?
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent(filename)
                try capture.screenshot.png.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                images.append(url); name = filename
            } catch { warnings.append("Couldn't save reference \(capture.number): \(error.localizedDescription)") }
            references.append(.init(number: capture.number, seconds: capture.seconds, description: description, imageName: name))
        }
        return Result(references: references, images: images, warnings: warnings)
    }
}
