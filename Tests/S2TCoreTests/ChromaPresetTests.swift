import XCTest
@testable import S2TCore

final class ChromaPresetTests: XCTestCase {
    func testBundledPresetsMatchEveryExportedValue() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (preset, file) in [(ChromaPreset.bottom, "bottom-maximum"), (.box, "input-outline"), (.notch, "notch")] {
            let data = try Data(contentsOf: root.appendingPathComponent("docs/references/chroma-glow-\(file).json"))
            XCTAssertEqual(preset, try JSONDecoder().decode(ChromaPreset.self, from: data))
        }
    }

    func testBlurUnitsRemainIndependent() {
        XCTAssertEqual(ChromaPreset.bottom.backgroundBlurRadiusPoints, 25.36087)
        XCTAssertEqual(ChromaPreset.box.backgroundBlurRadiusPoints, 76.59375)
        XCTAssertEqual(ChromaPreset.notch.backgroundBlurRadiusPoints, 29.337423)
        XCTAssertEqual(ChromaPreset.bottom.settings.effectBlur, 60)
        XCTAssertEqual(ChromaPreset.bottom.settings.sweep.blur, 3.138587)
        for preset in [ChromaPreset.bottom, .box, .notch] {
            XCTAssertEqual(preset.settings.blur, 2)
            XCTAssertEqual(preset.sweepPhase(time: 0), 0.5)
            XCTAssertEqual(preset.sweepPhase(time: 7200), 0.5)
            XCTAssertEqual(preset.falloff(0), 0)
            XCTAssertEqual(preset.falloff(1), 1)
        }
    }

    func testBezierUsesXInversionRatherThanTreatingInputAsTime() {
        let curve = ChromaPreset.bottom.settings.falloffCurve
        // At Bezier t=0.5, x=0.875 and y=0.2022844175 for the supplied handles.
        XCTAssertEqual(curve.value(0.875), 0.2022844175, accuracy: 0.00002)
        XCTAssertNotEqual(curve.value(0.5), 0.2022844175, accuracy: 0.01)
    }

    func testSourceFieldHasIndependentColorAndBackdropCoverage() {
        let bottom = ChromaPreset.bottom.field(distance: 0, position: 0.5)
        XCTAssertEqual(bottom.color, 1.06, accuracy: 0.000001)
        XCTAssertEqual(bottom.blur, 1)
        XCTAssertEqual(ChromaPreset.bottom.field(distance: 400, position: 0.5).blur, 0)
        XCTAssertEqual(ChromaPreset.bottom.field(distance: 10, position: 0).blur, 0)
        let box = ChromaPreset.box.field(distance: 50, position: 0.5)
        XCTAssertGreaterThan(box.color, box.blur)
        XCTAssertEqual(ChromaPreset.box.field(distance: 400, position: 0.5).blur, 0)
    }

    func testSweepBlurBroadensThicknessAndConservesPeakEnergy() {
        let preset = ChromaPreset.bottom
        let length = 1800.0
        let peak = preset.sweepCoverage(along: 0, perpendicular: 0, length: length)
        XCTAssertGreaterThan(peak, 0)
        XCTAssertLessThan(peak, preset.settings.sweep.brightness)
        XCTAssertGreaterThan(preset.sweepCoverage(along: 0, perpendicular: 3, length: length), 0.1)
        XCTAssertLessThan(ChromaPreset.box.sweepCoverage(along: 0, perpendicular: 6, length: length), 0.000001)
    }
}
