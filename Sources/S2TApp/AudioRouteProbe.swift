import AVFoundation
import CoreAudio
import Foundation

@MainActor enum AudioRouteProbe {
    static func run() async {
        let inputs = AudioInputs(observe: false)
        print("Automatic input: \(inputs.defaultName)")
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            print("BLOCKED: Microphone permission is not already granted. No permission prompt was opened.")
            exit(2)
        }
        let microphone = Microphone()
        var lastTick = ProcessInfo.processInfo.systemUptime
        var worstGap = 0.0
        let heartbeat = Timer(timeInterval: 0.005, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            worstGap = max(worstGap, (now - lastTick) * 1000)
            lastTick = now
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        defer { heartbeat.invalidate() }
        defer { microphone.cancel() }
        do {
            let before = try output()
            print("Output before: device \(before.device), \(before.rate) Hz, \(before.channels) channels")
            for iteration in 1...3 {
                let startTime = ProcessInfo.processInfo.systemUptime
                try await microphone.start(captureAudio: false)
                let startMS = (ProcessInfo.processInfo.systemUptime - startTime) * 1000
                try await Task.sleep(nanoseconds: 400_000_000)
                let during = try output()
                let frames = microphone.capturedFrameCount
                let stopTime = ProcessInfo.processInfo.systemUptime
                microphone.cancel()
                await microphone.waitUntilStopped()
                let stopMS = (ProcessInfo.processInfo.systemUptime - stopTime) * 1000
                print(String(format: "Audio lifecycle cycle %d: start %.2f ms, stop %.2f ms off main thread", iteration, startMS, stopMS))
                try await Task.sleep(nanoseconds: 150_000_000)
                let after = try output()
                guard before == during, before == after, frames > 0 else {
                    throw NSError(domain: "AudioRouteProbe", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "Cycle \(iteration) failed: frames=\(frames), during=\(during), after=\(after)"])
                }
                print("PASS cycle \(iteration): \(frames) input frames, output device/rate/channels unchanged during and after capture")
            }
            print(String(format: "Main run-loop worst heartbeat gap during three cycles: %.2f ms", worstGap))
            let opening = Task { try await microphone.start(captureAudio: false) }
            try await Task.sleep(nanoseconds: 1_000_000)
            microphone.cancel()
            try await opening.value
            await microphone.waitUntilStopped()
            let stoppedFrames = microphone.capturedFrameCount
            try await Task.sleep(nanoseconds: 50_000_000)
            guard microphone.capturedFrameCount == stoppedFrames, microphone.meter == 0 else {
                throw NSError(domain: "AudioRouteProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cancel during startup left the microphone running"])
            }
            try await microphone.start(captureAudio: false)
            try await Task.sleep(nanoseconds: 100_000_000)
            guard microphone.capturedFrameCount > 0 else {
                throw NSError(domain: "AudioRouteProbe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Microphone did not restart after cancelling startup"])
            }
            microphone.cancel()
            await microphone.waitUntilStopped()
            guard try output() == before else {
                throw NSError(domain: "AudioRouteProbe", code: 4, userInfo: [NSLocalizedDescriptionKey: "Output changed after cancelling and restarting input"])
            }
            print("PASS: cancellation during device startup releases input; immediate restart captures frames; output stays unchanged. No audio samples retained.")
        } catch {
            print("FAIL: \(error.localizedDescription)")
            microphone.cancel()
            exit(1)
        }
    }

    private struct Output: Equatable {
        let device: AudioDeviceID
        let rate: Float64
        let channels: UInt32
    }

    private static func output() throws -> Output {
        var device: AudioDeviceID = 0
        var rate: Float64 = 0
        try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, value: &device)
        try read(device, kAudioDevicePropertyNominalSampleRate, value: &rate)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size))
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage))
        let channels = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        return Output(device: device, rate: rate, channels: channels)
    }

    private static func read<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, value: inout T) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer))
        }
    }

    private static func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
