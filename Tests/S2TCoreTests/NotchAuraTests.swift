import XCTest
@testable import S2TCore

final class NotchAuraTests: XCTestCase {
    func testEasedTailSlowsDownBeforeReachingZero() {
        let samples = (0...100).map { NotchAura.easedCoverage(distance: Double($0), extent: 100) }
        XCTAssertEqual(samples[0], 1)
        XCTAssertEqual(samples[100], 0)
        XCTAssertLessThan(samples[25], 0.5)
        for index in 1..<99 {
            let earlierDrop = samples[index - 1] - samples[index]
            let laterDrop = samples[index] - samples[index + 1]
            XCTAssertGreaterThanOrEqual(earlierDrop, laterDrop)
            XCTAssertGreaterThanOrEqual(laterDrop, 0)
        }
        XCTAssertLessThan(samples[99], 0.00001)
    }

    func testBlurRemainsSubtleWithAnExtendedColorTail() {
        XCTAssertEqual(NotchAura.maximumBlurRadius, 12)
        for strength in [0.3, 1.0, 1.3] {
            XCTAssertGreaterThan(NotchAura.extent(strength: strength), 88)
            XCTAssertGreaterThan(NotchAura.blurCoverage(distance: 64, strength: strength), 0.015)
            XCTAssertGreaterThan(NotchAura.colorCoverage(distance: 64, strength: strength), 0.005)
            XCTAssertEqual(NotchAura.blurCoverage(distance: 110, strength: strength), 0)
        }
    }

    func testColorHasABroadShoulderAndEasesToTransparent() {
        XCTAssertEqual(NotchAura.maximumBlurRadius, 12)
        for strength in [0.3, 1.0, 1.3] {
            XCTAssertGreaterThan(NotchAura.colorCoverage(distance: 0, strength: strength), 0.5)
            XCTAssertGreaterThan(NotchAura.colorCoverage(distance: 24, strength: strength), 0.12)
            XCTAssertGreaterThan(NotchAura.colorCoverage(distance: 48, strength: strength), 0.025)
            XCTAssertLessThan(NotchAura.colorCoverage(distance: 80, strength: strength), 0.08)
            XCTAssertEqual(NotchAura.colorCoverage(distance: 116, strength: strength), 0)
            let samples = (0...116).map { NotchAura.colorCoverage(distance: Double($0), strength: strength) }
            for pair in zip(samples, samples.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.0, pair.1)
            }
            XCTAssertGreaterThan(NotchAura.blurCoverage(distance: 24, strength: strength), 0.15)
        }
    }

    func testQuietGlowAndBoundedSpeechMovement() {
        XCTAssertEqual(NotchAura.speechVisibility(energy: 0), 0)
        XCTAssertEqual(NotchAura.speechVisibility(energy: 0.4), 1)
        var previous = 0.0
        for index in 0...100 {
            let visibility = NotchAura.speechVisibility(energy: Double(index) / 100)
            XCTAssertTrue((previous...1).contains(visibility))
            previous = visibility
        }
        for band in 0..<7 {
            var bands = Array(repeating: 0.0, count: 7)
            bands[band] = 1
            let motion = NotchAura.deformation(GlowDistortion(bands: bands))
            XCTAssertLessThan(abs(motion.horizontal), 1.5)
            XCTAssertLessThan(abs(motion.vertical), 1)
        }
        XCTAssertEqual(NotchAura.deformation(.identity), .identity)
    }

    func testContourGlowFallsOutwardAndStaysBoundedAtBothModeSizes() {
        for extent in [24.0, NotchAura.extent(strength: 1.3)] {
            for position in [0.0, 0.33125, 0.5, 0.825, 1.0] {
                let values = (0...100).map {
                    GlowSweep.contourCoverage(distance: Double($0) / 100 * extent, extent: extent, position: position)
                }
                XCTAssertGreaterThan(values[0], 0.7)
                XCTAssertEqual(values.last!, 0)
                for pair in zip(values, values.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.0, pair.1)
                }
            }
            XCTAssertGreaterThan(GlowSweep.contourHighlight(distance: 0, extent: extent), 0.5)
            XCTAssertEqual(GlowSweep.contourHighlight(distance: extent, extent: extent), 0)
        }
    }

    func testFrequencyBalanceRedistributesLocalLight() {
        let bass = GlowDistortion(bands: [1, 0, 0, 0, 0, 0, 0])
        let treble = GlowDistortion(bands: [0, 0, 0, 0, 0, 0, 1])
        XCTAssertGreaterThan(NotchAura.illumination(at: 0.15, distortion: bass),
                             NotchAura.illumination(at: 0.15, distortion: treble) + 0.1)
        XCTAssertGreaterThan(NotchAura.illumination(at: 0.85, distortion: treble),
                             NotchAura.illumination(at: 0.85, distortion: bass) + 0.1)
        for index in 0...100 {
            let x = Double(index) / 100
            XCTAssertEqual(NotchAura.illumination(at: x, distortion: .identity), 0.82, accuracy: 0.000001)
            XCTAssertTrue((0.6...1).contains(NotchAura.illumination(at: x, distortion: bass)))
        }
    }

    func testEveryPaletteStopFitsBeneathTheNotch() {
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32,
            topLeft: CGRect(x: 0, y: 950, width: 660, height: 32),
            topRight: CGRect(x: 852, y: 950, width: 660, height: 32))
        let layout = TopGlowLayout(display: display)
        let bounds = NotchAura.paletteBounds(layout: layout)
        XCTAssertGreaterThanOrEqual(bounds.lowerBound, layout.notch!.minX)
        XCTAssertLessThanOrEqual(bounds.upperBound, layout.notch!.maxX)
        for stop in GlowSweep.stops {
            let x = bounds.lowerBound + (bounds.upperBound - bounds.lowerBound) * stop.position
            XCTAssertGreaterThan(layout.sideOpacity(at: x), 0.99)
        }
    }
}
