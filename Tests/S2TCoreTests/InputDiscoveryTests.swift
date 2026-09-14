import XCTest
@testable import S2TCore

final class InputDiscoveryTests: XCTestCase {
    let window = CGRect(x: 280, y: 200, width: 1040, height: 730)

    func testMissingTopLevelFocusCanStillChooseDominantEditor() {
        let search = DiscoveredInput(id: 0, frame: CGRect(x: 1150, y: 245, width: 150, height: 18), boundary: CGRect(x: 1140, y: 239, width: 170, height: 30))
        let editor = DiscoveredInput(id: 1, frame: CGRect(x: 508, y: 887, width: 704, height: 38), boundary: CGRect(x: 466, y: 886, width: 856, height: 39))
        XCTAssertEqual(InputDiscovery.choose([search, editor], window: window, anchor: nil), 1)
        XCTAssertEqual(InputDiscovery.choose([search, editor], window: window, anchor: CGPoint(x: 1200, y: 255)), 0)
    }

    func testActualFocusWinsOverPreviousClickAndLargerEditor() {
        let focused = DiscoveredInput(id: 0, frame: CGRect(x: 400, y: 250, width: 180, height: 25), boundary: CGRect(x: 390, y: 240, width: 200, height: 40), focused: true)
        let other = DiscoveredInput(id: 1, frame: CGRect(x: 400, y: 750, width: 750, height: 80), boundary: CGRect(x: 380, y: 730, width: 800, height: 130))
        XCTAssertEqual(InputDiscovery.choose([focused, other], window: window, anchor: CGPoint(x: 800, y: 790)), 0)
    }

    func testSimilarInputsNeedInteractionEvidence() {
        let fields = (0..<3).map { i in
            let frame = CGRect(x: 450, y: 400 + i * 60, width: 500, height: 35)
            return DiscoveredInput(id: i, frame: frame, boundary: frame.insetBy(dx: -8, dy: -8))
        }
        XCTAssertNil(InputDiscovery.choose(fields, window: window, anchor: nil))
        XCTAssertEqual(InputDiscovery.choose(fields, window: window, anchor: CGPoint(x: 500, y: 475)), 1)
    }

    func testSamplingUsesWindowCoordinatesAndStartsWithInteraction() {
        let anchor = CGPoint(x: 520, y: 910)
        let points = InputDiscovery.samplePoints(in: window, anchor: anchor)
        XCTAssertEqual(points.first, anchor)
        XCTAssertLessThanOrEqual(points.count, 28)
        XCTAssertTrue(points.allSatisfy(window.contains))
        XCTAssertTrue(points.contains { $0.y > 890 })
        XCTAssertTrue(points.contains { $0.y < 290 })
    }
}
