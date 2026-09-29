import XCTest
@testable import S2TCore

final class ClassicLiquidMotionTests: XCTestCase {
    func testMovementRespondsGraduallyAndSettlesAfterRelease() {
        var motion = ClassicLiquidMotion()
        motion.update(point: .zero, time: 0, reducedMotion: false)
        motion.update(point: CGPoint(x: 15, y: 0), time: 1.0 / 60, reducedMotion: false)
        XCTAssertGreaterThan(motion.stretch.x, 0)
        XCTAssertLessThan(motion.stretch.x, 0.1)
        for frame in 2...20 {
            motion.update(point: CGPoint(x: frame * 15, y: 0), time: Double(frame) / 60, reducedMotion: false)
        }
        XCTAssertGreaterThan(motion.stretch.x, 0.6)
        let before = motion.stretch.x
        motion.update(point: CGPoint(x: 285, y: 0), time: 21.0 / 60, reducedMotion: false)
        XCTAssertLessThan(abs(motion.stretch.x - before), 0.1)
        for frame in 22...100 {
            motion.update(point: CGPoint(x: 285, y: 0), time: Double(frame) / 60, reducedMotion: false)
        }
        XCTAssertEqual(motion.stretch.x, 0, accuracy: 0.0001)
    }

    func testReducedMotionAndResumingDoNotStretch() {
        var motion = ClassicLiquidMotion()
        motion.update(point: .zero, time: 0, reducedMotion: false)
        motion.update(point: CGPoint(x: 500, y: 200), time: 0.016, reducedMotion: true)
        XCTAssertEqual(motion.stretch, .zero)
        motion.update(point: .zero, time: 1, reducedMotion: false)
        XCTAssertEqual(motion.stretch, .zero)
    }
}
