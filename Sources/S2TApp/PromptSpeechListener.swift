import AppKit
import Speech
import S2TCore

@MainActor final class PromptSpeechListener {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var detector = PromptReferenceDetector()
    private var generation = UUID()
    private var requestSequence = 0
    private var startedAt = Date()
    private var onReference: ((String, Double) -> Void)?
    private var onFailure: ((String) -> Void)?
    private weak var microphone: Microphone?
    private var audioSeconds: Double = 0
    private var recentAudio: [Float] = []
    private var recentSampleRate: Double = 48000
    private var settledWords: [TimedWord] = []
    private var currentWords: [TimedWord] = []
    private var finishing = false
    private var requestFinished = false

    static var permissionGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    func start(microphone: Microphone, locale: String, onReference: @escaping (String, Double) -> Void, onFailure: @escaping (String) -> Void) throws {
        stop()
        guard Self.permissionGranted else { throw ServiceError.message("Allow Speech Recognition under Prompt mode setup first.") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw ServiceError.message("On-device speech recognition is unavailable for this language. Choose English or German in Prompt mode, and make sure macOS has downloaded that language.")
        }
        self.recognizer = recognizer
        self.microphone = microphone
        self.onReference = onReference
        self.onFailure = onFailure
        detector = PromptReferenceDetector()
        audioSeconds = 0
        recentAudio = []
        settledWords = []; currentWords = []; finishing = false; requestFinished = false
        beginRequest()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pump() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func beginRequest(replay: Bool = false) {
        task?.cancel()
        generation = UUID()
        startedAt = Date()
        let id = generation
        requestSequence += 1
        let sequence = requestSequence
        let offset = audioSeconds - (replay ? Double(recentAudio.count) / recentSampleRate : 0)
        if !currentWords.isEmpty {
            settledWords.removeAll { $0.start >= currentWords[0].start }
            settledWords.append(contentsOf: currentWords)
        }
        currentWords = []
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = ["look here", "like here", "zoom in here", "this area here", "look at this", "look at that", "check this out", "schau mal hier", "so wie hier", "schau dir das an"]
        self.request = request
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.generation == id, self.request != nil else { return }
                if let result {
                    let transcription = result.bestTranscription
                    self.currentWords = transcription.segments.flatMap { segment -> [TimedWord] in
                        let parts = segment.substring.split(whereSeparator: \.isWhitespace)
                        return parts.enumerated().map { index, part in
                            let duration = segment.duration / Double(max(1, parts.count))
                            return TimedWord(text: String(part), start: offset + segment.timestamp + Double(index) * duration,
                                             end: offset + segment.timestamp + Double(index + 1) * duration)
                        }
                    }
                    for event in self.detector.consume(text: transcription.formattedString, wordTimes: transcription.segments.map { offset + $0.timestamp }, requestID: sequence) {
                        self.onReference?(event.phrase, event.seconds)
                    }
                }
                if error != nil {
                    if self.finishing { self.requestFinished = true; return }
                    let callback = self.onFailure
                    self.stop()
                    callback?("Local reference timing stopped. Final transcript timestamps will still be used when available.")
                } else if result?.isFinal == true {
                    if self.finishing { self.requestFinished = true }
                    else { self.beginRequest() }
                }
            }
        }
        if replay { append(recentAudio, rate: recentSampleRate, to: request) }
    }

    private func pump() {
        guard let microphone, let request else { return }
        let audio = microphone.drainSpeechAudio()
        if audio.overflowed {
            let callback = onFailure
            stop()
            callback?("Local reference timing could not keep up. Final transcript timestamps will still be used when available.")
            return
        }
        if !audio.samples.isEmpty {
            append(audio.samples, rate: audio.sampleRate, to: request)
            audioSeconds += Double(audio.samples.count) / audio.sampleRate
            if recentSampleRate != audio.sampleRate { recentAudio = [] }
            recentSampleRate = audio.sampleRate
            recentAudio.append(contentsOf: audio.samples)
            let excess = recentAudio.count - Int(audio.sampleRate * 1.5)
            if excess > 0 { recentAudio.removeFirst(excess) }
        }
        // Replay the overlap so a phrase spanning Speech's task rollover is still recognized.
        if !finishing, Date().timeIntervalSince(startedAt) > 45 { beginRequest(replay: true) }
    }

    private func append(_ samples: [Float], rate: Double, to request: SFSpeechAudioBufferRecognitionRequest) {
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: $0.count) }
        request.append(buffer)
    }

    func finish() async -> [TimedWord] {
        let id = generation
        finishing = true
        pump()
        timer?.invalidate(); timer = nil
        request?.endAudio()
        for _ in 0..<50 {
            if requestFinished || request == nil || Task.isCancelled || generation != id { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard generation == id else { return [] }
        let start = currentWords.first?.start ?? .infinity
        let words = settledWords.filter { $0.start < start } + currentWords
        stop()
        return words
    }

    func stop() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        microphone = nil
        recentAudio = []
        onReference = nil; onFailure = nil
    }
}
