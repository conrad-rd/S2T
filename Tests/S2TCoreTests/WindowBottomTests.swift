import CoreGraphics
import XCTest
@testable import S2TCore

final class WindowBottomTests: XCTestCase {
    func testWindowCoordinatesAndShortWindows() {
        let window = CGRect(x: -1200.25, y: 430.5, width: 900.5, height: 310)
        let layout = WindowBottomLayout(window: window, leftRadius: 16, rightRadius: 26, maximumHeight: 640)
        XCTAssertEqual(layout.frame, window)
        XCTAssertEqual(layout.boundaryY(at: 200), 310)
        XCTAssertEqual(layout.boundaryY(at: 0), 294)
        XCTAssertEqual(layout.boundaryY(at: window.width), 284)
    }

    func testRoundedBoundaryWrapsBothCornersContinuously() {
        let layout = WindowBottomLayout(window: CGRect(x: 10, y: 20, width: 800, height: 900), leftRadius: 26, rightRadius: 16, maximumHeight: 400)
        XCTAssertEqual(layout.frame, CGRect(x: 10, y: 20, width: 800, height: 400))
        for x in stride(from: 0.0, through: 800, by: 0.25) {
            let edge = layout.boundaryY(at: x)
            XCTAssertEqual(layout.distance(at: CGPoint(x: x, y: edge)), 0, accuracy: 0.00001)
            XCTAssertGreaterThan(layout.distance(at: CGPoint(x: x, y: edge - 1)), 0)
            XCTAssertLessThan(layout.distance(at: CGPoint(x: x, y: edge + 1)), 0)
        }
        XCTAssertEqual(layout.boundaryY(at: 26), 400)
        XCTAssertEqual(layout.boundaryY(at: 784), 400)
        XCTAssertGreaterThan(layout.boundaryY(at: 2), layout.boundaryY(at: 0))
        XCTAssertLessThan(layout.boundaryY(at: 798), layout.boundaryY(at: 796))
    }

    func testSquareCornersStaySquareAndRadiusIsBounded() {
        let rect = CGRect(x: 0, y: 0, width: 30, height: 10)
        let square = WindowBottomLayout(window: rect, leftRadius: 0, rightRadius: 0, maximumHeight: 640)
        XCTAssertEqual(square.boundaryY(at: 0), 10)
        XCTAssertEqual(square.boundaryY(at: 30), 10)
        let rounded = WindowBottomLayout(window: rect, leftRadius: 200, rightRadius: 200, maximumHeight: 640)
        XCTAssertEqual(rounded.leftRadius, 5)
        XCTAssertEqual(rounded.rightRadius, 5)
    }
}
