import XCTest
@testable import S2TCore

final class GlowSweepTests: XCTestCase {
    func testMockFalloffHasBroadShoulderAndFeatheredTail() {
        for extent in [60.0, 84, 200] {
            let inner = GlowSweep.contourCoverage(distance: extent * 0.25, extent: extent)
            let middle = GlowSweep.contourCoverage(distance: extent * 0.5, extent: extent)
            let outer = GlowSweep.contourCoverage(distance: extent * 0.9, extent: extent)
            XCTAssertGreaterThan(inner, 0.5)
            XCTAssertTrue((0.15...0.3).contains(middle))
            XCTAssertLessThan(outer, 0.004)
            XCTAssertEqual(GlowSweep.contourCoverage(distance: extent, extent: extent), 0)
            XCTAssertGreaterThan(BackdropBlurFalloff.strength(middle), 0.2)
        }
        XCTAssertGreaterThan(InputOutlineGeometry.backdropExtent, 60)
        XCTAssertGreaterThan(InputOutlineGeometry.padding, InputOutlineGeometry.backdropExtent + 4)
    }

    func testAuthoredColorsAndBrightnessEndpoint() {
        XCTAssertEqual(GlowSweep.stops.map(\.position), [0, 0.33125, 0.825, 1])
        XCTAssertEqual(GlowSweep.stops[0].rgb, [142 / 255.0, 0, 1])
        XCTAssertEqual(GlowSweep.stops[3].rgb, [1, 0, 250 / 255.0])
        XCTAssertEqual(GlowSweep.mask(x: 0.5, depth: 1), 0.9882352948188782, accuracy: 0.000001)
    }

    func testMaximumIntensityDoesNotRequireLoudSpeech() {
        for crest in [3.0, 30, 55, 89] {
            XCTAssertGreaterThanOrEqual(GlowSweep.height(crest: crest, strength: 1.3), 200)
            XCTAssertLessThanOrEqual(GlowSweep.height(crest: crest, strength: 1.3), 240)
            XCTAssertGreaterThan(GlowSweep.height(crest: crest, strength: 1.3), GlowSweep.height(crest: crest, strength: 0.25))
        }
        for energy in [0.0, 0.3, 0.55, 1.0] {
            XCTAssertGreaterThanOrEqual(GlowSweep.brightness(energy: energy, strength: 1.3), 0.8)
            XCTAssertGreaterThan(GlowSweep.brightness(energy: energy, strength: 1.3), GlowSweep.brightness(energy: energy, strength: 0.25))
        }
    }

    func testCenterMatchesOriginalSweep() {
        for x in [0.25, 0.375, 0.5, 0.625, 0.75] {
            for depth in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let original = GlowSweep.vertical(depth) * GlowSweep.radial(hypot(x * 1080 - 540, depth * 1080 - 1080))
                XCTAssertEqual(GlowSweep.mask(x: x, depth: depth), original, accuracy: 0.000001)
            }
        }
    }

    func testContinuousBottomBandAndClearTop() {
        for x in [0.0, 0.125, 0.5, 0.875, 1] {
            XCTAssertEqual(GlowSweep.mask(x: x, depth: -1), 0, accuracy: 0.000001)
            XCTAssertEqual(GlowSweep.mask(x: x, depth: 0), 0, accuracy: 0.000001)
            if x == 0 || x == 1 {
                XCTAssertEqual(GlowSweep.mask(x: x, depth: 1), 0)
            } else {
                XCTAssertGreaterThan(GlowSweep.mask(x: x, depth: 1), 0.4)
            }
            var previous = 0.0
            for step in 0...100 {
                let value = GlowSweep.mask(x: x, depth: Double(step) / 100)
                XCTAssertGreaterThanOrEqual(value + 0.000001, previous)
                previous = value
            }
        }
        XCTAssertGreaterThan(GlowSweep.mask(x: 0.5, depth: 0.5), 0.15)
        XCTAssertLessThan(GlowSweep.mask(x: 0.5, depth: 0.5), 0.3)
        XCTAssertGreaterThan(GlowSweep.mask(x: 0.5, depth: 1), GlowSweep.mask(x: 0, depth: 1))
    }
}
