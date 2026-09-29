import XCTest
@testable import S2TCore

final class InputGlowSizeTests: XCTestCase {
    func testSizeResponseKeepsSmallFieldsVisibleAndIncreasesSmoothly() {
        let tuning = GlowTuning(inputSizeEnabled: true)
        let small = tuning.forInput(size: CGSize(width: 800, height: 24))
        let medium = tuning.forInput(size: CGSize(width: 400, height: 120))
        let large = tuning.forInput(size: CGSize(width: 600, height: 300))
        func coverage(_ value: GlowTuning) -> Double {
            GlowTuning.coverage(0.5, distance: 20, extent: 128, falloff: value.falloff)
        }
        XCTAssertGreaterThan(coverage(small), 0.25)
        XCTAssertLessThan(coverage(small), coverage(medium))
        XCTAssertLessThan(coverage(medium), coverage(large))
        XCTAssertEqual(tuning.forInput(size: .zero, preview: true), large)
        XCTAssertEqual(tuning.forInput(size: CGSize(width: 20, height: 900)), small)
    }

    func testPersistenceAndDisabledCompatibility() throws {
        let old = try JSONDecoder().decode(GlowTuning.self, from: Data("{}".utf8))
        XCTAssertFalse(old.inputSizeEnabled)
        XCTAssertEqual(old.forInput(size: .zero), old)
        let tuning = GlowTuning(inputSizeEnabled: true, inputMinimumSize: 0.7, inputMaximumSize: 1.8)
        XCTAssertEqual(try JSONDecoder().decode(GlowTuning.self, from: JSONEncoder().encode(tuning)), tuning)
        XCTAssertEqual(GlowTuning(inputMinimumSize: 1.8, inputMaximumSize: 0.6).inputMaximumSize, 1.8)
    }
}
