import XCTest
@testable import S2TCore

final class GlassWaveformTests: XCTestCase {
    func testBounceIsSmallAndSettles() {
        var motion = GlassWaveformMotion()
        var peak = 0.0
        for _ in 0..<120 {
            motion.update(bands: [1, 0, 0, 0, 0, 0, 0], delta: 1.0 / 60)
            peak = max(peak, motion.values[0])
            XCTAssertEqual(motion.values[1], 0)
        }
        XCTAssertGreaterThan(peak, 1.005)
        XCTAssertLessThan(peak, 1.06)
        XCTAssertEqual(motion.values[0], 1, accuracy: 0.0001)
        for _ in 0..<120 { motion.update(bands: [], delta: 1.0 / 60) }
        XCTAssertEqual(motion.values[0], 0, accuracy: 0.0001)
    }

    func testReversalPreservesMomentumAndFrameRateDoesNotChangeMotion() {
        var fast = GlassWaveformMotion(), slow = GlassWaveformMotion()
        for _ in 0..<12 { fast.update(bands: [0.7], delta: 1.0 / 120) }
        for _ in 0..<6 { slow.update(bands: [0.7], delta: 1.0 / 60) }
        XCTAssertEqual(fast.values[0], slow.values[0], accuracy: 0.000001)
        let before = fast.values[0]
        fast.update(bands: [0], delta: 1.0 / 1000)
        XCTAssertGreaterThan(fast.values[0], before)
        XCTAssertLessThan(fast.values[0] - before, 0.01)
    }

    func testReducedMotionAndGeometryStayBounded() {
        var motion = GlassWaveformMotion()
        motion.update(bands: [1, 0.5, .nan, .infinity, -1, 2], delta: 1, reducedMotion: true)
        XCTAssertEqual(motion.values, [1, 0.5, 0, 0, 0, 1, 0])
        for index in 0..<7 {
            let bar = motion.bar(at: index)
            XCTAssertEqual(bar.lean, 0)
            XCTAssertEqual(bar.lift, 0)
        }
        for frame in 0..<300 {
            motion.update(bands: (0..<7).map { Double((frame + $0) % 3) }, delta: 1.0 / 60)
            for index in 0..<7 {
                let bar = motion.bar(at: index)
                XCTAssertTrue((5...42).contains(bar.height))
                XCTAssertTrue((4.5...6.5).contains(bar.width))
                XCTAssertLessThanOrEqual(abs(bar.lean), 0.8)
                XCTAssertLessThanOrEqual(abs(bar.lift), 0.6)
                let path = bar.path(center: .zero)
                XCTAssertTrue(path.contains(.zero))
                XCTAssertLessThan(path.boundingBoxOfPath.width, 8)
            }
        }
    }
}
