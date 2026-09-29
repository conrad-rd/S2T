import Accelerate
import Foundation

extension WaveAudio {
    /// Speech models analyze 16 kHz audio. Uploading 48 kHz microphone PCM only triples the bytes.
    public static let speechUploadRate = 16_000

    /// Canonical mono PCM resampled to 16 kHz for cloud speech upload. The result is deterministic,
    /// so a retried recording keeps its exact request identity. Other input is returned unchanged.
    public static func speechUpload(_ audio: Data) -> Data {
        guard audio.count >= 44,
              String(data: audio.prefix(4), encoding: .ascii) == "RIFF",
              String(data: audio[8..<16], encoding: .ascii) == "WAVEfmt ",
              String(data: audio[36..<40], encoding: .ascii) == "data" else { return audio }
        func word(_ offset: Int, _ size: Int) -> Int {
            (0..<size).reduce(0) { $0 | Int(audio[audio.startIndex + offset + $1]) << ($1 * 8) }
        }
        let rate = word(24, 4)
        guard word(16, 4) == 16, word(20, 2) == 1, word(22, 2) == 1, word(34, 2) == 16,
              word(28, 4) == rate * 2, word(40, 4) == audio.count - 44, (audio.count - 44) % 2 == 0,
              rate > speechUploadRate, rate <= 192_000 else { return audio }
        var samples = [Int16](repeating: 0, count: (audio.count - 44) / 2)
        _ = samples.withUnsafeMutableBytes { audio.dropFirst(44).copyBytes(to: $0) }
        for index in samples.indices { samples[index] = Int16(littleEndian: samples[index]) }
        return encode(samples: resample(samples, from: rate, to: speechUploadRate), sampleRate: UInt32(speechUploadRate))
    }

    /// Polyphase windowed-sinc resampler. Passband ends at 7.6 kHz; content above 8 kHz is removed before decimation.
    static func resample(_ input: [Int16], from inputRate: Int, to outputRate: Int) -> [Int16] {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = gcd(inputRate, outputRate)
        let up = outputRate / divisor, down = inputRate / divisor
        let count = input.count * up / down
        guard count > 0 else { return [] }
        let ratio = Double(inputRate) / Double(outputRate)
        let half = Int((16 * ratio).rounded(.up)), taps = 2 * half + 1
        let cutoff = 7_600 / Double(inputRate)
        let beta = 8.6, besselBeta = bessel(beta)
        var table = [Float](repeating: 0, count: up * taps)
        for phase in 0..<up {
            var sum = 0.0
            var row = [Double](repeating: 0, count: taps)
            for tap in 0..<taps {
                let distance = Double(phase) / Double(up) - Double(tap - half)
                let x = 2 * cutoff * distance
                let sinc = x == 0 ? 1 : sin(.pi * x) / (.pi * x)
                let position = distance / Double(half + 1)
                let window = abs(position) >= 1 ? 0 : bessel(beta * sqrt(1 - position * position)) / besselBeta
                row[tap] = sinc * window
                sum += row[tap]
            }
            for tap in 0..<taps { table[phase * taps + tap] = Float(row[tap] / sum) }
        }
        var padded = [Float](repeating: 0, count: input.count + 2 * half + 1)
        input.withUnsafeBufferPointer { source in
            padded.withUnsafeMutableBufferPointer { target in
                vDSP_vflt16(source.baseAddress!, 1, target.baseAddress! + half, 1, vDSP_Length(input.count))
            }
        }
        var output = [Int16](repeating: 0, count: count)
        padded.withUnsafeBufferPointer { signal in
            table.withUnsafeBufferPointer { filters in
                for index in 0..<count {
                    let position = index * down
                    let base = position / up, phase = position % up
                    var value: Float = 0
                    // Taps start `half` samples before `base`, which is offset `half` into the padded signal.
                    vDSP_dotpr(signal.baseAddress! + base, 1, filters.baseAddress! + phase * taps, 1, &value, vDSP_Length(taps))
                    output[index] = Int16(max(-32_768, min(32_767, value.rounded())))
                }
            }
        }
        return output
    }

    private static func bessel(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0
        for k in 1..<32 {
            term *= (x / (2 * Double(k))) * (x / (2 * Double(k)))
            sum += term
            if term < sum * 1e-12 { break }
        }
        return sum
    }
}
