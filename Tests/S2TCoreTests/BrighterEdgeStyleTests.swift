import XCTest
@testable import S2TCore

final class BrighterEdgeStyleTests: XCTestCase {
    // Frozen pixels from the approved E PNGs, not values computed by this implementation.
    func testApprovedPreviewPixels() {
        let samples: [(BrighterEdgeStyle.Mode, Double, Double, Double, [Int], Int)] = [
            (.bottom, 0.5, 540.5, 1079.5, [116, 120, 235, 255], 254),
            (.bottom, 19.5, 540.5, 1060.5, [135, 139, 238, 149], 214),
            (.bottom, 49.5, 540.5, 1030.5, [153, 155, 239, 115], 158),
            (.bottom, 129.5, 540.5, 950.5, [181, 185, 241, 55], 55),
            (.bottom, 5.5, 100.5, 1074.5, [128, 91, 255, 182], 134)

        ]
        for (mode, distance, x, y, expected, blur) in samples {
            let field = BrighterEdgeStyle.sample(mode: mode, distance: distance, x: x, y: y)
            let alpha = field.edgeAlpha + field.alpha * (1 - field.edgeAlpha)
            let color = field.edgeColor * field.edgeAlpha + field.color * field.alpha * (1 - field.edgeAlpha)
            XCTAssertEqual(alpha * 255, Double(expected[3]), accuracy: 1, "\(mode) \(distance)")
            for c in 0..<3 {
                XCTAssertEqual(color[c] * 255, Double(expected[c] * expected[3]) / 255, accuracy: 1.1, "\(mode) \(distance) \(c)")
            }
            XCTAssertEqual(field.blur * 255, Double(blur), accuracy: 1)
        }
    }

    func testContoursUseFrozenBottomLightAndBlurAtNormalizedDistances() {
        for mode in [BrighterEdgeStyle.Mode.notch, .input] {
            let scale = mode == .notch ? 1.2 : 1.5
            for (distance, rgba, blur) in [(19.5, [135, 139, 238, 149], 214),
                                            (49.5, [153, 155, 239, 115], 158),
                                            (129.5, [181, 185, 241, 55], 55)] {
                let field = BrighterEdgeStyle.sample(mode: mode, distance: distance / scale, x: 540.5, y: 540)
                let alpha = field.edgeAlpha + field.alpha * (1 - field.edgeAlpha)
                let color = field.edgeColor * field.edgeAlpha + field.color * field.alpha * (1 - field.edgeAlpha)
                XCTAssertEqual(alpha * 255, Double(rgba[3]), accuracy: 1)
                for channel in 0..<3 {
                    XCTAssertEqual(color[channel] * 255, Double(rgba[channel] * rgba[3]) / 255, accuracy: 1.1)
                }
                XCTAssertEqual(field.blur * 255, Double(blur), accuracy: 1)
            }
            let blue = BrighterEdgeStyle.hue(mode: mode, x: 356.4, y: 540)
            let pink = BrighterEdgeStyle.hue(mode: mode, x: 896.4, y: 540)
            XCTAssertLessThan(blue.x, 0.01)
            XCTAssertGreaterThan(pink.x, 0.9)
        }
    }

    func testFalloffAndPreviewBlurRadii() {
        XCTAssertEqual(BrighterEdgeStyle.Mode.bottom.blurRadius, 12)
        XCTAssertEqual(BrighterEdgeStyle.Mode.notch.blurRadius, 12)
        XCTAssertEqual(BrighterEdgeStyle.Mode.input.blurRadius, 18)
        for mode in BrighterEdgeStyle.Mode.allCases {
            let values = (0...400).map { BrighterEdgeStyle.sample(mode: mode, distance: Double($0), x: 540, y: 540).blur }
            XCTAssertEqual(values[0], 1, accuracy: 0.000001)
            XCTAssertLessThan(values.last!, 1 / 255)
            for (a, b) in zip(values, values.dropFirst()) { XCTAssertGreaterThanOrEqual(a, b) }
        }
    }
}
