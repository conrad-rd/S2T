import CoreGraphics
import XCTest
@testable import S2TCore

final class GlowPlacementTests: XCTestCase {
    private func mac(origin: CGPoint = .zero) -> GlowDisplay {
        GlowDisplay(frame: CGRect(origin: origin, size: CGSize(width: 1512, height: 982)), safeTop: 32,
                    topLeft: CGRect(x: origin.x, y: origin.y + 950, width: 660, height: 32),
                    topRight: CGRect(x: origin.x + 852, y: origin.y + 950, width: 660, height: 32))
    }

    func testNotchUsesReportedGapAndGlobalCoordinates() {
        let display = mac(origin: CGPoint(x: -1512, y: 300))
        XCTAssertEqual(display.notch, CGRect(x: -852, y: 1250, width: 192, height: 32))
        let layout = TopGlowLayout(display: display)
        XCTAssertEqual(layout.frame.maxY, 1282)
        XCTAssertEqual(layout.frame.midX, -756)
        XCTAssertEqual(layout.notch?.width, 192)
        XCTAssertEqual(layout.notch?.height, 32)
        XCTAssertGreaterThan(layout.notch!.minX, 30)
        XCTAssertLessThan(layout.notch!.minX, 224)
    }

    func testNoNotchUsesTopWithoutTreatingMenuBarAsNotch() {
        let display = GlowDisplay(frame: CGRect(x: 1512, y: -240, width: 1920, height: 1080))
        XCTAssertNil(display.notch)
        let layout = TopGlowLayout(display: display)
        XCTAssertNil(layout.notch)
        XCTAssertLessThanOrEqual(layout.frame.width, 320)
        XCTAssertLessThan(layout.frame.width, display.frame.width / 3)
        XCTAssertEqual(layout.frame.maxY, 840)
        XCTAssertEqual(layout.frame.midX, 2472)
        XCTAssertEqual(layout.distance(at: CGPoint(x: layout.frame.width / 2, y: 5)), 5)
    }

    func testIncompleteOrOverlappingSafeAreasDoNotInventNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertNil(GlowDisplay(frame: frame, safeTop: 32).notch)
        XCTAssertNil(GlowDisplay(frame: frame, safeTop: 32,
            topLeft: CGRect(x: 0, y: 768, width: 600, height: 32),
            topRight: CGRect(x: 500, y: 768, width: 500, height: 32)).notch)
    }

    func testStripFollowsSidesAndBottomAndExcludesHousing() {
        let layout = TopGlowLayout(display: mac())
        let notch = layout.notch!
        XCTAssertLessThan(layout.distance(at: CGPoint(x: notch.midX, y: 10)), 0)
        XCTAssertEqual(layout.distance(at: CGPoint(x: notch.minX - 2, y: 12)), 2, accuracy: 0.001)
        XCTAssertEqual(layout.distance(at: CGPoint(x: notch.maxX + 2, y: 12)), 2, accuracy: 0.001)
        XCTAssertEqual(layout.distance(at: CGPoint(x: notch.midX, y: notch.maxY + 2)), 2, accuracy: 0.001)
        XCTAssertGreaterThan(layout.distance(at: CGPoint(x: notch.minX, y: notch.maxY)), 0)
        XCTAssertEqual(layout.sideOpacity(at: 0), 0)
        XCTAssertEqual(layout.sideOpacity(at: layout.frame.width), 0)
        XCTAssertEqual(layout.sideOpacity(at: notch.midX), 1)
        XCTAssertEqual(layout.sideOpacity(at: notch.minX - 49), 0)
        XCTAssertEqual(layout.blurSideOpacity(at: notch.minX - 49), 0)
        XCTAssertEqual(layout.blurSideOpacity(at: notch.minX - 145), 0)
        XCTAssertLessThan(layout.sideOpacity(at: notch.minX - 35), layout.sideOpacity(at: notch.minX - 10))
    }

    func testNotchModeFollowsPointerWithBothDisplaysConnected() {
        let external = GlowDisplay(frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let pointer = CGPoint(x: 2000, y: 500)
        XCTAssertEqual(GlowDisplay.preferredIndex(in: [external, mac()], pointer: pointer), 0)
        XCTAssertEqual(GlowDisplay.preferredIndex(in: [external], pointer: pointer), 0)
        XCTAssertNil(GlowDisplay.preferredIndex(in: [], pointer: pointer))
        XCTAssertEqual(GlowDisplay.preferredIndex(in: [external, mac()], pointer: CGPoint(x: 700, y: 500)), 1)
        let layout = TopGlowLayout(display: [external, mac()][GlowDisplay.preferredIndex(in: [external, mac()], pointer: pointer)!])
        XCTAssertNil(layout.notch)
        XCTAssertEqual(layout.frame.midX, external.frame.midX)
        XCTAssertEqual(layout.frame.maxY, external.frame.maxY)
    }

    func testTopJoinDistanceIsContinuousAcrossBothSideBoundaries() {
        let layout = TopGlowLayout(display: mac())
        let notch = layout.notch!
        for edge in [notch.minX, notch.maxX] {
            for y in stride(from: 0.25, through: 5.75, by: 0.25) {
                let left = layout.distance(at: CGPoint(x: edge - 0.001, y: y))
                let right = layout.distance(at: CGPoint(x: edge + 0.001, y: y))
                XCTAssertLessThanOrEqual(abs(left - right), 0.00201)
            }
        }
    }

    func testTopJoinsRoundIntoBothNotchSides() {
        let layout = TopGlowLayout(display: mac())
        let notch = layout.notch!
        for x in [notch.minX - 1, notch.maxX + 1] {
            XCTAssertLessThan(layout.distance(at: CGPoint(x: x, y: 1)), 0)
            XCTAssertGreaterThan(layout.distance(at: CGPoint(x: x, y: 5)), 0)
        }
        for x in [notch.minX - 6, notch.maxX + 6] {
            XCTAssertEqual(layout.distance(at: CGPoint(x: x, y: 0)), 0, accuracy: 0.001)
        }
        for x in [notch.minX, notch.maxX] {
            XCTAssertEqual(layout.distance(at: CGPoint(x: x, y: 6)), 0, accuracy: 0.001)
        }
    }
}
