import XCTest
@testable import S2TCore

final class InputHeightResizeTests: XCTestCase {
    func testGrowthPreservesBothCornersAndAttachedBars() throws {
        var source = InputContour(rect: CGRect(x: 40, y: 80, width: 600, height: 100), radius: 16, style: .circular)
        source.bars = [.init(rect: CGRect(x: 60, y: 50, width: 560, height: 34), radius: 14, style: .circular, corners: .top),
                       .init(rect: CGRect(x: 60, y: 176, width: 560, height: 34), radius: 14, style: .circular, corners: .bottom)]
        for growth in [CGFloat(-20), 1, 24, 160] {
            var target = source
            target.main.rect.size.height += growth
            target.bars[1].rect.origin.y += growth
            let resize = try XCTUnwrap(InputHeightResize(source: source, target: target))
            for y in stride(from: CGFloat(0), through: 96, by: 0.5) { XCTAssertEqual(resize.sourceY(y), y, accuracy: 0.0001) }
            for y in stride(from: CGFloat(164) + growth, through: 260 + growth, by: 0.5) {
                XCTAssertEqual(resize.sourceY(y), y - growth, accuracy: 0.0001)
            }
            XCTAssertEqual(resize.sourceY(target.main.rect.midY), source.main.rect.midY, accuracy: 0.0001)
        }
    }

    func testDifferentShapesRequireFreshAssets() {
        let source = InputContour(rect: CGRect(x: 40, y: 80, width: 600, height: 100), radius: 16, style: .circular)
        var changed = source
        changed.main.radius = 24
        XCTAssertNil(InputHeightResize(source: source, target: changed))
        changed = source; changed.main.rect.size.width += 1
        XCTAssertNil(InputHeightResize(source: source, target: changed))
        changed = source; changed.main.style = .continuous
        XCTAssertNil(InputHeightResize(source: source, target: changed))
        changed = source; changed.main.rect.size.height = 32
        XCTAssertNil(InputHeightResize(source: source, target: changed))
        changed = source; changed.bars = [.init(rect: CGRect(x: 40, y: 180, width: 600, height: 32), radius: 16)]
        XCTAssertNil(InputHeightResize(source: source, target: changed))
    }
}
