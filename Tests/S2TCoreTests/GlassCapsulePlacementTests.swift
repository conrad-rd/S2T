import XCTest
@testable import S2TCore

final class GlassCapsulePlacementTests: XCTestCase {
    private let screen = CGRect(x: 100, y: 50, width: 1200, height: 800)

    func testClassicHasOneSelectionAndPreservesLegacyValues() {
        XCTAssertEqual(GlowAppearance.selectableCases.filter(\.isClassic), [.liquidGlass])
        XCTAssertEqual(GlowAppearance.bezel.selection, .liquidGlass)
        XCTAssertEqual(GlowAppearance.liquidGlass.title, "Classic")
        XCTAssertEqual(GlowAppearance(rawValue: "bezel"), .bezel)
    }

    func testEdgeAttachmentAndDetachmentOnOffsetDisplay() throws {
        XCTAssertEqual(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: 110, y: 400), screen: screen), .left)
        XCTAssertEqual(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: 1290, y: 400), screen: screen), .right)
        XCTAssertNil(GlassCapsuleAnchor.dockingSide(pointer: CGPoint(x: 800, y: 400), screen: screen))
        for side in BezelSide.allCases {
            let anchor = GlassCapsuleAnchor(center: CGPoint(x: 800, y: 400), visibleFrame: screen, displayID: "display", side: side)
            let restored = try JSONDecoder().decode(GlassCapsuleAnchor.self, from: JSONEncoder().encode(anchor))
            XCTAssertEqual(restored.side, side)
            XCTAssertEqual(restored.center(in: screen).y, 400)
        }
        let old = Data(#"{"displayID":"old","x":0.5,"y":0.25,"centered":true}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(GlassCapsuleAnchor.self, from: old).side)
    }

    func testCenterSnapRequiresDeliberatePullToDetach() {
        var drag = GlassCapsuleDrag(pointer: CGPoint(x: 750, y: 150),
            center: CGPoint(x: 760, y: 160), screenMidX: screen.midX)
        XCTAssertEqual(drag.update(pointer: CGPoint(x: 700, y: 180), visibleFrame: screen), CGPoint(x: 700, y: 190))
        XCTAssertTrue(drag.snapped)
        XCTAssertEqual(drag.update(pointer: CGPoint(x: 715, y: 200), visibleFrame: screen).x, 700)
        XCTAssertTrue(drag.snapped)
        XCTAssertEqual(drag.update(pointer: CGPoint(x: 722, y: 200), visibleFrame: screen).x, 732)
        XCTAssertFalse(drag.snapped)
    }

    func testCenteredDragStaysCenteredWhileMovingVertically() {
        var drag = GlassCapsuleDrag(pointer: CGPoint(x: 690, y: 140),
            center: CGPoint(x: 700, y: 150), screenMidX: screen.midX)
        XCTAssertEqual(drag.update(pointer: CGPoint(x: 710, y: 340), visibleFrame: screen), CGPoint(x: 700, y: 350))
    }

    func testAnchorRoundTripAndResolutionChangeKeepRelativePosition() throws {
        let anchor = GlassCapsuleAnchor(center: CGPoint(x: 700, y: 250), visibleFrame: screen, displayID: "display")
        let restored = try JSONDecoder().decode(GlassCapsuleAnchor.self, from: JSONEncoder().encode(anchor))
        XCTAssertEqual(restored, anchor)
        XCTAssertEqual(restored.center(in: CGRect(x: -1600, y: 0, width: 1600, height: 1200)), CGPoint(x: -800, y: 300))
        XCTAssertEqual(GlassCapsuleAnchor.clamp(CGPoint(x: -1000, y: 5000), to: screen), CGPoint(x: 166, y: 822))
    }

    func testDraggingBetweenDisplaysChangesSnapLine() {
        var drag = GlassCapsuleDrag(pointer: CGPoint(x: 700, y: 150),
            center: CGPoint(x: 700, y: 150), screenMidX: screen.midX)
        let second = CGRect(x: -1200, y: 50, width: 1200, height: 800)
        XCTAssertEqual(drag.update(pointer: CGPoint(x: -605, y: 250), visibleFrame: second), CGPoint(x: -600, y: 250))
        XCTAssertTrue(drag.snapped)
    }

    func testSideDockDoesNotMoveTheScreenCenterSnapLine() {
        let visible = CGRect(x: 180, y: 50, width: 1120, height: 800)
        var drag = GlassCapsuleDrag(pointer: CGPoint(x: 700, y: 150),
            center: CGPoint(x: 700, y: 150), screenMidX: 700)
        let center = drag.update(pointer: CGPoint(x: 715, y: 250), visibleFrame: visible, screenMidX: 700)
        XCTAssertEqual(center.x, 700)
        let anchor = GlassCapsuleAnchor(center: center, visibleFrame: visible, displayID: "screen", screenMidX: 700)
        XCTAssertEqual(anchor.center(in: visible, screenMidX: 700).x, 700)
    }
}
