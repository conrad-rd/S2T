import XCTest
@testable import S2TCore

final class BackdropBlurFalloffTests: XCTestCase {
    func testSoftensContrastWithoutBlurringOutsideTheEffect() {
        XCTAssertEqual(BackdropBlurFalloff.strength(0), 0)
        XCTAssertLessThan(BackdropBlurFalloff.strength(1), 0.7)
        XCTAssertGreaterThan(BackdropBlurFalloff.strength(0.04), 0.04)
        XCTAssertGreaterThan(BackdropBlurFalloff.strength(0.25), BackdropBlurFalloff.strength(0.04))
        XCTAssertLessThan(BackdropBlurFalloff.strength(1) / BackdropBlurFalloff.strength(0.04), 8)
        for index in 1...100 {
            XCTAssertGreaterThan(BackdropBlurFalloff.strength(Double(index) / 100),
                                 BackdropBlurFalloff.strength(Double(index - 1) / 100))
        }
    }
    func testTailReachesClearWithoutChangingTheInnerTransfer() {
        XCTAssertEqual(BackdropBlurFalloff.strength(0.4, remainingFraction: 0), 0)
        XCTAssertEqual(BackdropBlurFalloff.strength(0.4, remainingFraction: 1), BackdropBlurFalloff.strength(0.4))
        XCTAssertLessThan(BackdropBlurFalloff.strength(0.4, remainingFraction: 0.1), 0.02)
        XCTAssertGreaterThan(BackdropBlurFalloff.strength(0.4, remainingFraction: 0.8),
                             BackdropBlurFalloff.strength(0.4, remainingFraction: 0.4))
    }

}
