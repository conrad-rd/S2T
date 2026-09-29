import XCTest
@testable import S2TCore

final class ClassicDockMotionTests: XCTestCase {
    func testDockingTakesIntermediateFramesAndSettlesWithoutOvershoot() {
        var motion = ClassicDockMotion()
        motion.update(attached: false, time: 0, reducedMotion: false)
        var previous = 0.0
        for frame in 1...60 {
            motion.update(attached: true, time: Double(frame) / 60, reducedMotion: false)
            XCTAssertGreaterThanOrEqual(motion.amount, previous)
            XCTAssertLessThanOrEqual(motion.amount, 1)
            if frame == 6 { XCTAssertTrue((0.2...0.9).contains(motion.amount)) }
            previous = motion.amount
        }
        XCTAssertEqual(motion.amount, 1)
    }

    func testReversalKeepsPositionAndVelocityAtTheSameInstant() {
        var motion = ClassicDockMotion()
        for frame in 0...8 { motion.update(attached: true, time: Double(frame) / 60, reducedMotion: false) }
        let before = motion
        motion.update(attached: false, time: 8.0 / 60, reducedMotion: false)
        XCTAssertEqual(motion.amount, before.amount, accuracy: 1e-12)
        XCTAssertEqual(motion.velocity, before.velocity, accuracy: 1e-12)
        for frame in 9...90 { motion.update(attached: false, time: Double(frame) / 60, reducedMotion: false) }
        XCTAssertEqual(motion.amount, 0)
    }

    func testAttachmentThresholdDoesNotFlickerAtTheScreenEdge() {
        let screen = CGRect(x: -1200, y: 0, width: 1200, height: 800)
        XCTAssertEqual(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: -1166, y: 400), screen: screen), .left)
        XCTAssertEqual(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: -1140, y: 400), screen: screen, attached: .left), .left)
        XCTAssertNil(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: -1120, y: 400), screen: screen, attached: .left))
    }

    func testReducedMotionResolvesImmediately() {
        var motion = ClassicDockMotion()
        motion.update(attached: true, time: 0, reducedMotion: true)
        XCTAssertEqual(motion.amount, 1)
        motion.update(attached: false, time: 0.01, reducedMotion: true)
        XCTAssertEqual(motion.amount, 0)
    }
}
