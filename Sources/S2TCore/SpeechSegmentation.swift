import Foundation

/// A boundary is chosen only after a sustained pause, with some silence left for the next section.
public struct SpeechSegmentation: Sendable {
    public private(set) var frames = 0
    private var sectionStart = 0
    private var quietFrames = 0
    private var hasSpeech = false

    public init() {}

    public mutating func append(_ samples: [Int16], sampleRate: Int) -> Int? {
        guard sampleRate > 0 else { return nil }
        for sample in samples {
            frames += 1
            if abs(Int(sample)) > 260 {
                quietFrames = 0
                hasSpeech = true
            } else { quietFrames += 1 }
        }
        // Avoid tiny requests, and never cut ongoing speech just to meet a timer.
        guard hasSpeech, frames - sectionStart >= sampleRate * 8,
              quietFrames >= sampleRate / 2 else { return nil }
        let end = frames - sampleRate / 4
        sectionStart = end
        quietFrames = sampleRate / 4
        hasSpeech = false
        return end
    }
}

extension WaveAudio {
    /// The saved boundaries refer to original microphone frames. Resample each section the same
    /// way during recording and retry so its bytes and payment identity never change.
    public static func segmentedSpeechParts(_ audio: Data, ends: [Int]) throws -> [Data] {
        _ = try captureSampleRate(audio)
        let frames = (audio.count - 44) / 2
        var previous = 0
        for end in ends {
            guard end > previous, end <= frames else { throw ServiceError.message("The saved speech sections do not match this recording.") }
            previous = end
        }
        var parts: [Data] = []
        var start = 0
        for end in ends + (previous < frames ? [frames] : []) {
            var part = Data(audio.prefix(44))
            let count = (end - start) * 2
            for (offset, value) in [(4, count + 36), (40, count)] {
                for byte in 0..<4 { part[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
            }
            part.append(audio[(44 + start * 2)..<(44 + end * 2)])
            parts.append(contentsOf: try creditParts(speechUpload(part)))
            start = end
        }
        return parts
    }
}
