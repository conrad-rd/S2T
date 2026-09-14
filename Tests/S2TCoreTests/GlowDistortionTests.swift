import XCTest
@testable import S2TCore

final class GlowDistortionTests: XCTestCase {
    private func tone(_ frequency: Double) -> GlowDistortion {
        var analyzer = AudioSpectrum(sampleRate: 48000)
        for index in 0..<14400 {
            analyzer.consume(0.04 * sin(2 * .pi * frequency * Double(index) / 48000))
        }
        return GlowDistortion(bands: analyzer.levels)
    }

    func testEqualVolumePitchesShiftTheFieldInDifferentDirections() {
        XCTAssertLessThan(tone(140).horizontal, -1)
        XCTAssertGreaterThan(tone(2200).horizontal, 0.5)
    }

    func testGainDoesNotChangeTheDeformation() {
        let bands = [0.12, 0.2, 0.08, 0.15, 0.1, 0.18, 0.09]
        let quiet = GlowDistortion(bands: bands)
        let loud = GlowDistortion(bands: bands.map { $0 * 3 })
        XCTAssertEqual(quiet.horizontal, loud.horizontal, accuracy: 0.000001)
        XCTAssertEqual(quiet.vertical, loud.vertical, accuracy: 0.000001)
        XCTAssertEqual(quiet.stretch, loud.stretch, accuracy: 0.000001)
    }

    func testSilenceReducedMotionAndBoundedDeformation() {
        XCTAssertTrue(GlowDistortion(bands: []).isIdentity)
        XCTAssertTrue(GlowDistortion(bands: [0.8], reducedMotion: true).isIdentity)
        for band in 0..<7 {
            var bands = Array(repeating: 0.0, count: 7)
            bands[band] = 1
            let value = GlowDistortion(bands: bands)
            XCTAssertLessThanOrEqual(abs(value.horizontal), 3)
            XCTAssertLessThanOrEqual(abs(value.vertical), 2)
            XCTAssertLessThanOrEqual(abs(value.stretch), 1)
        }
        let invalid = GlowDistortion(bands: [.nan, .infinity, -1])
        XCTAssertTrue(invalid.isIdentity)
        let target = tone(140)
        let half = GlowDistortion.identity.blended(toward: target, fraction: 0.5)
        XCTAssertEqual(half.horizontal, target.horizontal / 2, accuracy: 0.000001)
    }
}
