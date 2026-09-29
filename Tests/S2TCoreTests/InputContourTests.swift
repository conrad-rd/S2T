import XCTest
@testable import S2TCore

final class InputContourTests: XCTestCase {
    func testPresetKeepsInsetFooterInsteadOfItsSurroundingRectangle() throws {
        for preset in InputTargetPreset.allCases where preset.usesComposerBoundary {
            for scale in [CGFloat(0.75), 1, 1.5, 2] {
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let nodes = fixture().mapValues { node in
                    ComposerNode(id: node.id, role: node.role, subrole: node.subrole, editable: node.editable,
                        frame: node.frame?.applying(transform), parent: node.parent, children: node.children,
                        childrenComplete: node.childrenComplete)
                }
                let target = try XCTUnwrap(preset.resolve(editor: 0, nodes: nodes))
                XCTAssertEqual(target.frame, CGRect(x: 100, y: 200, width: 690, height: 158).applying(transform))
                XCTAssertEqual(target.contour.main.rect, CGRect(x: 0, y: 0, width: 690, height: 130).applying(transform))
                XCTAssertEqual(target.contour.bars.count, 1)
                XCTAssertEqual(target.contour.bars.first?.rect, CGRect(x: 20, y: 130, width: 650, height: 28).applying(transform))
                XCTAssertEqual(target.contour.bars.first?.corners, .bottom)
            }
        }
    }

    func testDetachedOrEditableBarsAreNotAttached() throws {
        var nodes = fixture()
        nodes[4] = ComposerNode(id: 4, role: "AXGroup", frame: CGRect(x: 120, y: 350, width: 650, height: 28), parent: 3, children: [5])
        XCTAssertTrue(try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes)).contour.bars.isEmpty)
        nodes = fixture()
        nodes[5] = ComposerNode(id: 5, role: "AXTextField", frame: nodes[5]!.frame, parent: 4)
        XCTAssertTrue(try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes)).contour.bars.isEmpty)
        nodes = fixture()
        nodes[4] = ComposerNode(id: 4, role: "AXGroup", frame: nodes[4]!.frame, parent: 3, children: [5], childrenComplete: false)
        XCTAssertTrue(try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes)).contour.bars.isEmpty)
    }

    func testHeaderAndFooterKeepTheirOwnExposedCorners() throws {
        var nodes = fixture()
        nodes[3] = ComposerNode(id: 3, role: "AXGroup", frame: CGRect(x: 100, y: 172, width: 690, height: 186), parent: nil, children: [1, 4, 6])
        nodes[6] = ComposerNode(id: 6, role: "AXGroup", frame: CGRect(x: 120, y: 172, width: 650, height: 28), parent: 3, children: [7])
        nodes[7] = ComposerNode(id: 7, role: "AXButton", frame: CGRect(x: 140, y: 176, width: 20, height: 20), parent: 6)
        let target = try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes))
        XCTAssertEqual(target.frame, CGRect(x: 100, y: 172, width: 690, height: 186))
        XCTAssertEqual(target.contour.main.rect.minY, 28)
        XCTAssertEqual(target.contour.bars.map(\.corners), [.top, .bottom])
        XCTAssertEqual(target.contour.bars.map { $0.rect.minY }, [0, 158])
    }

    func testOutlyingControlsDoNotTurnAWrapperIntoABar() throws {
        var nodes = fixture()
        nodes[5] = ComposerNode(id: 5, role: "AXButton", frame: CGRect(x: 900, y: 334, width: 20, height: 20), parent: 4)
        XCTAssertTrue(try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes)).contour.bars.isEmpty)
    }

    func testOverlappingFooterRetainsItsConnectionAndExposedCornerRadius() throws {
        var nodes = fixture()
        nodes[4] = ComposerNode(id: 4, role: "AXGroup", frame: CGRect(x: 120, y: 310, width: 650, height: 48), parent: 3, children: [5])
        let target = try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: 0, nodes: nodes))
        XCTAssertEqual(target.contour.bars.first?.rect, CGRect(x: 20, y: 110, width: 650, height: 48))
        XCTAssertEqual(target.contour.bars.first?.radius, 14)
        XCTAssertEqual(target.contour.bounds, CGRect(x: 0, y: 0, width: 690, height: 158))
    }

    func testEditorBoundaryPresetsCanAttachBarsWithoutExpandingTheMainField() throws {
        for preset in [InputTargetPreset.x] {
            let field = CGRect(x: 100, y: 200, width: 500, height: 60)
            let nodes = [0: ComposerNode(id: 0, role: "AXTextField", frame: field, parent: 1),
                1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 500, height: 88), parent: nil, children: [0, 2]),
                2: ComposerNode(id: 2, role: "AXGroup", frame: CGRect(x: 120, y: 260, width: 460, height: 28), parent: 1, children: [3]),
                3: ComposerNode(id: 3, role: "AXButton", frame: CGRect(x: 130, y: 264, width: 20, height: 20), parent: 2)]
            let target = try XCTUnwrap(preset.resolve(editor: 0, nodes: nodes))
            XCTAssertEqual(target.contour.main.rect.size, field.size)
            XCTAssertEqual(target.contour.bars.count, 1)
        }
    }

    func testRecordedT3BrowserWrappersDoNotFlattenTheContextBar() throws {
        struct Fixture: Decodable { let editor: Int; let expected, main, bar: CGRect; let nodes: [ComposerNode] }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Composers/t3-browser.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let target = try XCTUnwrap(InputTargetPreset.t3Code.resolve(editor: fixture.editor,
            nodes: Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })))
        XCTAssertEqual(target.frame, fixture.expected)
        XCTAssertEqual(target.contour.main.rect, fixture.main)
        XCTAssertEqual(target.contour.bars.first?.rect, fixture.bar)
    }

    private func fixture() -> [Int: ComposerNode] {
        [0: ComposerNode(id: 0, role: "AXTextArea", frame: CGRect(x: 116, y: 216, width: 658, height: 80), parent: 1),
         1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 690, height: 130), parent: 3, children: [0, 2]),
         2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 750, y: 300, width: 28, height: 28), parent: 1),
         3: ComposerNode(id: 3, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 690, height: 158), parent: nil, children: [1, 4]),
         4: ComposerNode(id: 4, role: "AXGroup", frame: CGRect(x: 120, y: 330, width: 650, height: 28), parent: 3, children: [5]),
         5: ComposerNode(id: 5, role: "AXPopUpButton", frame: CGRect(x: 690, y: 334, width: 64, height: 20), parent: 4)]
    }
}
