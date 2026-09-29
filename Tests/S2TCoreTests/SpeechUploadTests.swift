import XCTest
@testable import S2TCore

final class SpeechUploadTests: XCTestCase {
    private func tone(rate: Int, seconds: Double, components: [(hz: Double, amplitude: Double)]) -> [Int16] {
        (0..<Int(Double(rate) * seconds)).map { index in
            let t = Double(index) / Double(rate)
            return Int16(components.reduce(0) { $0 + $1.amplitude * sin(2 * .pi * $1.hz * t) })
        }
    }

    /// Goertzel magnitude, normalized to the amplitude of a pure sine at `hz`.
    private func amplitude(_ samples: ArraySlice<Int16>, rate: Int, hz: Double) -> Double {
        let omega = 2 * Double.pi * hz / Double(rate), coefficient = 2 * cos(omega)
        var previous = 0.0, older = 0.0
        for sample in samples {
            let current = Double(sample) + coefficient * previous - older
            older = previous; previous = current
        }
        let power = previous * previous + older * older - coefficient * previous * older
        return 2 * sqrt(max(0, power)) / Double(samples.count)
    }

    private func decode(_ wave: Data) -> (rate: Int, samples: [Int16]) {
        let rate = Int(wave[24]) | Int(wave[25]) << 8 | Int(wave[26]) << 16 | Int(wave[27]) << 24
        let samples = stride(from: 44, to: wave.count - 1, by: 2).map { Int16(bitPattern: UInt16(wave[$0]) | UInt16(wave[$0 + 1]) << 8) }
        return (rate, samples)
    }

    func testFortyEightKilohertzSpeechUploadsAtSixteenKilohertzWithoutAliasing() throws {
        // 12 kHz is above the 8 kHz upload band and would alias to 4 kHz without filtering.
        let source = tone(rate: 48_000, seconds: 2, components: [(1_000, 8_000), (12_000, 8_000)])
        let wave = WaveAudio.encode(samples: source, sampleRate: 48_000)
        let upload = WaveAudio.speechUpload(wave)
        let (rate, samples) = decode(upload)
        XCTAssertEqual(rate, 16_000)
        XCTAssertEqual(samples.count, source.count / 3)
        XCTAssertEqual(upload.count, 44 + samples.count * 2)
        XCTAssertLessThan(Double(upload.count) / Double(wave.count), 0.34)
        let middle = samples[4_000..<28_000]
        XCTAssertEqual(amplitude(middle, rate: 16_000, hz: 1_000), 8_000, accuracy: 160)
        XCTAssertLessThan(amplitude(middle, rate: 16_000, hz: 4_000), 80)
        XCTAssertNoThrow(try WaveAudio.creditParts(upload))
        XCTAssertTrue(WaveAudio.supportsImmediateTranscription(upload))
    }

    func testUploadIsDeterministicForRetriesAndKeepsDuration() {
        let source = tone(rate: 44_100, seconds: 1.5, components: [(440, 5_000), (3_000, 3_000)])
        let wave = WaveAudio.encode(samples: source, sampleRate: 44_100)
        let first = WaveAudio.speechUpload(wave), second = WaveAudio.speechUpload(wave)
        XCTAssertEqual(first, second)
        let (rate, samples) = decode(first)
        XCTAssertEqual(rate, 16_000)
        XCTAssertEqual(Double(samples.count) / 16_000, 1.5, accuracy: 0.001)
        XCTAssertEqual(amplitude(samples[2_000..<22_000], rate: 16_000, hz: 440), 5_000, accuracy: 100)
        XCTAssertEqual(amplitude(samples[2_000..<22_000], rate: 16_000, hz: 3_000), 3_000, accuracy: 90)
    }

    func testLowRateAndUnsupportedAudioIsUnchanged() {
        let sixteen = WaveAudio.encode(samples: tone(rate: 16_000, seconds: 0.5, components: [(500, 1_000)]), sampleRate: 16_000)
        XCTAssertEqual(WaveAudio.speechUpload(sixteen), sixteen)
        let invalid = Data("not a wave file".utf8)
        XCTAssertEqual(WaveAudio.speechUpload(invalid), invalid)
        let silence = WaveAudio.encode(samples: [], sampleRate: 48_000)
        XCTAssertEqual(decode(WaveAudio.speechUpload(silence)).samples.count, 0)
    }

    func testLoudInputClipsInsteadOfWrapping() {
        let square = (0..<48_000).map { $0 / 24 % 2 == 0 ? Int16.max : Int16.min }
        let (_, samples) = decode(WaveAudio.speechUpload(WaveAudio.encode(samples: square, sampleRate: 48_000)))
        // Filter overshoot on a full-scale square wave must saturate, never wrap to the opposite sign.
        var saturated = 0
        for index in 1..<(samples.count - 1) {
            let before = Int(samples[index - 1]), after = Int(samples[index + 1]), value = Int(samples[index])
            if before > 20_000 && after > 20_000 { XCTAssertGreaterThan(value, 0) }
            if before < -20_000 && after < -20_000 { XCTAssertLessThan(value, 0) }
            if value == Int(Int16.max) || value == Int(Int16.min) { saturated += 1 }
        }
        XCTAssertGreaterThan(saturated, 0)
    }
}
