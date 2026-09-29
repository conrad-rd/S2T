import XCTest
@testable import S2TCore

final class NotchSpeechResponseTests: XCTestCase {
    private let bass = [0.8, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]

    func testOneFrameMicrophoneGapDoesNotBlankOrSnapTheNotch() {
        var response = NotchSpeechResponse()
        response.update(level: 0.45, bands: bass, time: 0, reducedMotion: false)
        let energy = response.energy, motion = response.distortion
        response.update(level: 0, bands: [], time: 1.0 / 60, reducedMotion: false)
        XCTAssertGreaterThan(response.energy, energy * 0.95)
        XCTAssertGreaterThan(abs(response.distortion.horizontal), abs(motion.horizontal) * 0.8)
    }

    func testShortSyllablePauseKeepsTheGlowSteady() {
        var response = NotchSpeechResponse()
        response.update(level: 0.45, bands: bass, time: 0, reducedMotion: false)
        let energy = response.energy
        for frame in 1...7 {
            response.update(level: 0, bands: [], time: Double(frame) / 60, reducedMotion: false)
            XCTAssertGreaterThan(response.energy, energy * 0.95)
        }
        response.update(level: 0.45, bands: bass, time: 8.0 / 60, reducedMotion: false)
        XCTAssertEqual(response.energy, energy, accuracy: 0.001)
    }

    func testSpeechJitterStaysBoundedAndRealSilenceClears() {
        var response = NotchSpeechResponse()
        response.update(level: 0.45, bands: bass, time: 0, reducedMotion: false)
        var previous = response.energy
        var largestJump = 0.0
        let levels = [0.27, 0.48, 0.32, 0.52, 0, 0.42]
        for frame in 1...120 {
            let level = levels[frame % levels.count]
            response.update(level: level, bands: level == 0 ? [] : bass, time: Double(frame) / 60, reducedMotion: false)
            largestJump = max(largestJump, abs(response.energy - previous))
            previous = response.energy
        }
        XCTAssertLessThan(largestJump, 0.10)
        for frame in 121...155 {
            response.update(level: 0, bands: [], time: Double(frame) / 60, reducedMotion: false)
            XCTAssertLessThanOrEqual(response.energy, previous + 0.000001)
            previous = response.energy
        }
        XCTAssertEqual(response.energy, 0)
        XCTAssertEqual(response.distortion, .identity)
        print("Synthetic notch speech maximum frame jump: \(largestJump)")
    }

    func testRepeatedFrameIsStableAndProcessingClearsImmediately() {
        var response = NotchSpeechResponse()
        response.update(level: 0.45, bands: bass, time: 1, reducedMotion: false)
        let energy = response.energy
        response.update(level: 0, bands: [], time: 1, reducedMotion: false)
        XCTAssertEqual(response.energy, energy)
        response.update(level: 0.45, bands: bass, time: 1, reducedMotion: false, active: false)
        XCTAssertEqual(response.energy, 0)
        XCTAssertEqual(response.distortion, .identity)
        response.update(level: 0.45, bands: bass, time: 2, reducedMotion: true)
        XCTAssertGreaterThan(response.energy, 0)
        XCTAssertEqual(response.distortion, .identity)
    }

    func testSpeechOnsetEasesInWithoutOvershoot() {
        var response = NotchSpeechResponse()
        response.update(level: 0.06, bands: [], time: 0, reducedMotion: false)
        response.update(level: 0.06, bands: [], time: 1.0 / 60, reducedMotion: false)
        var previous = response.energy
        var steps: [Double] = []
        for frame in 2...40 {
            response.update(level: 0.6, bands: bass, time: Double(frame) / 60, reducedMotion: false)
            XCTAssertGreaterThanOrEqual(response.energy, previous)
            steps.append(response.energy - previous)
            previous = response.energy
        }
        let target = pow((0.6 - 0.06) / 0.94, 0.7)
        XCTAssertLessThanOrEqual(previous, target + 0.000001)
        XCTAssertGreaterThan(previous, target * 0.95)
        // Continuous velocity: the glow accelerates into a new level instead of jumping.
        XCTAssertLessThan(steps[0], steps[1])
        XCTAssertLessThan(steps[0], 0.08)
    }

    func testSpringStepIsExactAcrossFrameRates() {
        var coarse = (0.0, 0.0)
        coarse = NotchSpeechResponse.spring(value: coarse.0, velocity: coarse.1, target: 1, rate: 27, elapsed: 0.04)
        var fine = (0.0, 0.0)
        for _ in 0..<4 { fine = NotchSpeechResponse.spring(value: fine.0, velocity: fine.1, target: 1, rate: 27, elapsed: 0.01) }
        XCTAssertEqual(coarse.0, fine.0, accuracy: 1e-12)
        XCTAssertEqual(coarse.1, fine.1, accuracy: 1e-9)
    }
}
