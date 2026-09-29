import AVFoundation
import CoreAudio
import S2TCore

protocol MeetingSystemCapturing: AnyObject, Sendable {
    var audioStartTime: Double? { get }
    func start() async throws
    func stop() async
    func drain() throws -> (samples: [Int16], sampleRate: Int)
    func drainFinal() -> (samples: [Int16], sampleRate: Int, overflowed: Bool)
}

@available(macOS 14.2, *)
final class MeetingSystemAudio: MeetingSystemCapturing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.s2t.meeting.system-audio")
    private let lock = NSLock()
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var samples: [Int16] = []
    private var rate = 48000
    private var overflow = false
    private var firstTime: Double?
    var audioStartTime: Double? { lock.lock(); defer { lock.unlock() }; return firstTime }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.open(); continuation.resume() }
                catch { self.close(); continuation.resume(throwing: error) }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { self.close(); continuation.resume() }
        }
    }
    func drain() throws -> (samples: [Int16], sampleRate: Int) {
        lock.lock(); defer { lock.unlock() }
        guard !overflow else { throw ServiceError.message("Mac audio could not be saved fast enough. The meeting has stopped to avoid losing more audio.") }
        let result = (samples, rate); samples.removeAll(keepingCapacity: true); return result
    }
    func drainFinal() -> (samples: [Int16], sampleRate: Int, overflowed: Bool) {
        lock.lock(); defer { lock.unlock() }
        let result = (samples, rate, overflow)
        samples.removeAll(keepingCapacity: false)
        return result
    }
    private func open() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "S2T meeting audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout.size(ofValue: format))
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 0 else {
            throw ServiceError.message("This Mac audio format is not supported for meetings.")
        }
        rate = Int(format.mSampleRate)
        let spec: [String: Any] = [kAudioAggregateDeviceNameKey: "S2T meeting capture", kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
        try check(AudioHardwareCreateAggregateDevice(spec as CFDictionary, &device))
        try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, queue) { [weak self] _, input, inputTime, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = buffers.first, let data = buffer.mData else { return }
            let channels = max(1, Int(buffer.mNumberChannels))
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            let values = data.assumingMemoryBound(to: Float.self)
            self.lock.lock(); defer { self.lock.unlock() }
            if self.firstTime == nil { self.firstTime = AVAudioTime.seconds(forHostTime: inputTime.pointee.mHostTime) }
            guard self.samples.count + count <= self.rate * 10 else { self.overflow = true; return }
            for frame in 0..<count {
                var value: Float = 0
                for channel in 0..<channels { value += values[frame * channels + channel] / Float(channels) }
                self.samples.append(Int16(max(-1, min(1, value.isFinite ? value : 0)) * 32767))
            }
        })
        try check(AudioDeviceStart(device, io))
    }
    private func close() {
        if let io { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }
        io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw ServiceError.message("Mac audio capture could not start, code \(status). Allow S2T audio recording in System Settings, then try again.") }
    }
}
