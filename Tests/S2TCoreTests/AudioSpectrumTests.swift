import XCTest
@testable import S2TCore

final class AudioSpectrumTests: XCTestCase {
    private func tone(_ frequency: Double, rate: Double = 48000, amplitude: Double = 0.08) -> [Double] {
        var spectrum = AudioSpectrum(sampleRate: rate)
        for index in 0..<Int(rate * 0.3) {
            spectrum.consume(amplitude * sin(2 * .pi * frequency * Double(index) / rate))
        }
        return spectrum.levels
    }

    func testEqualVolumeDifferentPitchesMoveDifferentBands() {
        for (frequency, expected) in [(140.0, 0), (560.0, 2), (2200.0, 4), (7400.0, 6)] {
            let levels = tone(frequency)
            XCTAssertEqual(levels.indices.max(by: { levels[$0] < levels[$1] }), expected)
            XCTAssertGreaterThan(levels[expected], 0.65)
        }
        let bass = tone(140), treble = tone(2200)
        XCTAssertGreaterThan(bass[0] - treble[0], 0.35)
        XCTAssertGreaterThan(treble[4] - bass[4], 0.35)
    }

    func testMixturePreservesLowAndHighFrequencyContent() {
        var spectrum = AudioSpectrum(sampleRate: 48000)
        for index in 0..<14400 {
            let time = Double(index) / 48000
            spectrum.consume(0.06 * sin(2 * .pi * 140 * time) + 0.06 * sin(2 * .pi * 4400 * time))
        }
        XCTAssertGreaterThan(spectrum.levels[0], spectrum.levels[2] + 0.2)
        XCTAssertGreaterThan(spectrum.levels[5], spectrum.levels[2] + 0.2)
    }

    func testSilenceAndDeviceRates() {
        for rate in [8000.0, 16000, 44100, 48000, 96000] {
            let levels = tone(560, rate: rate)
            XCTAssertEqual(levels.indices.max(by: { levels[$0] < levels[$1] }), 2)
            XCTAssertTrue(levels.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
        var spectrum = AudioSpectrum(sampleRate: 48000)
        XCTAssertEqual(spectrum.levels, Array(repeating: 0, count: 7))
        for index in 0..<4800 { spectrum.consume(0.1 * sin(2 * .pi * 560 * Double(index) / 48000)) }
        for _ in 0..<14400 { spectrum.consume(0) }
        XCTAssertLessThan(spectrum.levels.max()!, 0.02)
    }
}
