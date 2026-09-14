import XCTest
@testable import S2TCore

final class AudioEnvelopeTests: XCTestCase {
    func testSpeechOnsetReachesNinetyPercentWithinTwentyMilliseconds() {
        var envelope = AudioEnvelope()
        for _ in 0..<3 { _ = envelope.update(rms: 0.1, peak: 0.2, duration: 256.0 / 48000) }
        XCTAssertGreaterThan(envelope.level, 0.90)
    }
    func testSilenceFallsBelowTenPercentWithinOneHundredFiftyMilliseconds() {
        var envelope = AudioEnvelope()
        _ = envelope.update(rms: 0.5, peak: 0.8, duration: 0.1)
        _ = envelope.update(rms: 0, peak: 0, duration: 0.15)
        XCTAssertLessThan(envelope.level, 0.1)
    }
    func testSmoothingDoesNotDependOnDeviceBufferSize() {
        var small = AudioEnvelope()
        var large = AudioEnvelope()
        for _ in 0..<16 { _ = small.update(rms: 0.03, peak: 0.05, duration: 256.0 / 48000) }
        for _ in 0..<4 { _ = large.update(rms: 0.03, peak: 0.05, duration: 1024.0 / 48000) }
        XCTAssertEqual(small.level, large.level, accuracy: 0.00001)
    }
    func testOrdinarySpeechProducesMoreVisibleFeedbackThanSilence() {
        var envelope = AudioEnvelope()
        XCTAssertEqual(envelope.update(rms: 0, peak: 0, duration: 1), 0)
        XCTAssertGreaterThan(envelope.update(rms: 0.03, peak: 0.05, duration: 0.02), 0.6)
        XCTAssertLessThanOrEqual(envelope.update(rms: 1, peak: 1, duration: 1), 1)
    }
}
