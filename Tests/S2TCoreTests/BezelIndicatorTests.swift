import XCTest
@testable import S2TCore

final class BezelIndicatorTests: XCTestCase {
    func testOuterTipDoesNotHumpDuringSpeechOrElasticStretch() {
        for side in BezelSide.allCases {
            for level in [0.0, 0.55, 1] {
                for form in [BezelForm.shown, .init(depth: 1.15, body: 0.9, attachment: 1)] {
                    let shape = BezelGeometry.shape(form: form, side: side, level: level)
                    func extent(at y: Double) -> Double {
                        var low = 0.0, high = BezelGeometry.size.width
                        for _ in 0..<40 {
                            let distance = (low + high) / 2
                            let x = side == .left ? distance : BezelGeometry.size.width - distance
                            if shape.path.contains(CGPoint(x: x, y: y)) { low = distance } else { high = distance }
                        }
                        return (low + high) / 2
                    }
                    let middle = extent(at: shape.symbolCenter.y)
                    XCTAssertEqual(extent(at: shape.symbolCenter.y - 10), middle, accuracy: 0.001)
                    XCTAssertEqual(extent(at: shape.symbolCenter.y + 10), middle, accuracy: 0.001)
                }
            }
        }
    }

    func testConnectorExtendsFurtherIntoTheBezel() {
        let bounds = BezelGeometry.shape(form: .shown, side: .left).path.boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(bounds.height, 108)
        XCTAssertLessThanOrEqual(bounds.height, 114)
    }

    func testWaveformHasEqualPaddingAcrossTheFullVisibleBody() {
        for side in BezelSide.allCases {
            for level in [0.0, 0.55, 1] {
                for form in [BezelForm.shown, .init(depth: 1.15, body: 0.9, attachment: 1)] {
                    let shape = BezelGeometry.shape(form: form, side: side, level: level, tilt: 0.5)
                    let bounds = shape.path.boundingBoxOfPath
                    let leftGap = shape.symbolCenter.x - bounds.minX - 9.4
                    let rightGap = bounds.maxX - shape.symbolCenter.x - 9.4
                    XCTAssertEqual(leftGap, rightGap, accuracy: 0.001)
                    XCTAssertGreaterThanOrEqual(min(leftGap, rightGap), 12)
                }
            }
        }
    }

    func testBothSidesAreExactMirrorsWithNoGapAtTheDisplayEdge() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        for level in [0.0, 0.55, 1] {
            let left = BezelGeometry.shape(form: .shown, side: .left, level: level, tilt: -0.5)
            let right = BezelGeometry.shape(form: .shown, side: .right, level: level, tilt: -0.5)
            XCTAssertEqual(BezelGeometry.frame(screen: screen, side: .left).minX + left.path.boundingBoxOfPath.minX, screen.minX)
            XCTAssertEqual(BezelGeometry.frame(screen: screen, side: .right).minX + right.path.boundingBoxOfPath.maxX, screen.maxX)
            XCTAssertEqual(left.symbolCenter.x + right.symbolCenter.x, BezelGeometry.size.width)
            XCTAssertEqual(left.symbolCenter.y, right.symbolCenter.y)
        }
    }

    func testConnectorMergesIntoEdgeWithoutProtrudingTabs() {
        for side in BezelSide.allCases {
            let path = BezelGeometry.shape(form: .shown, side: side).path
            let middle = BezelGeometry.size.height / 2
            for distance in [0.25, 1, 2, 4, 8] {
                let x = side == .left ? distance : BezelGeometry.size.width - distance
                for offset in [-70.0, -66, -60, 60, 66, 70] {
                    XCTAssertFalse(path.contains(CGPoint(x: x, y: middle + offset)))
                }
            }
            let edgeX = side == .left ? 1.0 : BezelGeometry.size.width - 1
            XCTAssertTrue(path.contains(CGPoint(x: edgeX, y: middle - 40)))
            XCTAssertTrue(path.contains(CGPoint(x: edgeX, y: middle + 40)))
        }
    }

    func testSquircleJoinsHaveShortFlatShouldersAndNoDiagonalEdges() {
        var cursor = CGPoint.zero
        var horizontalShoulders = 0
        BezelGeometry.shape(form: .shown, side: .left).path.applyWithBlock { element in
            let item = element.pointee
            switch item.type {
            case .moveToPoint: cursor = item.points[0]
            case .addCurveToPoint: cursor = item.points[2]
            case .addLineToPoint:
                let end = item.points[0]
                XCTAssertTrue(abs(end.x - cursor.x) < 0.001 || abs(end.y - cursor.y) < 0.001)
                if abs(end.y - cursor.y) < 0.001 && abs(end.x - cursor.x) > 0.1 {
                    horizontalShoulders += 1
                    XCTAssertLessThan(abs(end.x - cursor.x), 6)
                }
                cursor = end
            default: break
            }
        }
        XCTAssertEqual(horizontalShoulders, 2)
    }

    func testSilhouetteIsTallAndShallowInsteadOfSquare() {
        let bounds = BezelGeometry.shape(form: .shown, side: .left).path.boundingBoxOfPath
        XCTAssertGreaterThanOrEqual(bounds.height, 90)
        XCTAssertLessThanOrEqual(bounds.width, 48)
        XCTAssertGreaterThan(bounds.height / bounds.width, 2.1)
    }

    func testAttachmentHasNoSuddenCurvatureAtTheBezel() {
        var points = [CGPoint]()
        BezelGeometry.shape(form: .shown, side: .left).path.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint: points.append(element.pointee.points[0])
            case .addCurveToPoint:
                if points.count == 1 { points += (0..<3).map { element.pointee.points[$0] } }
            default: break
            }
        }
        XCTAssertEqual(points.count, 4)
        guard points.count == 4 else { return }
        XCTAssertEqual(points[1].x, points[0].x, accuracy: 0.001)
        XCTAssertEqual(points[2].x, points[0].x, accuracy: 0.001)
    }

    func testBothSidesAttachExactlyToDisplayEdge() {
        for screen in [CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                       CGRect(x: 0, y: -982, width: 1512, height: 982),
                       CGRect(x: 0, y: 0, width: 1800, height: 1169)] {
            let left = BezelGeometry.frame(screen: screen, side: .left)
            let right = BezelGeometry.frame(screen: screen, side: .right)
            XCTAssertEqual(left.minX, screen.minX)
            XCTAssertEqual(right.maxX, screen.maxX)
            XCTAssertEqual(left.midY, screen.midY, accuracy: 0.5)
            XCTAssertEqual(right.midY, screen.midY, accuracy: 0.5)
            XCTAssertEqual(left.minY, floor(left.minY))
            XCTAssertTrue(screen.contains(left))
            XCTAssertTrue(screen.contains(right))
        }
    }

    func testRetractionStaysAttachedAndMirrorsWithoutClipping() {
        for amount in stride(from: 0.0, through: 1.0, by: 0.05) {
            let left = BezelGeometry.shape(form: .init(depth: amount, body: amount, attachment: amount), side: .left).path.boundingBoxOfPath
            let right = BezelGeometry.shape(form: .init(depth: amount, body: amount, attachment: amount), side: .right).path.boundingBoxOfPath
            XCTAssertEqual(left.minX, 0, accuracy: 0.001)
            XCTAssertEqual(right.maxX, BezelGeometry.size.width, accuracy: 0.001)
            XCTAssertEqual(left.width, right.width, accuracy: 0.001)
            XCTAssertLessThan(left.maxX, BezelGeometry.size.width)
            XCTAssertGreaterThanOrEqual(left.minY, 0)
            XCTAssertLessThanOrEqual(left.maxY, BezelGeometry.size.height)
        }
        XCTAssertEqual(BezelGeometry.shape(form: .hidden, side: .left).path.boundingBoxOfPath.width, 0)
    }

    func testLiquidMotionChangesProportionsAndSettles() {
        var motion = BezelMotion()
        motion.setVisible(true, at: 1)
        XCTAssertEqual(motion.form(at: 1), .hidden)
        let emerging = motion.form(at: 1.14)
        XCTAssertGreaterThan(emerging.depth, emerging.body + 0.1)
        let stretching = motion.form(at: 1.35)
        XCTAssertGreaterThan(stretching.body, 1)
        XCTAssertEqual(motion.form(at: 2), .shown)
        motion.setVisible(false, at: 2)
        let retracting = motion.form(at: 2.2)
        XCTAssertGreaterThan(retracting.attachment, retracting.body + 0.2)
        XCTAssertEqual(motion.form(at: 3), .hidden)
    }

    func testAnchorArrivesBeforeBodyAndBodyHasVisibleElasticOvershoot() {
        var motion = BezelMotion()
        motion.setVisible(true, at: 0)
        let entering = motion.form(at: 0.14)
        XCTAssertGreaterThan(entering.attachment, entering.body + 0.1)
        let maximum = stride(from: 0.0, through: 0.6, by: 1.0 / 120).map { motion.form(at: $0).depth }.max()!
        XCTAssertGreaterThan(maximum, 1.15)
        let shape = BezelGeometry.shape(form: .shown, side: .left)
        XCTAssertEqual(shape.symbolCenter.x, shape.path.boundingBoxOfPath.midX, accuracy: 0.001)
        for x in [-9.0, 9] {
            for y in [-17.0, 17] {
                XCTAssertTrue(shape.path.contains(CGPoint(x: shape.symbolCenter.x + x, y: shape.symbolCenter.y + y)))
            }
        }
    }

    func testInterruptedRetractionPreservesPositionAndVelocity() {
        var motion = BezelMotion()
        motion.setVisible(true, at: 1)
        motion.setVisible(false, at: 2)
        let before = motion.form(at: 2.19 - 0.00001)
        let atTurn = motion.form(at: 2.19)
        motion.setVisible(true, at: 2.19)
        let resumed = motion.form(at: 2.19)
        XCTAssertEqual(resumed.depth, atTurn.depth, accuracy: 0.000001)
        XCTAssertEqual(resumed.body, atTurn.body, accuracy: 0.000001)
        XCTAssertEqual(resumed.attachment, atTurn.attachment, accuracy: 0.000001)
        let after = motion.form(at: 2.19 + 0.00001)
        XCTAssertEqual((atTurn.depth - before.depth) / 0.00001,
                       (after.depth - atTurn.depth) / 0.00001, accuracy: 0.01)
        XCTAssertEqual(motion.form(at: 3.2), .shown)
    }

    func testRepeatedDisplayRefreshAndReducedMotion() {
        var motion = BezelMotion()
        motion.setVisible(true, at: 0)
        let before = motion.form(at: 0.2)
        motion.setVisible(true, at: 0.2)
        XCTAssertEqual(motion.form(at: 0.2), before)
        XCTAssertEqual(motion.form(at: 1), .shown)
        motion.setVisible(false, at: 1, reducedMotion: true)
        XCTAssertEqual(motion.form(at: 1, reducedMotion: true), .hidden)
        motion.setVisible(true, at: 1.1, reducedMotion: true)
        XCTAssertEqual(motion.form(at: 1.1, reducedMotion: true), .shown)
    }

    func testLiquidFramesStayInsidePanelOnBothSides() {
        var motion = BezelMotion()
        motion.setVisible(true, at: 0)
        for start in [0.0, 1.0] {
            if start == 1 { motion.setVisible(false, at: start) }
            for time in stride(from: start, through: start + 1, by: 1.0 / 60) {
                for side in BezelSide.allCases {
                    let path = BezelGeometry.shape(form: motion.form(at: time), side: side, level: 1, tilt: sin(time * 10)).path
                    let bounds = path.boundingBoxOfPath
                    XCTAssertGreaterThanOrEqual(bounds.minX, 0)
                    XCTAssertLessThanOrEqual(bounds.maxX, BezelGeometry.size.width)
                    XCTAssertGreaterThanOrEqual(bounds.minY, 0)
                    XCTAssertLessThanOrEqual(bounds.maxY, BezelGeometry.size.height)
                }
            }
        }
    }

    func testSpectrumBarsAreIndependentAndBounded() {
        XCTAssertEqual(BezelGeometry.barLength(energy: 0), 2.5)
        XCTAssertGreaterThan(BezelGeometry.barLength(energy: 0.55), BezelGeometry.barLength(energy: 0.3))
        XCTAssertEqual(BezelGeometry.barLength(energy: 100), 16.5)
    }
}
