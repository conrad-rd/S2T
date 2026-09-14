import XCTest
@testable import S2TCore

final class ProcessingSweepTests: XCTestCase {
    func testOneContinuousSweepUsesBottomColorsAndWraps() {
        let orbit = ProcessingSweep.orbitStops
        XCTAssertEqual(orbit.dropLast().map(\.rgb), ProcessingSweep.stops.map(\.rgb))
        XCTAssertEqual(orbit.dropLast().map(\.opacity), ProcessingSweep.stops.map(\.opacity))
        XCTAssertEqual(orbit[orbit.count - 2].position, 0.3, accuracy: 0.000001)
        XCTAssertEqual(orbit.first?.opacity, 0)
        XCTAssertEqual(orbit.last?.opacity, 0)
        XCTAssertEqual(orbit.last?.position, 1)
        let lit = orbit.indices.filter { orbit[$0].opacity > 0 }
        XCTAssertEqual(lit, Array(1...5), "Only one uninterrupted light arc may orbit the input.")
        XCTAssertNotEqual(ProcessingSweep.phase(time: 0, reducedMotion: false), ProcessingSweep.phase(time: 0.7, reducedMotion: false))
        XCTAssertEqual(ProcessingSweep.phase(time: 0, reducedMotion: false), ProcessingSweep.phase(time: 2.8, reducedMotion: false))
        XCTAssertEqual(ProcessingSweep.phase(time: 0, reducedMotion: true), ProcessingSweep.phase(time: 20, reducedMotion: true))
    }
}
