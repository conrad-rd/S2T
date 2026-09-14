import XCTest
@testable import S2TCore

final class BezelPositionTests: XCTestCase {
    func testVerticalPlacementKeepsBothEdgesFlushAndBodyOnScreen() {
        let screen = CGRect(x: -1728, y: 120, width: 1728, height: 1117)
        for side in BezelSide.allCases {
            let top = BezelGeometry.frame(screen: screen, side: side, verticalPosition: 0)
            let middle = BezelGeometry.frame(screen: screen, side: side)
            let bottom = BezelGeometry.frame(screen: screen, side: side, verticalPosition: 1)
            XCTAssertGreaterThan(top.midY, middle.midY)
            XCTAssertGreaterThan(middle.midY, bottom.midY)
            XCTAssertEqual(middle.midY, screen.midY, accuracy: 1)
            for frame in [top, middle, bottom] {
                XCTAssertEqual(side == .left ? frame.minX : frame.maxX, side == .left ? screen.minX : screen.maxX)
                XCTAssertGreaterThanOrEqual(frame.midY - 56, screen.minY)
                XCTAssertLessThanOrEqual(frame.midY + 56, screen.maxY)
            }
            XCTAssertEqual(BezelGeometry.frame(screen: screen, side: side, verticalPosition: -10), top)
            XCTAssertEqual(BezelGeometry.frame(screen: screen, side: side, verticalPosition: 10), bottom)
        }
    }
}
