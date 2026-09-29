import XCTest
@testable import S2TCore

final class AutomaticComposerTests: XCTestCase {
    func testMeasuredNativeAddressContainerIncludesItsButton() throws {
        struct Fixture: Decodable { let editor: Int; let expected: CGRect; let nodes: [ComposerNode] }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Composers/safari-address.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let nodes = Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })
        assertRect(try XCTUnwrap(InputTargetPreset.safari.resolve(editor: fixture.editor, nodes: nodes)).frame, fixture.expected)
        assertRect(try XCTUnwrap(ComposerTargeting.resolveTarget(editor: fixture.editor, nodes: nodes)).frame, fixture.expected)
    }

    func testExistingLayoutsKeepTheirMeasuredBoundary() throws {
        struct Fixture: Decodable { let editor: Int; let expected: CGRect; let nodes: [ComposerNode] }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Composers")
        for name in ["chatgpt", "gemini", "nested-horizontal", "search-with-suggestions", "composer-with-select-controls"] {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: fixture.editor,
                nodes: Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })))
            assertRect(target.frame, fixture.expected)
            XCTAssertTrue(target.contour.bars.isEmpty, name)
        }
    }

    func testRecordedComposersWithoutAppIdentity() throws {
        struct Fixture: Decodable {
            let editor: Int
            let expected, main, bar: CGRect
            let nodes: [ComposerNode]
        }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Composers")
        for name in ["codex-extended", "t3-browser"] {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
            for scale in [CGFloat(0.65), 1, 1.5, 2] {
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let nodes = Dictionary(uniqueKeysWithValues: fixture.nodes.map { node in
                    (node.id, ComposerNode(id: node.id, role: node.role, subrole: node.subrole, editable: node.editable,
                        frame: node.frame?.applying(transform), parent: node.parent, children: node.children,
                        childrenComplete: node.childrenComplete))
                })
                let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: fixture.editor, nodes: nodes))
                assertRect(target.frame, fixture.expected.applying(transform))
                assertRect(target.contour.main.rect, fixture.main.applying(transform))
                XCTAssertEqual(target.contour.bars.count, 1, name)
                assertRect(try XCTUnwrap(target.contour.bars.first).rect, fixture.bar.applying(transform))
            }
        }
    }

    func testUnfamiliarComposerWithBothAttachments() throws {
        let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: fixture()))
        XCTAssertEqual(target.frame, CGRect(x: 100, y: 176, width: 600, height: 172))
        XCTAssertEqual(target.contour.main.rect, CGRect(x: 0, y: 24, width: 600, height: 120))
        XCTAssertEqual(target.contour.bars.map(\.corners), [.top, .bottom])
        XCTAssertEqual(target.contour.bars.map(\.rect), [CGRect(x: 16, y: 0, width: 568, height: 28),
                                                       CGRect(x: 20, y: 136, width: 560, height: 36)])
    }

    func testUnrelatedDetachedEditableAndIncompleteAttachmentsStayOutside() throws {
        for mode in 0..<4 {
            var nodes = fixture()
            let frame = mode == 0 ? CGRect(x: 120, y: 340, width: 560, height: 36) : nodes[5]!.frame
            nodes[5] = ComposerNode(id: 5, role: "AXGroup", frame: frame, parent: 3, children: [6], childrenComplete: mode != 2)
            if mode == 1 || mode == 3 {
                nodes[6] = ComposerNode(id: 6, role: mode == 1 ? "AXTextField" : "AXList", frame: nodes[6]!.frame, parent: 5)
            }
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
            XCTAssertFalse(target.contour.bars.contains { $0.corners == .bottom }, "mode \(mode)")
            XCTAssertEqual(target.contour.main.rect.size, CGSize(width: 600, height: 120))
        }
    }

    func testIncompleteOrAmbiguousContainerFallsBackToConfirmedEditor() throws {
        let field = CGRect(x: 120, y: 220, width: 500, height: 40)
        for incomplete in [false, true] {
            let nodes = [0: ComposerNode(id: 0, role: "AXTextArea", frame: field, parent: 1),
                1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 600, height: 120), parent: nil,
                    children: [0, 2], childrenComplete: !incomplete),
                2: ComposerNode(id: 2, role: "AXTextField", frame: CGRect(x: 120, y: 270, width: 500, height: 30), parent: 1)]
            let target = try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes))
            XCTAssertEqual(target.frame, field)
            XCTAssertTrue(target.contour.bars.isEmpty)
        }
    }

    func testCenteredSingleLineFieldUsesCapsuleGeometry() throws {
        let field = CGRect(x: 120, y: 110, width: 360, height: 20)
        let nodes = [0: ComposerNode(id: 0, role: "AXTextField", frame: field, parent: 1),
                     1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 100, width: 400, height: 40), parent: nil, children: [0])]
        XCTAssertEqual(try XCTUnwrap(ComposerTargeting.resolveTarget(editor: 0, nodes: nodes)).cornerRadius, 20)
    }

    private func fixture() -> [Int: ComposerNode] {
        [0: ComposerNode(id: 0, role: "AXTextArea", frame: CGRect(x: 116, y: 216, width: 568, height: 50), parent: 1),
         1: ComposerNode(id: 1, role: "AXGroup", frame: CGRect(x: 100, y: 200, width: 600, height: 120), parent: 3, children: [0, 2]),
         2: ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 656, y: 280, width: 28, height: 28), parent: 1),
         3: ComposerNode(id: 3, role: "AXGroup", frame: CGRect(x: 80, y: 176, width: 640, height: 172), parent: nil, children: [1, 4, 5]),
         4: ComposerNode(id: 4, role: "AXGroup", frame: CGRect(x: 116, y: 176, width: 568, height: 28), parent: 3, children: [7]),
         5: ComposerNode(id: 5, role: "AXGroup", frame: CGRect(x: 120, y: 312, width: 560, height: 36), parent: 3, children: [6]),
         6: ComposerNode(id: 6, role: "AXButton", frame: CGRect(x: 630, y: 324, width: 20, height: 20), parent: 5),
         7: ComposerNode(id: 7, role: "AXPopUpButton", frame: CGRect(x: 130, y: 180, width: 100, height: 20), parent: 4)]
    }

    private func assertRect(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
