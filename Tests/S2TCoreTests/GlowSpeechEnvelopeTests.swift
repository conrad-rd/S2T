import XCTest
@testable import S2TCore

final class GlowSpeechEnvelopeTests: XCTestCase {
    func testMaximumSupportsFiveHundredPercent() {
        let settings = GlowResponseSettings(minimum: 0.3, maximum: 5)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 1, selected: 1.3, settings: settings), 5)
        XCTAssertEqual(GlowSpeechEnvelope.expansion(energy: 1, selected: 1.3, reducedMotion: false, settings: settings), 5.0 / 3)
        XCTAssertEqual(GlowResponseSettings(maximum: 8).maximum, 5)
    }

    func testCustomMinimumAndMaximumControlTheWholeResponse() {
        let settings = GlowResponseSettings(width: 0.5, minimum: 0.1, maximum: 1.4)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 0, selected: 1.3, settings: settings), 0.1, accuracy: 0.000001)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 0.5, selected: 1.3, settings: settings), 0.75, accuracy: 0.000001)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 1, selected: 1.3, settings: settings), 1.4, accuracy: 0.000001)
        let constant = GlowResponseSettings(minimum: 0.6, maximum: 0.6)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 0, selected: 1.3, settings: constant), GlowSpeechEnvelope.gain(energy: 1, selected: 1.3, settings: constant))
        XCTAssertEqual(GlowResponseSettings(minimum: 1.5, maximum: 0.5).maximum, 1.5)
    }

    func testQuietAndLoudEndpointsAreRelativeToTheSelectedLevel() {
        for selected in [0.3, 0.8, 1.3] {
            XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 0, selected: selected), selected / 1.3 * 0.3, accuracy: 0.000001)
            XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 1, selected: selected), selected / 1.3 * 2, accuracy: 0.000001)
        }
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 1, selected: 0), 0)
    }

    func testLouderSpeechAlwaysIncreasesTheEffectWithoutClippingAtOne() {
        let gains = (0...100).map { GlowSpeechEnvelope.gain(energy: Double($0) / 100, selected: 1.3) }
        for (a, b) in zip(gains, gains.dropFirst()) { XCTAssertGreaterThan(b, a) }
        XCTAssertEqual(gains[50], 1.15, accuracy: 0.000001)
        XCTAssertEqual(gains[100], 2)
    }

    func testReduceMotionKeepsSizeFixedButAllowsBrightnessFeedback() {
        for energy in [0.0, 0.3, 0.8, 1] {
            XCTAssertEqual(GlowSpeechEnvelope.expansion(energy: energy, selected: 0.8, reducedMotion: true), 0.8 / 1.3)
            XCTAssertGreaterThan(GlowSpeechEnvelope.expansion(energy: energy, selected: 0.8, reducedMotion: false), 0)
        }
    }

    func testMeterNoiseAndInvalidValuesRemainBounded() {
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: -.infinity, selected: 1.3), 0.3)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: .nan, selected: 1.3), 0.3)
        XCTAssertEqual(GlowSpeechEnvelope.gain(energy: 5, selected: 1.3), 2)
    }
}
