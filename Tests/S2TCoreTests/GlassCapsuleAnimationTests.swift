import XCTest
@testable import S2TCore

final class GlassCapsuleAnimationTests: XCTestCase {
    func testEntranceRisesWithOneRestrainedSettle() {
        var animation = GlassCapsuleAnimation()
        animation.update(phase: .listening, energy: 0, time: 0, reducedMotion: false)
        XCTAssertLessThan(animation.offsetY, -8)
        XCTAssertTrue((0.91...0.94).contains(animation.scaleX))
        XCTAssertTrue((0.91...0.94).contains(animation.scaleY))
        var peakY = 0.0, peakSize = 1.0
        for frame in 1...42 {
            animation.update(phase: .listening, energy: 0, time: Double(frame) / 60, reducedMotion: false)
            peakY = max(peakY, animation.offsetY)
            peakSize = max(peakSize, animation.scaleX)
            if frame == 6 {
                XCTAssertGreaterThan(animation.offsetY, -3.2)
                XCTAssertGreaterThan(animation.scaleX, 0.97)
            }
        }
        XCTAssertEqual(peakY, 0)
        XCTAssertTrue((1.002...1.012).contains(peakSize))
        XCTAssertEqual(animation.offsetY, 0, accuracy: 0.03)
        XCTAssertEqual(animation.scaleX, 1, accuracy: 0.002)
        XCTAssertEqual(animation.scaleY, 1, accuracy: 0.002)
    }

    func testChangingPhaseDoesNotReplayEntrance() {
        var animation = GlassCapsuleAnimation()
        animation.update(phase: .listening, energy: 0, time: 0, reducedMotion: false)
        animation.update(phase: .processing, energy: 0, time: 2, reducedMotion: false)
        XCTAssertEqual(animation.offsetY, 0, accuracy: 0.0001)
        XCTAssertEqual(animation.scaleX, 1, accuracy: 0.0001)
    }

    func testMotionRemainsSmallAndCompletionSettles() {
        var animation = GlassCapsuleAnimation()
        for frame in 0..<600 {
            let phase: GlassCapsulePhase = frame < 120 ? .listening : frame < 360 ? .processing : .success
            animation.update(phase: phase, energy: frame.isMultiple(of: 8) ? 1 : 0.3,
                time: Double(frame) / 60, reducedMotion: false)
            XCTAssertTrue((0.91...1.025).contains(animation.scaleX))
            XCTAssertTrue((0.91...1.025).contains(animation.scaleY))
            XCTAssertTrue((-10...0).contains(animation.offsetY))
            XCTAssertTrue((0...1).contains(animation.blend))
        }
        XCTAssertEqual(animation.scaleX, 1, accuracy: 0.0001)
        XCTAssertEqual(animation.scaleY, 1, accuracy: 0.0001)
    }
    func testPhaseTransitionsAndReducedMotion() {
        var animation = GlassCapsuleAnimation()
        animation.update(phase: .listening, energy: 1, time: 0, reducedMotion: false)
        animation.update(phase: .processing, energy: 1, time: 1, reducedMotion: false)
        XCTAssertEqual(animation.previousPhase, .listening)
        XCTAssertEqual(animation.blend, 0)
        animation.update(phase: .success, energy: 1, time: 1.1, reducedMotion: true)
        XCTAssertEqual(animation.previousPhase, .processing)
        XCTAssertEqual(animation.blend, 1)
        XCTAssertEqual(animation.scaleX, 1)
        XCTAssertEqual(animation.scaleY, 1)
        XCTAssertEqual(animation.offsetY, 0)
    }
}
