import XCTest
@testable import S2TCore

final class ClassicBarPlacementTests: XCTestCase {
    let home = CGRect(x: 100, y: 300, width: 500, height: 60)
    let container = CGRect(x: 0, y: 0, width: 700, height: 720)

    func testEdgeAttachmentsPushInOppositeDirectionsAndReturnHome() {
        let left = CGRect(x: 80, y: 315, width: 40, height: 40)
        let right = CGRect(x: 580, y: 315, width: 40, height: 40)
        let a = ClassicBarPlacement.offset(home: home, obstacle: left, container: container, side: .left)
        let b = ClassicBarPlacement.offset(home: home, obstacle: right, container: container, side: .right)
        XCTAssertEqual(a, CGPoint(x: 34, y: 0))
        XCTAssertEqual(b, CGPoint(x: -34, y: 0))
        XCTAssertEqual(ClassicBarPlacement.offset(home: home, obstacle: left.offsetBy(dx: 0, dy: 200), container: container, side: .left, previous: a), .zero)
    }
    func testFloatingIndicatorMovesBarAboveOrBelowWithoutMovingHorizontally() {
        for y in [290.0, 340] {
            let obstacle = CGRect(x: 300, y: y, width: 112, height: 36)
            let offset = ClassicBarPlacement.offset(home: home, obstacle: obstacle, container: container, side: nil)
            XCTAssertEqual(offset.x, 0)
            XCTAssertEqual(offset.y > 0, y < home.midY)
            XCTAssertFalse(home.offsetBy(dx: offset.x, dy: offset.y).intersects(obstacle))
        }
    }
    func testRepeatedOverlapNeverAccumulatesAndFollowingTheMovedBarReturnsHome() {
        let obstacle = CGRect(x: 300, y: 320, width: 112, height: 36)
        var offset = ClassicBarPlacement.offset(home: home, obstacle: obstacle, container: container, side: nil)
        let expected = offset
        for _ in 0..<200 {
            offset = ClassicBarPlacement.offset(home: home, obstacle: obstacle, container: container, side: nil, previous: offset)
            XCTAssertEqual(offset, expected)
        }
        let following = obstacle.offsetBy(dx: 0, dy: offset.y * 2)
        XCTAssertEqual(ClassicBarPlacement.offset(home: home, obstacle: following, container: container, side: nil, previous: offset), .zero)
    }
    func testResumingAfterIdleStartsWithOneFrameOfMotion() {
        var motion = ClassicBarMotion()
        motion.update(time: 0, reducedMotion: false)
        motion.target = CGPoint(x: 280, y: 0)
        motion.resume(time: 100)
        XCTAssertEqual(motion.position, .zero)
        motion.update(time: 100 + 1.0 / 60, reducedMotion: false)
        XCTAssertGreaterThan(motion.position.x, 0)
        XCTAssertLessThan(motion.position.x, 15)
    }
    func testReversingMotionPreservesCurrentPositionAndVelocity() {
        var motion = ClassicBarMotion()
        motion.target = CGPoint(x: 40, y: 0)
        for frame in 0...8 { motion.update(time: Double(frame) / 60, reducedMotion: false) }
        let position = motion.position, velocity = motion.velocity
        motion.target = CGPoint(x: -40, y: 0)
        motion.update(time: 8.0 / 60, reducedMotion: false)
        XCTAssertEqual(motion.position.x, position.x, accuracy: 1e-10)
        XCTAssertEqual(motion.velocity.x, velocity.x, accuracy: 1e-10)
        for frame in 9...100 { motion.update(time: Double(frame) / 60, reducedMotion: false) }
        XCTAssertTrue(motion.settled)
        motion.target = .zero
        motion.update(time: 2, reducedMotion: true)
        XCTAssertEqual(motion.position, .zero)
    }
}
