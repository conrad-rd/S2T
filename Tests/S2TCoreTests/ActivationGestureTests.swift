import XCTest
@testable import S2TCore

final class ActivationGestureTests: XCTestCase {
    func testHoldStartsImmediatelyAndReleaseStops() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.press(at: 0, listening: false, hold: true, tap: true), .start)
        XCTAssertEqual(gesture.release(at: 0.8), .stop)
    }
    func testTapLatchesAndNextTapStops() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.press(at: 0, listening: false, hold: true, tap: true), .start)
        XCTAssertEqual(gesture.release(at: 0.1), .none)
        XCTAssertEqual(gesture.press(at: 1, listening: true, hold: true, tap: true), .none)
        XCTAssertEqual(gesture.release(at: 1.1), .stop)
    }
    func testHoldOnlyNeverLatches() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.press(at: 0, listening: false, hold: true, tap: false), .start)
        XCTAssertEqual(gesture.release(at: 0.1), .stop)
    }
    func testTapOnlyDoesNotStartOnHold() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.press(at: 0, listening: false, hold: false, tap: true), .none)
        XCTAssertEqual(gesture.release(at: 0.8), .none)
        XCTAssertEqual(gesture.press(at: 1, listening: false, hold: false, tap: true), .none)
        XCTAssertEqual(gesture.release(at: 1.1), .toggle)
    }
    func testBothDisabledDoNothing() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.press(at: 0, listening: false, hold: false, tap: false), .none)
        XCTAssertEqual(gesture.release(at: 0.1), .none)
    }
    func testKeyCombinationCancelsOnlyTheRecordingItStarted() {
        var gesture = ActivationGesture()
        _ = gesture.press(at: 0, listening: false, hold: true, tap: true)
        XCTAssertEqual(gesture.interrupt(), .cancel)
        XCTAssertEqual(gesture.release(at: 0.1), .none)
        _ = gesture.press(at: 1, listening: true, hold: true, tap: true)
        XCTAssertEqual(gesture.interrupt(), .none)
        XCTAssertEqual(gesture.release(at: 1.1), .none)
    }
    func testRepeatAndOrphanReleaseDoNotToggle() {
        var gesture = ActivationGesture()
        XCTAssertEqual(gesture.release(at: 0), .none)
        _ = gesture.press(at: 1, listening: false, hold: true, tap: true)
        XCTAssertEqual(gesture.press(at: 1.05, listening: true, hold: true, tap: true), .none)
        XCTAssertEqual(gesture.release(at: 1.1), .none)
    }
    func testAResetEndsOwnedHoldBeforePermissionsOrSettingsChange() {
        var gesture = ActivationGesture()
        _ = gesture.press(at: 0, listening: false, hold: true, tap: true)
        XCTAssertEqual(gesture.interrupt(), .cancel)
        XCTAssertEqual(gesture.release(at: 0.5), .none)
    }
}
