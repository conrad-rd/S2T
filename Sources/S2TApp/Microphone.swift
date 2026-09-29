import AVFoundation
import AudioToolbox
import Foundation
import S2TCore

final class Microphone: NSObject, @unchecked Sendable {
    private let simulation: (audio: [Float], delay: TimeInterval)?

    override init() {
        simulation = nil
        super.init()
    }

    init(simulatedAudio: [Float], startDelay: TimeInterval) {
        simulation = (simulatedAudio, startDelay)
        super.init()
    }

    static let configurationChanged = Notification.Name("S2TMicrophoneConfigurationChanged")
    private let controlQueue = DispatchQueue(label: "com.s2t.microphone", qos: .userInitiated)
    private var unit: AudioUnit?
    private var renderBuffer: UnsafeMutablePointer<Float>?
    private var capacity: UInt32 = 0
    private var activeDevice: AudioDeviceID?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var sessionID = UUID()
    private var reportedRenderFailure = false
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var level: Double = 0
    private var envelope = AudioEnvelope()
    private var spectrumAnalyzer = AudioSpectrum(sampleRate: 48000)
    private var frequencyLevels = Array(repeating: 0.0, count: AudioSpectrum.bandCount)
    private var sampleRate: Double = 48000
    private var capturing = false
    private var captureAudio = true
    private var liveSpeech = false
    private var speechSamples: [Float] = []
    private var speechOverflow = false
    private var streamingReadOffset: Int?
    private var recordingFinalized = false
    private var framesReceived = 0
    private var firstAudioTime: Double?
    var audioStartTime: Double? {
        lock.lock(); defer { lock.unlock() }
        return firstAudioTime
    }

    var meter: Double {
        lock.lock(); defer { lock.unlock() }
        return level
    }

    var spectrum: [Double] {
        lock.lock(); defer { lock.unlock() }
        return frequencyLevels
    }

    var capturedFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return framesReceived
    }

    func start(deviceUID: String = "", captureAudio: Bool = true, liveSpeech: Bool = false, streamingAudio: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controlQueue.async {
                do {
                    try self.startCapture(deviceUID: deviceUID, captureAudio: captureAudio, liveSpeech: liveSpeech, streamingAudio: streamingAudio)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func startCapture(deviceUID: String, captureAudio: Bool, liveSpeech: Bool, streamingAudio: Bool) throws {
        stopCapture()
        if let simulation {
            Thread.sleep(forTimeInterval: simulation.delay)
            resetCapture(rate: 48000, captureAudio: captureAudio, liveSpeech: liveSpeech, streamingAudio: streamingAudio)
            simulation.audio.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress { capture(base, count: buffer.count) }
            }
            return
        }
        guard var device = AudioInputs.resolve(deviceUID) else {
            throw ServiceError.message(deviceUID.isEmpty
                ? "No wired or built-in microphone is available. Connect one or choose a microphone in General settings."
                : "The selected microphone is unavailable. Choose another input in General settings.")
        }
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw ServiceError.message("macOS could not open audio capture.")
        }
        var created: AudioUnit?
        try check(AudioComponentInstanceNew(component, &created))
        guard let created else { throw ServiceError.message("macOS could not open the microphone.") }
        unit = created
        do {
            var enabled: UInt32 = 1
            var disabled: UInt32 = 0
            // Configure input-only capture before assigning or initializing any device.
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4))
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4))
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, 4))
            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &format, &formatSize))
            guard format.mSampleRate > 0, format.mChannelsPerFrame > 0 else {
                throw ServiceError.message("The microphone has no available audio input.")
            }
            let rate = format.mSampleRate
            format = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
            try check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, formatSize))
            var channel: Int32 = 0
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, &channel, 4))
            var frames: UInt32 = 0
            var size: UInt32 = 4
            try check(AudioUnitGetProperty(created, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, &size))
            capacity = max(frames, 16384)
            renderBuffer = .allocate(capacity: Int(capacity))
            var callback = AURenderCallbackStruct(inputProc: { reference, flags, time, _, frames, _ in
                let microphone = Unmanaged<Microphone>.fromOpaque(reference).takeUnretainedValue()
                return microphone.render(flags: flags, time: time, frames: frames)
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            resetCapture(rate: rate, captureAudio: captureAudio, liveSpeech: liveSpeech, streamingAudio: streamingAudio)
            try check(AudioUnitInitialize(created))
            observe(device)
            try check(AudioOutputUnitStart(created))
        } catch {
            stopCapture()
            throw error
        }
    }

    private func resetCapture(rate: Double, captureAudio: Bool, liveSpeech: Bool, streamingAudio: Bool) {
        lock.lock()
        sampleRate = rate
        samples = []
        if captureAudio { samples.reserveCapacity(Int(rate) * 60) }
        level = 0
        envelope = AudioEnvelope()
        spectrumAnalyzer = AudioSpectrum(sampleRate: rate)
        frequencyLevels = Array(repeating: 0, count: AudioSpectrum.bandCount)
        capturing = true
        reportedRenderFailure = false
        framesReceived = 0
        firstAudioTime = nil
        self.captureAudio = captureAudio
        self.liveSpeech = liveSpeech
        streamingReadOffset = streamingAudio ? 0 : nil
        recordingFinalized = false
        speechSamples = []
        speechOverflow = false
        lock.unlock()
    }

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, time: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        guard let unit, let renderBuffer, frames <= capacity else {
            reportRenderFailure()
            return kAudioUnitErr_TooManyFramesToProcess
        }
        var buffers = AudioBufferList(mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: renderBuffer))
        let status = AudioUnitRender(unit, flags, time, 1, frames, &buffers)
        if status == noErr {
            lock.lock()
            if firstAudioTime == nil {
                firstAudioTime = time.pointee.mFlags.contains(.hostTimeValid) && time.pointee.mHostTime > 0
                    ? AVAudioTime.seconds(forHostTime: time.pointee.mHostTime)
                    : ProcessInfo.processInfo.systemUptime
            }
            lock.unlock()
            capture(renderBuffer, count: Int(frames))
        }
        else { reportRenderFailure() }
        return status
    }

    private func reportRenderFailure() {
        lock.lock()
        let shouldReport = capturing && !reportedRenderFailure
        reportedRenderFailure = true
        let id = sessionID
        lock.unlock()
        guard shouldReport else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive(id) else { return }
            NotificationCenter.default.post(name: Self.configurationChanged, object: self)
        }
    }

    private func observe(_ device: AudioDeviceID) {
        activeDevice = device
        let id = sessionID
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.isActive(id) else { return }
            NotificationCenter.default.post(name: Self.configurationChanged, object: self)
        }
        deviceListener = listener
        for selector in Self.observedProperties {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, listener)
        }
    }

    private static let observedProperties = [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate]

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw ServiceError.message("Could not open the microphone, error \(status). Try another input.") }
    }

    private func capture(_ buffer: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        lock.lock()
        let saveAudio = captureAudio
        lock.unlock()
        var sum: Float = 0
        var peak: Float = 0
        var chunk = [Int16]()
        if saveAudio { chunk.reserveCapacity(count) }
        for index in 0..<count {
            let value = buffer[index]
            let finite = value.isFinite ? max(-1, min(1, value)) : 0
            spectrumAnalyzer.consume(Double(finite))
            sum += finite * finite
            peak = max(peak, abs(finite))
            if saveAudio { chunk.append(Int16(finite * 32767)) }
        }
        let rms = sqrt(Double(sum) / Double(count))
        lock.lock(); defer { lock.unlock() }
        guard capturing else { return }
        if liveSpeech {
            let remainingSpeech = max(0, Int(sampleRate * 2) - speechSamples.count)
            if count > remainingSpeech { speechOverflow = true }
            speechSamples.append(contentsOf: UnsafeBufferPointer(start: buffer, count: min(count, remainingSpeech)))
        }
        frequencyLevels = spectrumAnalyzer.levels
        framesReceived += count
        let remaining = max(0, Int(sampleRate * 600) - samples.count)
        samples.append(contentsOf: chunk.prefix(remaining))
        level = envelope.update(rms: rms, peak: Double(peak), duration: Double(count) / sampleRate)
    }

    func drainMeetingAudio() -> (samples: [Int16], sampleRate: Int) {
        lock.lock(); defer { lock.unlock() }
        let result = (samples, Int(sampleRate))
        samples.removeAll(keepingCapacity: true)
        return result
    }

    func drainSpeechAudio() -> (samples: [Float], sampleRate: Double, overflowed: Bool) {
        lock.lock(); defer { lock.unlock() }
        let result = (speechSamples, sampleRate, speechOverflow)
        speechSamples = []
        speechOverflow = false
        return result
    }

    var streamingSampleRate: Int {
        lock.lock(); defer { lock.unlock() }
        return Int(sampleRate)
    }

    func audioPrefix(frames: Int) -> Data {
        lock.lock()
        let captured = Array(samples.prefix(frames))
        let rate = UInt32(sampleRate)
        lock.unlock()
        return WaveAudio.encode(samples: captured, sampleRate: rate)
    }

    func releaseStreamingAudio() {
        lock.lock(); defer { lock.unlock() }
        guard recordingFinalized else { return }
        samples = []
        streamingReadOffset = nil
    }

    func drainStreamingAudio() -> (samples: [Int16], sampleRate: Int, hasMore: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard let offset = streamingReadOffset else { return ([], Int(sampleRate), false) }
        let end = min(samples.count, offset + Int(sampleRate / 10))
        let chunk = Array(samples[offset..<end])
        let hasMore = end < samples.count
        streamingReadOffset = end
        if recordingFinalized && !hasMore { samples = []; streamingReadOffset = nil }
        return (chunk, Int(sampleRate), hasMore)
    }

    func finish() async -> Data {
        await withCheckedContinuation { continuation in
            controlQueue.async { continuation.resume(returning: self.finishCapture()) }
        }
    }

    private func finishCapture() -> Data {
        stopCapture(preserveSpeech: true)
        lock.lock()
        let captured = samples
        let rate = UInt32(sampleRate)
        recordingFinalized = true
        if streamingReadOffset == nil { samples = [] }
        lock.unlock()
        return WaveAudio.encode(samples: captured, sampleRate: rate)
    }

    func cancel() {
        controlQueue.async { self.cancelCapture() }
    }

    func waitUntilStopped() async {
        await withCheckedContinuation { continuation in
            controlQueue.async { continuation.resume() }
        }
    }

    private func cancelCapture() {
        stopCapture()
        lock.lock(); samples = []; lock.unlock()
    }

    private func isActive(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return capturing && sessionID == id
    }

    private func stopCapture(preserveSpeech: Bool = false) {
        lock.lock()
        capturing = false
        liveSpeech = false
        if !preserveSpeech { streamingReadOffset = nil }
        if !preserveSpeech { speechSamples = []; speechOverflow = false }
        level = 0
        frequencyLevels = Array(repeating: 0, count: AudioSpectrum.bandCount)
        lock.unlock()
        if let unit { AudioOutputUnitStop(unit) }
        lock.lock(); sessionID = UUID(); lock.unlock()
        if let device = activeDevice, let listener = deviceListener {
            for selector in Self.observedProperties {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
        }
        deviceListener = nil
        activeDevice = nil
        if let unit {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        renderBuffer?.deallocate()
        renderBuffer = nil
        capacity = 0
    }

    @MainActor static func verifyStreamingAudio() throws {
        let microphone = Microphone()
        microphone.capturing = true
        microphone.liveSpeech = true
        microphone.streamingReadOffset = microphone.samples.count
        let signal: [Float] = [0, 0.5, -0.5, 1, -1]
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        let speech = microphone.drainSpeechAudio()
        let streamed = microphone.drainStreamingAudio()
        guard speech.samples == signal, streamed.samples == [0, 16383, -16383, 32767, -32767],
              microphone.samples == streamed.samples, microphone.drainStreamingAudio().samples.isEmpty else {
            throw ServiceError.message("Streaming changed local recording or consumed prompt audio.")
        }
        let long = Array(repeating: Float(0), count: 48000 * 6)
        long.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        var backlog: [Int16] = []
        while true {
            let chunk = microphone.drainStreamingAudio()
            guard chunk.samples.count <= 48000 else {
                throw ServiceError.message("Streaming chunks exceeded one second or lost buffered audio.")
            }
            backlog.append(contentsOf: chunk.samples)
            if !chunk.hasMore { break }
        }
        guard backlog.count == long.count else {
            throw ServiceError.message("Authorization backlog lost opening audio after five seconds.")
        }
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        microphone.stopCapture(preserveSpeech: true)
        let finalChunk = microphone.drainStreamingAudio()
        let audio = microphone.finishCapture()
        guard audio.count == 44 + (signal.count * 2 + long.count) * 2,
              finalChunk.samples == streamed.samples,
              microphone.drainStreamingAudio().samples.isEmpty else {
            throw ServiceError.message("Finishing did not preserve final streaming audio and full recording.")
        }
        microphone.capturing = true; microphone.streamingReadOffset = microphone.samples.count
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        microphone.cancelCapture()
        guard microphone.drainStreamingAudio().samples.isEmpty else {
            throw ServiceError.message("Cancelled streaming audio remained buffered.")
        }
    }

    @MainActor static func verifyPromptAudio() throws {
        let microphone = Microphone()
        microphone.capturing = true
        let signal: [Float] = [0, 0.5, -0.5, 1, -1]
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        guard microphone.drainSpeechAudio().samples.isEmpty else { throw ServiceError.message("Prompt audio ran while disabled.") }
        microphone.liveSpeech = true
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        let speech = microphone.drainSpeechAudio()
        guard speech.samples == signal, speech.sampleRate == 48000,
              microphone.samples == [0, 16383, -16383, 32767, -32767, 0, 16383, -16383, 32767, -32767],
              microphone.drainSpeechAudio().samples.isEmpty else { throw ServiceError.message("Live speech changed recording samples or replayed drained audio.") }
        let long = Array(repeating: Float(0), count: 48000 * 3)
        long.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        let bounded = microphone.drainSpeechAudio()
        guard bounded.samples.count == 96000, bounded.overflowed else { throw ServiceError.message("Prompt audio buffer is unbounded.") }
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        microphone.cancelCapture()
        guard microphone.drainSpeechAudio().samples.isEmpty, !microphone.liveSpeech else { throw ServiceError.message("Cancelled prompt audio remained active.") }
        microphone.capturing = true; microphone.liveSpeech = true
        signal.withUnsafeBufferPointer { microphone.capture($0.baseAddress!, count: $0.count) }
        let completed = microphone.finishCapture()
        guard completed.count == 44 + signal.count * 2, microphone.drainSpeechAudio().samples == signal,
              microphone.drainSpeechAudio().samples.isEmpty else { throw ServiceError.message("Finishing lost the final Speech buffer or changed recording samples.") }

    }

    @MainActor static func verifySpectrumCapture() throws {
        func fixture(_ frequency: Double) -> (levels: [Double], milliseconds: Double, frames: Int) {
            let microphone = Microphone()
            microphone.captureAudio = false
            microphone.capturing = true
            let signal = (0..<14400).map { Float(0.08 * sin(2 * .pi * frequency * Double($0) / 48000)) }
            let started = ProcessInfo.processInfo.systemUptime
            signal.withUnsafeBufferPointer { samples in
                for offset in stride(from: 0, to: samples.count, by: 256) {
                    microphone.capture(samples.baseAddress!.advanced(by: offset), count: min(256, samples.count - offset))
                }
            }
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            let result = (microphone.spectrum, elapsed, microphone.capturedFrameCount)
            microphone.cancelCapture()
            return result
        }
        let low = fixture(140), high = fixture(2200)
        guard low.frames == 14400, high.frames == 14400,
              low.levels[0] > high.levels[0] + 0.35,
              high.levels[4] > low.levels[4] + 0.35 else {
            throw ServiceError.message("The microphone callback did not publish independent frequency bands.")
        }
        let recording = Microphone()
        recording.capturing = true
        let signal: [Float] = [0, 0.5, -0.5, 1, -1]
        signal.withUnsafeBufferPointer { recording.capture($0.baseAddress!, count: $0.count) }
        guard recording.samples == [0, 16383, -16383, 32767, -32767] else {
            throw ServiceError.message("Spectrum analysis changed the recorded PCM samples.")
        }
        recording.cancelCapture()
        guard recording.spectrum.allSatisfy({ $0 == 0 }), recording.meter == 0 else {
            throw ServiceError.message("Stopped capture retained its live frequency levels.")
        }
        print(String(format: "Synthetic microphone callback: independent pitch bands, unchanged PCM, cleared stop state PASS. 300 ms of audio processed in %.2f / %.2f ms.", low.milliseconds, high.milliseconds))
    }
}
