import XCTest
@testable import S2TCore

final class GlowBlurResponseTests: XCTestCase {
    func testBlurIsStrongerAtLowAmountsAndBoundedAtHighAmounts() {
        XCTAssertEqual(GlowSpeechEnvelope.blurGain(0), 0)
        XCTAssertGreaterThan(GlowSpeechEnvelope.blurGain(0.3), 0.9)
        XCTAssertEqual(GlowSpeechEnvelope.blurGain(1), 1.5)
        XCTAssertLessThan(GlowSpeechEnvelope.blurGain(5), 2)
        let gains = (0...500).map { GlowSpeechEnvelope.blurGain(Double($0) / 100) }
        for (a, b) in zip(gains, gains.dropFirst()) {
            XCTAssertGreaterThan(b, a)
            XCTAssertLessThan(b - a, 0.06)
        }
        XCTAssertEqual(GlowSpeechEnvelope.blurGain(.nan), 0)
    }
    func testAmountDoesNotResizeThePanelOrCreateAJumpNearFourHundredPercent() {
        let sizes = (0...500).map { GlowResponseSettings(maximum: Double($0) / 100).paddingScale }
        XCTAssertTrue(sizes.allSatisfy { $0 == sizes[0] })
        let expansions = (0...500).map {
            GlowSpeechEnvelope.expansion(energy: 1, selected: 1.3, reducedMotion: false,
                settings: .init(minimum: 0, maximum: Double($0) / 100))
        }
        XCTAssertEqual(expansions[0], 0)
        XCTAssertEqual(expansions[100], 1)
        XCTAssertGreaterThan(expansions[30], 0.4)
        XCTAssertLessThan(expansions[500], 2)
        for (a, b) in zip(expansions, expansions.dropFirst()) {
            XCTAssertGreaterThan(b, a)
            XCTAssertLessThan(b - a, 0.025)
        }
    }

    func testFractionalInputBoundsAlwaysUseTopDownCoordinates() {
        let field = CGRect(x: 123.15, y: 85.2, width: 600.45, height: 71.3)
        for scale in [1.0, 1.4, 2.5] {
            let geometry = InputOutlineGeometry(field: field, paddingScale: scale,
                displayFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169))
            let local = geometry.outlineRect
            XCTAssertEqual(geometry.windowFrame.minX + local.minX, field.minX, accuracy: 0.000001)
            XCTAssertEqual(geometry.windowFrame.maxY - local.maxY, field.minY, accuracy: 0.000001)
        }
    }
}
