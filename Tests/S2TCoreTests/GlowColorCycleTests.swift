import XCTest
@testable import S2TCore

final class GlowColorCycleTests: XCTestCase {
    func testSpeedChangesPreservePhaseAndZeroStopsMovement() {
        let clock = GlowColorCycleClock()
        XCTAssertEqual(clock.sample(time: 0, speed: 0.1), 0)
        XCTAssertEqual(clock.sample(time: 2, speed: 0.1), 2)
        XCTAssertEqual(clock.sample(time: 2, speed: 0), 2)
        XCTAssertEqual(clock.sample(time: 20, speed: 0), 2)
        XCTAssertEqual(clock.sample(time: 20, speed: 1), 2)
        XCTAssertEqual(clock.sample(time: 20 + 0.5, speed: 1), 7, accuracy: 0.000001)
        XCTAssertEqual(clock.sample(time: 20 + 1, speed: 1), 2, accuracy: 0.000001)
    }

    func testSpeedPersistsAndOlderPreferencesKeepCurrentDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: Data("{}".utf8)).gradientSpeed, 0.1)
        for speed in [0.0, 0.1, 0.5, 1] {
            let tuning = GlowTuning(gradientSpeed: speed)
            XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(tuning)).normalized.gradientSpeed, speed)
        }
        XCTAssertEqual(GlowTuning(gradientSpeed: -1).gradientSpeed, 0)
        XCTAssertEqual(GlowTuning(gradientSpeed: 3).gradientSpeed, 1)
        XCTAssertEqual(GlowTuning(gradientSpeed: .infinity).gradientSpeed, 0.1)
    }

    func testFullTurnAndSmoothWrapAtEveryPosition() {
        for position in stride(from: -0.4, through: 1.4, by: 0.01) {
            let start = GlowColorCycle.color(position: position, time: 0)
            let end = GlowColorCycle.color(position: position, time: GlowColorCycle.duration)
            let before = GlowColorCycle.color(position: position, time: GlowColorCycle.duration - 1.0 / 60)
            let after = GlowColorCycle.color(position: position, time: 1.0 / 60)
            for channel in 0..<3 {
                XCTAssertEqual(start[channel], end[channel], accuracy: 0.000001)
                XCTAssertLessThan(abs(after[channel] - before[channel]), 0.025)
                XCTAssertTrue((0...1).contains(start[channel]))
            }
        }
    }

    func testCycleVisitsTheExistingPaletteInOrder() {
        let expected = [SIMD3<Double>(142, 0, 255), SIMD3<Double>(0, 93, 255),
                        SIMD3<Double>(253, 90, 189), SIMD3<Double>(255, 0, 250)]
        for index in expected.indices {
            XCTAssertEqual(GlowColorCycle.color(position: 0, time: Double(index) * GlowColorCycle.duration / 4), expected[index] / 255)
        }
    }
}
