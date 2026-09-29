import XCTest
@testable import S2TCore

final class GlowPhaseHandoffTests: XCTestCase {
    private let frame = 1.0 / 60

    func testListeningIntoProcessingEasesOverTheHandoff() {
        var handoff = GlowPhaseHandoff()
        XCTAssertEqual(handoff.progress(working: false, completing: false, time: 10, reducedMotion: false), 1)
        XCTAssertEqual(handoff.progress(working: true, completing: false, time: 10 + frame, reducedMotion: false), 0)
        XCTAssertFalse(handoff.fromWorking)
        var previous = 0.0
        var steps: [Double] = []
        var time = 10 + frame
        while time < 10 + frame + GlowPhaseHandoff.duration + frame {
            time += frame
            let value = handoff.progress(working: true, completing: false, time: time, reducedMotion: false)
            XCTAssertGreaterThanOrEqual(value, previous)
            steps.append(value - previous)
            previous = value
        }
        XCTAssertEqual(previous, 1)
        // Smoothstep starts and ends gently, fastest in the middle.
        XCTAssertLessThan(steps.first!, steps[steps.count / 2])
        XCTAssertLessThan(steps.last!, steps[steps.count / 2])
    }

    func testRepeatedTimestampIsStable() {
        var handoff = GlowPhaseHandoff()
        _ = handoff.progress(working: false, completing: false, time: 1, reducedMotion: false)
        _ = handoff.progress(working: true, completing: false, time: 1 + frame, reducedMotion: false)
        let first = handoff.progress(working: true, completing: false, time: 1.1, reducedMotion: false)
        XCTAssertEqual(handoff.progress(working: true, completing: false, time: 1.1, reducedMotion: false), first)
    }

    func testProcessingIntoCompletionFadesButANewSessionCuts() {
        var handoff = GlowPhaseHandoff()
        _ = handoff.progress(working: true, completing: false, time: 1, reducedMotion: false)
        XCTAssertEqual(handoff.progress(working: false, completing: true, time: 1 + frame, reducedMotion: false), 0)
        XCTAssertTrue(handoff.fromWorking)

        var restart = GlowPhaseHandoff()
        _ = restart.progress(working: true, completing: false, time: 1, reducedMotion: false)
        XCTAssertEqual(restart.progress(working: false, completing: false, time: 1 + frame, reducedMotion: false), 1)
    }

    func testPausedTimelineAndReduceMotionSwitchImmediately() {
        var paused = GlowPhaseHandoff()
        _ = paused.progress(working: false, completing: false, time: 1, reducedMotion: false)
        XCTAssertEqual(paused.progress(working: true, completing: false, time: 5, reducedMotion: false), 1)

        var reduced = GlowPhaseHandoff()
        _ = reduced.progress(working: false, completing: false, time: 1, reducedMotion: true)
        XCTAssertEqual(reduced.progress(working: true, completing: false, time: 1 + frame, reducedMotion: true), 1)
    }

    func testListeningOpacityMirrorsTheIndicator() {
        XCTAssertEqual(GlowPhaseHandoff.listeningOpacity(working: true, progress: 0.25), 0.75)
        XCTAssertEqual(GlowPhaseHandoff.listeningOpacity(working: false, progress: 0.25), 0.25)
        XCTAssertEqual(GlowPhaseHandoff.listeningOpacity(working: false, progress: 1), 1)
    }
}
