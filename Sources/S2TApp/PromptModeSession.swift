import AppKit
import S2TCore

@MainActor final class PromptModeSession {
    struct Capture: Sendable {
        let number: Int
        let seconds: Double
        let phrase: String
        let screenshot: PromptScreenshot
        let cueIndex: Int?
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
    private(set) var manualCaptures: [Capture] = []
    private var pendingManualCaptures = 0
    private var manualSequence = 0
    var hasManualCaptures: Bool { !manualCaptures.isEmpty || pendingManualCaptures > 0 }
    private var captureWaiters: [CheckedContinuation<Void, Never>] = []
    var onStatus: ((String) -> Void)?
    /// A captured screenshot. `Bool` is true when its preview already flew into the deck.
    var onManualCapture: ((PromptScreenshot, Bool) -> Void)?
    /// A thumbnail and on-screen region, available before the full PNG is encoded.
    var onManualPreview: ((CGImage?, CGRect) -> Void)?
    var onCaptureTiming: (([String: Double]) -> Void)?
    var onSpokenCaptures: (([Capture]) -> Void)?

    init(frames: [PromptScreenRecorder.Frame] = [], words: [TimedWord] = [], audioOrigin: Double = 0) {
        self.frames = frames; self.words = words; self.audioOrigin = audioOrigin
    }

    @discardableResult func addManualCapture(_ screenshot: PromptScreenshot) -> Bool {
        guard accepting, !cancelled, manualCaptures.count < 64 else { return false }
        let capture = Capture(number: 0, seconds: -1, phrase: "selected area", screenshot: screenshot, cueIndex: nil)
        manualCaptures.append(capture)
        onManualCapture?(screenshot, false)
        return true
    }

    typealias AreaCapture = @MainActor (CGRect, @escaping @MainActor (PromptScreenshot?) -> Void) -> Void

    /// Starts capturing a ⌘-click region on mouse-down, before the gesture is known to be a click.
    func prefetchClick(_ rect: CGRect) {
        guard accepting, !cancelled, manualCaptures.count + pendingManualCaptures < 64 else { return }
        recorder?.prefetch(rect)
    }

    func captureArea(_ rect: CGRect, using operation: AreaCapture? = nil) {
        var previewed = false
        let recorded: AreaCapture? = recorder.map { recorder in
            { [weak self] rect, completion in
                recorder.manualScreenshot(in: rect, preview: { thumbnail, region in
                    guard let self, !self.cancelled else { return }
                    previewed = true
                    self.onManualPreview?(thumbnail, region)
                }, completion: completion)
            }
        }
        guard accepting, !cancelled, let capture = operation ?? recorded else { return }
        guard manualCaptures.count + pendingManualCaptures < 64 else {
            recordWarning("This prompt already has 64 screenshots. Finish it before adding more.")
            return
        }
        pendingManualCaptures += 1
        manualSequence += 1
        let order = manualSequence
        capture(rect) { [weak self] screenshot in
            guard let self, !self.cancelled else { return }
            self.pendingManualCaptures -= 1
            if let screenshot {
                self.manualCaptures.append(Capture(number: order, seconds: -1, phrase: "selected area", screenshot: screenshot, cueIndex: nil))
                self.manualCaptures.sort { $0.number < $1.number }
                self.onManualCapture?(screenshot, previewed)
            } else { self.recordWarning("Couldn't capture that area. Wait for visual recording to start, then try again.") }
            if self.pendingManualCaptures == 0 {
                let waiters = self.captureWaiters
                self.captureWaiters = []
                for waiter in waiters { waiter.resume() }
            }
        }
    }

    /// Starts screen recording without holding up the microphone. Display discovery and
    /// stream startup take a noticeable moment, so dictation begins while they finish.
    func beginRecording() {
        guard accepting, !cancelled, recorder == nil else { return }
        let recorder = PromptScreenRecorder()
        self.recorder = recorder
        recorder.onWarning = { [weak self] in self?.recordWarning($0) }
        recorder.onTiming = { [weak self] in self?.onCaptureTiming?($0) }
        Task { @MainActor [weak self] in
            do { try await recorder.start() }
            catch {
                guard let self, !self.cancelled, self.accepting, !(error is CancellationError) else { return }
                self.recordWarning("Screen recording could not start, so spoken references have no screenshots. \(error.localizedDescription)")
            }
        }
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
            // Sampling has stopped, so the history is final. Closing the streams can take a
            // while per display and does not need to finish before references are matched.
            frameTask = Task {
                let frames = await recorder.takeFrames()
                return Task.isCancelled ? [] : frames
            }
            Task { await recorder.stop() }
        }
    }

    func cancel() {
        cancelled = true; accepting = false
        pendingManualCaptures = 0
        let waiters = captureWaiters
        captureWaiters = []
        for waiter in waiters { waiter.resume() }
        recorder?.cancel(); frameTask?.cancel(); wordTask?.cancel()
        frames = []; words = []; selected = nil; manualCaptures = []
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
        if words.isEmpty, !PromptReferenceDetector.matches(transcript).isEmpty, let wordTask { words = await wordTask.value }
        if pendingManualCaptures > 0 { await withCheckedContinuation { captureWaiters.append($0) } }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let frames = self.frames, words = self.words, origin = audioOrigin
        let manual = manualCaptures
        let selection = Task.detached(priority: .userInitiated) { () -> ([Capture], Int, Int) in
            let references = PromptTiming.references(transcript: transcript, words: words)
            let times = frames.map(\.time)
            var captures: [Capture] = []
            let spokenLimit = max(0, 64 - manual.count)
            var missing = max(0, references.count - spokenLimit), approximate = 0
            // Screen recording starts alongside the microphone, so a reference spoken in the first
            // moments can precede the first frame. The screen rarely changes in that gap.
            let matched = references.prefix(spokenLimit).map { reference in
                reference.seconds.flatMap { PromptTiming.nearestFrame(to: origin + $0, times: times, leadingTolerance: 2) }
            }
            // Decode and convert each distinct frame once, on all cores.
            let unique = Array(Set(matched.compactMap { $0 })).sorted()
            let screenshots = PromptModeSession.convert(unique.map { frames[$0] })
            try Task.checkCancellation()
            for (cueIndex, (reference, frame)) in zip(references.prefix(spokenLimit), matched).enumerated() {
                guard let seconds = reference.seconds, let frame,
                      let screenshot = screenshots[unique.firstIndex(of: frame)!] else { missing += 1; continue }
                captures.append(Capture(number: captures.count + 1, seconds: seconds, phrase: reference.phrase, screenshot: screenshot, cueIndex: cueIndex))
                if reference.approximate { approximate += 1 }
            }
            for capture in manual where captures.count < 64 {
                captures.append(Capture(number: captures.count + 1, seconds: capture.seconds, phrase: capture.phrase, screenshot: capture.screenshot, cueIndex: nil))
            }
            return (captures, missing, approximate)
        }
        let result = try await withTaskCancellationHandler { try await selection.value } onCancel: { selection.cancel() }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        selected = result.0
        onSpokenCaptures?(result.0.filter { $0.seconds >= 0 })
        if result.1 > 0 { recordWarning("\(result.1) visual references could not be matched to recorded frames. No replacement screenshots were taken after recording.") }
        if result.2 > 0 { recordWarning("\(result.2) reference times were estimated between recognized words.") }
        return result.0
    }

    func saveReferences(transcript: String, directory: URL) async throws -> Result {
        stopListening()
        let captures = try await selectFrames(transcript: transcript)
        var warnings = sessionWarnings
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        let id = self.id
        let save = Task.detached(priority: .userInitiated) { () throws -> Result in
            try Task.checkCancellation()
            let prepared = Swift.Result<Void, Error>(catching: {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            })
            let outcomes = ConcurrentSlots<Swift.Result<URL, Error>>(count: captures.count)
            DispatchQueue.concurrentPerform(iterations: captures.count) { index in
                let capture = captures[index]
                outcomes[index] = Swift.Result {
                    try prepared.get()
                    let url = directory.appendingPathComponent("\(id)-reference-\(capture.number).png")
                    try capture.screenshot.png.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    return url
                }
            }
            try Task.checkCancellation()
            var warnings: [String] = []
            var references: [PromptReferenceText.Reference] = []
            var images: [URL] = []
            for (index, capture) in captures.enumerated() {
                var name: String?
                switch outcomes[index] {
                case .success(let url)?: images.append(url); name = url.lastPathComponent
                case .failure(let error)?: warnings.append("Couldn't save reference \(capture.number): \(error.localizedDescription)")
                case nil: break
                }
                references.append(.init(number: capture.number, seconds: capture.seconds, description: "See screenshot for '\(capture.phrase)'.", imageName: name, cueIndex: capture.cueIndex))
            }
            return Result(references: references, images: images, warnings: warnings)
        }
        let saved = try await withTaskCancellationHandler { try await save.value } onCancel: { save.cancel() }
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
        warnings += saved.warnings
        return Result(references: saved.references, images: saved.images, warnings: warnings)
    }

    /// Converts recorded frames to full-display screenshots concurrently. Failed frames stay nil.
    nonisolated static func convert(_ frames: [PromptScreenRecorder.Frame]) -> [PromptScreenshot?] {
        let results = ConcurrentSlots<PromptScreenshot>(count: frames.count)
        DispatchQueue.concurrentPerform(iterations: frames.count) { index in results[index] = try? frames[index].screenshot() }
        return results.values
    }
}

/// Fixed slots written once each from `DispatchQueue.concurrentPerform`, one index per iteration.
final class ConcurrentSlots<Value>: @unchecked Sendable {
    private var storage: [Value?]
    private let lock = NSLock()
    init(count: Int) { storage = Array(repeating: nil, count: count) }
    subscript(index: Int) -> Value? {
        get { lock.lock(); defer { lock.unlock() }; return storage[index] }
        set { lock.lock(); storage[index] = newValue; lock.unlock() }
    }
    var values: [Value?] { lock.lock(); defer { lock.unlock() }; return storage }
}
