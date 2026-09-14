import XCTest
@testable import S2TCore

final class LisseCornerTests: XCTestCase {
    func testMatchesUpstreamLisseWithConstrainedCornerBudget() {
        // Reference values evaluated from Lisse's corner-params.ts, not the Swift port.
        let corner = LisseCorner(radius: 0.8, budget: 1)
        let actual = [corner.a, corner.b, corner.c, corner.d, corner.p, corner.arc]
        let expected = [0.16583812256334737, 0.24291906128167376, 0.18213980935254281,
                        0.1020031943417623, 1, 0.30709981246067375]
        for (value, reference) in zip(actual, expected) {
            XCTAssertEqual(value, reference, accuracy: 1e-12)
        }
    }

    func testStraightEdgesEaseIntoSquircleAndEndAtRequestedPoint() {
        for verticalFirst in [false, true] {
            let path = CGMutablePath()
            let start = CGPoint(x: 5, y: 10), end = CGPoint(x: 25, y: 30)
            path.move(to: start)
            LisseCorner(radius: 0.8, budget: 1).append(to: path, from: start, to: end, verticalFirst: verticalFirst)
            var curves: [[CGPoint]] = []
            path.applyWithBlock { element in
                if element.pointee.type == .addCurveToPoint {
                    curves.append((0..<3).map { element.pointee.points[$0] })
                }
            }
            XCTAssertEqual(curves.count, 3)
            XCTAssertEqual(path.currentPoint, end)
            let first = curves[0], last = curves[2]
            XCTAssertEqual(verticalFirst ? first[0].x : first[0].y, verticalFirst ? start.x : start.y)
            XCTAssertEqual(verticalFirst ? first[1].x : first[1].y, verticalFirst ? start.x : start.y)
            XCTAssertEqual(verticalFirst ? last[0].y : last[0].x, verticalFirst ? end.y : end.x, accuracy: 1e-10)
            XCTAssertEqual(verticalFirst ? last[1].y : last[1].x, verticalFirst ? end.y : end.x, accuracy: 1e-10)
        }
    }
}
