import XCTest
@testable import S2TCore

final class GlowTuningTests: XCTestCase {
    func testExistingAppearancePreferencesSurviveNewEdgeControls() throws {
        let legacy = Data(#"{"backgroundBlur":1.4,"softness":3,"falloff":0.75,"edgeBrightness":1.6}"#.utf8)
        let saved = try JSONDecoder().decode(GlowTuning.self, from: legacy)
        XCTAssertEqual(saved.backgroundBlur, 1.4)
        XCTAssertEqual(saved.softness, 3)
        XCTAssertEqual(saved.falloff, 0.75)
        XCTAssertEqual(saved.edgeBrightness, 1.6)
        XCTAssertEqual(saved.edgeBlur, 0)
        XCTAssertEqual(saved.edgeGlow, 0)
        XCTAssertEqual(saved.edgeHeight, 1)
        XCTAssertEqual(saved.edgeOpacity, 1)
        XCTAssertEqual(saved.bodyOpacity, 1)
    }

    func testMainOpacityPersistsWithoutChangingEdgeOrBlur() throws {
        let saved = GlowTuning(backgroundBlur: 1.4, edgeOpacity: 0.7, bodyOpacity: 0.6)
        let restored = try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(saved)).normalized
        XCTAssertEqual(restored.bodyOpacity, 0.6)
        XCTAssertEqual(restored.backgroundBlur, 1.4)
        XCTAssertEqual(restored.edgeOpacity, 0.7)
        XCTAssertEqual(GlowTuning(bodyOpacity: -.infinity).bodyOpacity, 1)
        XCTAssertEqual(GlowTuning(bodyOpacity: -1).bodyOpacity, 0)
        XCTAssertEqual(GlowTuning(bodyOpacity: 2).bodyOpacity, 1)
    }

    func testEdgeControlsSaveIndependentlyWithBoundedDefaults() throws {
        let saved = GlowTuning(edgeBrightness: 1.7, edgeBlur: 5, edgeGlow: 1.2, edgeHeight: 0.5, edgeOpacity: 0.4)
        XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(saved)), saved)
        XCTAssertEqual(saved.backgroundBlur, 1)
        XCTAssertEqual(saved.softness, 0)
        XCTAssertEqual(saved.falloff, 1)
        let invalid = GlowTuning(edgeBlur: -.infinity, edgeGlow: 100, edgeHeight: 0, edgeOpacity: 4)
        XCTAssertEqual(invalid.edgeBlur, 0)
        XCTAssertEqual(invalid.edgeGlow, 2)
        XCTAssertEqual(invalid.edgeHeight, 0)
        XCTAssertEqual(GlowTuning(edgeHeight: 4).edgeHeight, 1)
        for height in [0.0, 0.5, 1.0] {
            let value = GlowTuning(edgeHeight: height)
            XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(value)).edgeHeight, height)
        }
        XCTAssertEqual(invalid.edgeOpacity, 1)
        XCTAssertEqual(GlowResponseSettings(tuning: saved).paddingScale, 1)
    }

    func testSavedControlsNormalizeInvalidValuesWithoutChangingDefaults() throws {
        let defaults = GlowTuning()
        XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(defaults)), defaults)
        let invalid = GlowTuning(backgroundBlur: -.infinity, softness: 100, falloff: -10, edgeBrightness: .nan)
        XCTAssertEqual(invalid.backgroundBlur, 1)
        XCTAssertEqual(invalid.softness, 12)
        XCTAssertEqual(invalid.falloff, 0.5)
        XCTAssertEqual(invalid.edgeBrightness, 1)
        XCTAssertEqual(GlowTuning(backgroundBlur: 0).backgroundBlur, 0)
    }

    func testFalloffKeepsTheBoundaryAndEndsWithoutACutoff() {
        for value in [0.0, 0.02, 0.4, 1] {
            XCTAssertEqual(GlowTuning.coverage(value, distance: 50, extent: 240, falloff: 1), value)
        }
        XCTAssertGreaterThan(GlowTuning.coverage(0.1, distance: 50, extent: 240, falloff: 0.5), 0.1)
        XCTAssertLessThan(GlowTuning.coverage(0.1, distance: 50, extent: 240, falloff: 2), 0.1)
        XCTAssertEqual(GlowTuning.coverage(1, distance: 0, extent: 240, falloff: 0.5), 1)
        XCTAssertEqual(GlowTuning.coverage(0.01, distance: 240, extent: 240, falloff: 0.5), 0)
        XCTAssertLessThan(GlowTuning.coverage(0.01, distance: 239, extent: 240, falloff: 0.5), 0.0001)
    }
}
