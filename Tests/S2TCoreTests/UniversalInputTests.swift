import XCTest
@testable import S2TCore

final class UniversalInputTests: XCTestCase {
    func testCornerRadiusUsesMatchingPaddingInsteadOfAnUnrelatedSmallInset() throws {
        for scale in [CGFloat(0.65), 1, 1.5, 2] {
            for height in [CGFloat(100), 180, 300] {
                for insets in [(CGFloat(2), CGFloat(16), CGFloat(16)), (16, 2, 16), (16, 16, 2)] {
                    let transform = CGAffineTransform(scaleX: scale, y: scale)
                    let body = CGRect(x: 100, y: 100, width: 600, height: height).applying(transform)
                    let editor = CGRect(x: 100 + insets.0, y: 100 + insets.2,
                        width: 600 - insets.0 - insets.1, height: height - insets.2 - 44).applying(transform)
                    let nodes = [0: ComposerNode(id: 0, role: "AXTextArea", frame: editor, parent: 1),
                        1: ComposerNode(id: 1, role: "AXGroup", frame: body, parent: nil, children: [0, 2]),
                        2: ComposerNode(id: 2, role: "AXButton", frame:
                            CGRect(x: 656, y: 100 + height - 40, width: 28, height: 28).applying(transform), parent: 1)]
                    let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
                    XCTAssertEqual(target.frame, body)
                    XCTAssertEqual(target.cornerRadius, 16 * scale, accuracy: 0.001)
                    XCTAssertEqual(target.cornerStyle, .continuous)
                }
            }
        }
    }

    func testCompactRowCanReserveLeadingIconSpaceWithoutExposingAnIcon() throws {
        let body = CGRect(x: 100, y: 400, width: 500, height: 70)
        let nodes = [0: ComposerNode(id: 0, role: "AXTextArea", frame: CGRect(x: 150, y: 420, width: 400, height: 30), parent: 1),
            1: ComposerNode(id: 1, role: "AXGroup", frame: body, parent: 3, children: [0, 2]),
            2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 560, y: 420, width: 28, height: 28), parent: 1),
            3: ComposerNode(id: 3, role: "AXToolbar", frame: CGRect(x: 0, y: 400, width: 1200, height: 70), parent: nil, children: [1])]
        let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
        XCTAssertEqual(target.frame, body)
        XCTAssertEqual(target.kind, .input)
        XCTAssertEqual(target.cornerRadius, 35)
    }

    func testDecorativeSearchIconsBelongToTheFieldAtEveryScale() throws {
        for scale in [CGFloat(0.65), 1, 1.5, 2] {
            let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -700, y: 230)
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x, y: y, width: w, height: h).applying(transform)
            }
            let body = r(100, 100, 400, 40)
            let nodes = [0: ComposerNode(id: 0, role: "AXTextField", frame: r(150, 110, 300, 20), parent: 1),
                1: ComposerNode(id: 1, role: "AXGroup", frame: body, parent: 4, children: [0, 2, 3]),
                2: ComposerNode(id: 2, role: "AXImage", frame: r(112, 110, 20, 20), parent: 1),
                3: ComposerNode(id: 3, role: "AXImage", frame: r(468, 110, 20, 20), parent: 1),
                4: ComposerNode(id: 4, role: "AXToolbar", frame: r(0, 80, 1200, 80), parent: nil, children: [1])]
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
            XCTAssertEqual(target.frame, body)
            XCTAssertEqual(target.kind, .input)
            XCTAssertEqual(target.cornerStyle, .circular)
            XCTAssertEqual(target.cornerRadius, 20 * scale, accuracy: 0.001)
        }
    }

    func testStandaloneFieldsKeepTheirOutlineWhenCornerEvidenceIsLimited() throws {
        let field = CGRect(x: 100, y: 100, width: 400, height: 32)
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXGroup"] {
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes:
                [0: ComposerNode(id: 0, role: role, editable: true, frame: field, parent: nil)]))
            XCTAssertEqual(target.kind, .input)
            XCTAssertEqual(target.frame, field)
            XCTAssertGreaterThan(target.cornerRadius, 0)
            let converted = try XCTUnwrap(target.onScreens(primaryTop: 1000,
                screens: [CGRect(x: 0, y: 0, width: 1500, height: 1000)]))
            XCTAssertEqual(converted.kind, .input)
            XCTAssertEqual(converted.frame.minY, 868)
        }
    }

    func testAsymmetricTextBoundsDoNotDisplaceCompactControlRows() throws {
        let nodes = [0: ComposerNode(id: 0, role: "AXTextField", frame: CGRect(x: 131, y: 118, width: 695, height: 31), parent: 1),
            1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 100, width: 732, height: 52), parent: nil, children: [0, 2]),
            2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 110, y: 111.5, width: 23.5, height: 30), parent: 1)]
        let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
        XCTAssertEqual(target.frame, nodes[1]?.frame)
        XCTAssertEqual(target.cornerRadius, 26)
        XCTAssertEqual(target.cornerStyle, .circular)
        XCTAssertEqual(target.kind, .input)
    }

    func testGrowingMultilineComposerKeepsContentSpacingCorners() throws {
        for height in [CGFloat(80), 160, 300] {
            let nodes = [0: ComposerNode(id: 0, role: "AXTextArea", frame: CGRect(x: 116, y: 116, width: 568, height: height - 60), parent: 1),
                1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 100, width: 600, height: height), parent: nil, children: [0, 2]),
                2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 656, y: 100 + height - 40, width: 28, height: 28), parent: 1)]
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
            XCTAssertEqual(target.kind, .input)
            XCTAssertEqual(target.cornerRadius, 16)
        }
    }

    func testAmbiguousOrIncompleteParentKeepsTheConfirmedFieldOutline() throws {
        let input = CGRect(x: 110, y: 110, width: 400, height: 30)
        for incomplete in [false, true] {
            let nodes = [0: ComposerNode(id: 0, role: "AXTextField", frame: input, parent: 1),
                1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 100, width: 430, height: 90), parent: nil, children: [0, 2], childrenComplete: !incomplete),
                2: ComposerNode(id: 2, role: "AXTextField", frame: CGRect(x: 110, y: 150, width: 400, height: 30), parent: 1)]
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
            XCTAssertEqual(target.frame, input)
            XCTAssertEqual(target.kind, .input)
        }
    }
}
