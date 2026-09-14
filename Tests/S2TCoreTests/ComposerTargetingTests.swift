import XCTest
@testable import S2TCore

final class ComposerTargetingTests: XCTestCase {
    private func node(_ id: Int, _ role: String, _ frame: CGRect?, _ parent: Int?, _ children: [Int] = [], editable: Bool = false) -> ComposerNode {
        ComposerNode(id: id, role: role, editable: editable, frame: frame, parent: parent, children: children)
    }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    private func target(_ nodes: [ComposerNode]) -> CGRect? { ComposerTargeting.resolve(editor: 0, nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })) }

    func testMeasuredAccessibilityTrees() throws {
        struct Fixture: Decodable { let name: String; let editor: Int; let expected: CGRect; let nodes: [ComposerNode] }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Composers")
        for name in ["chatgpt", "gemini", "nested-horizontal", "search-with-suggestions", "composer-with-select-controls"] {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
            XCTAssertEqual(ComposerTargeting.resolve(editor: fixture.editor, nodes: Dictionary(uniqueKeysWithValues: fixture.nodes.map { ($0.id, $0) })), fixture.expected, fixture.name)
            if ["chatgpt", "gemini", "composer-with-select-controls"].contains(name),
               let editor = fixture.nodes.first(where: { $0.id == fixture.editor }), let frame = editor.frame {
                let controls = fixture.nodes.filter { ComposerTargeting.controlRoles.contains($0.role) }
                    .compactMap(\.frame).filter { fixture.expected.contains($0) }
                XCTAssertEqual(InputOutlineGeometry.isCapsule(field: fixture.expected, editor: frame,
                    role: editor.role, controls: controls), name != "composer-with-select-controls", fixture.name)
            }
        }
    }

    func testIncludesBothSideControlsAndFooterInsteadOfFirstAccessoryGroup() {
        let input = rect(150, 100, 450, 60)
        let inner = rect(100, 90, 560, 80), outer = rect(100, 90, 560, 130)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", inner, 3, [0, 2]),
            node(2, "AXButton", rect(610, 115, 30, 30), 1),
            node(3, "AXGroup", outer, 6, [1, 4, 5]),
            node(4, "AXPopUpButton", rect(110, 175, 130, 30), 3), node(5, "AXButton", rect(610, 175, 30, 30), 3),
            node(6, "AXGroup", rect(80, 60, 600, 180), nil, [3])
        ]), outer)
    }

    func testHorizontalChatWithAccessoriesOnBothSidesAndLargeHorizontalInset() {
        let input = rect(200, 400, 300, 28), composer = rect(95, 386, 525, 58)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", composer, nil, [2, 3, 0, 4, 5]),
            node(2, "AXButton", rect(105, 397, 32, 32), 1), node(3, "AXButton", rect(150, 397, 32, 32), 1),
            node(4, "AXButton", rect(520, 397, 32, 32), 1), node(5, "AXButton", rect(565, 397, 32, 32), 1)
        ]), composer)
    }

    func testFrameLessWrappersAndControlsWhoseBoundsOverlapEditor() {
        let input = rect(100, 100, 600, 100), composer = rect(90, 90, 620, 120)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", composer, nil, [0, 2]),
            node(2, "AXGroup", nil, 1, [3]), node(3, "AXToolbar", input, 2, [4]),
            node(4, "AXButton", rect(650, 155, 32, 32), 3)
        ]), composer)
    }

    func testNativeScrollableTextViewUsesVisibleViewport() {
        let viewport = rect(100, 100, 500, 100), composer = rect(90, 90, 520, 155)
        XCTAssertEqual(target([
            node(0, "AXTextArea", rect(100, -900, 500, 1500), 1),
            node(1, "AXScrollArea", viewport, 2, [0]), node(2, "AXGroup", composer, nil, [1, 3]),
            node(3, "AXButton", rect(560, 205, 32, 30), 2)
        ]), composer)
    }

    func testSemanticFormAndScaledLayoutsDoNotDependOnPixelConstants() {
        for scale in [CGFloat(0.65), 1, 1.5, 2] {
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { rect(x * scale, y * scale, w * scale, h * scale) }
            let composer = r(80, 80, 640, 200)
            XCTAssertEqual(target([
                node(0, "AXTextArea", r(100, 100, 600, 110), 1), node(1, "AXForm", composer, nil, [0, 2]),
                node(2, "AXToolbar", r(100, 225, 600, 35), 1, [3]), node(3, "AXButton", r(650, 225, 35, 35), 2)
            ]), composer)
        }
    }

    func testDoesNotExpandIntoConversationOrUnrelatedInput() {
        let input = rect(120, 620, 560, 60), composer = rect(100, 600, 600, 120)
        for foreignRole in ["AXTextArea", "AXList", "AXTable", "AXStaticText"] {
            XCTAssertEqual(target([
                node(0, "AXTextArea", input, 1), node(1, "AXGroup", composer, 3, [0, 2]),
                node(2, "AXButton", rect(640, 680, 35, 30), 1),
                node(3, "AXGroup", rect(80, 100, 640, 650), nil, [1, 4, 5]),
                node(4, foreignRole, rect(100, 110, 600, 470), 3), node(5, "AXButton", rect(650, 110, 30, 30), 3)
            ]), composer)
        }
    }

    func testPlainFieldAndModestPaddedContainerWithoutButtons() {
        let input = rect(100, 100, 500, 40)
        XCTAssertEqual(target([node(0, "AXTextField", input, nil)]), input)
        let padded = rect(92, 92, 516, 56)
        XCTAssertEqual(target([node(0, "AXTextArea", input, 1), node(1, "AXGroup", padded, nil, [0])]), padded)
    }

    func testMissingOrAmbiguousMetadataDoesNotInventAComposer() {
        XCTAssertNil(target([node(0, "AXTextArea", nil, nil)]))
        let input = rect(100, 100, 500, 40)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", rect(90, 90, 520, 110), nil, [0, 2]),
            node(2, "AXTextField", rect(100, 160, 300, 30), 1)
        ]), input)
    }

    func testIncompleteAncestorCannotReplaceKnownInput() {
        let input = rect(100, 100, 500, 40)
        let incomplete = ComposerNode(id: 1, role: "AXGroup", frame: rect(90, 90, 520, 100), parent: nil,
                                     children: [0, 2], childrenComplete: false)
        XCTAssertEqual(target([node(0, "AXTextArea", input, 1), incomplete,
                               node(2, "AXButton", rect(550, 150, 30, 30), 1)]), input)
    }

    func testDeepTransparentWrappersDoNotPreventBoundaryDetection() {
        let input = rect(100, 100, 500, 40), composer = rect(85, 85, 530, 100)
        var nodes = [node(0, "AXTextArea", input, 1)]
        for id in 1...18 { nodes.append(node(id, "AXGroup", id.isMultiple(of: 2) ? input : nil, id + 1, [id - 1])) }
        nodes.append(node(19, "AXGroup", composer, nil, [18, 20]))
        nodes.append(node(20, "AXButton", rect(555, 150, 30, 25), 19))
        XCTAssertEqual(target(nodes), composer)
    }

    func testClimbsPastControlRowToItsImmediateBorderWrapper() {
        let input = rect(508, 887, 704, 38)
        let row = rect(466, 887, 848, 38), border = rect(466, 886, 856, 39)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", row, 4, [0, 2, 3]),
            node(2, "AXButton", rect(476, 895, 22, 22), 1), node(3, "AXButton", rect(1280, 895, 22, 22), 1),
            node(4, "AXGroup", border, 5, [1]), node(5, "AXGroup", rect(460, 886, 867, 44), nil, [4])
        ]), border)
    }

    func testDoesNotMergeSeparateSideButtonIntoEstablishedSearchBox() {
        let input = rect(100, 100, 400, 40), search = rect(90, 95, 470, 50)
        XCTAssertEqual(target([
            node(0, "AXTextField", input, 1), node(1, "AXGroup", search, 3, [0, 2]),
            node(2, "AXButton", rect(510, 105, 35, 30), 1),
            node(3, "AXGroup", rect(90, 95, 535, 50), nil, [1, 4]),
            node(4, "AXButton", rect(575, 105, 35, 30), 3)
        ]), search)
    }

    func testEditableAncestorsBelongToTheSameInput() {
        for role in ["AXGroup", "AXComboBox"] {
            let input = rect(100, 100, 500, 40), composer = rect(88, 88, 524, 100)
            XCTAssertEqual(target([
                node(0, "AXTextField", input, 1), node(1, role, input, 2, [0], editable: true),
                node(2, "AXGroup", composer, nil, [1, 3]),
                node(3, "AXButton", rect(570, 145, 30, 30), 2)
            ]), composer)
        }
    }

    func testNestedPaddingDoesNotStopAtTheInnerWrapper() {
        let input = rect(100, 100, 500, 24), border = rect(88, 88, 524, 48)
        XCTAssertEqual(target([
            node(0, "AXTextField", input, 1), node(1, "AXGroup", input.insetBy(dx: -2, dy: -2), 2, [0]),
            node(2, "AXGroup", border, 3, [1]), node(3, "AXGroup", rect(50, 50, 700, 500), nil, [2])
        ]), border)
    }

    func testCyclesAreBounded() {
        let input = rect(100, 100, 500, 40)
        XCTAssertEqual(target([node(0, "AXTextArea", input, 1), node(1, "AXGroup", input, 1, [0, 1])]), input)
    }

    func testSplitAccessoryGroupsAcrossScalesAndWrapperDepths() {
        for scale in [CGFloat(0.75), 1, 1.5, 2] {
            for depth in [0, 2, 8, 16] {
                func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { rect(x * scale, y * scale, w * scale, h * scale) }
                let input = r(160, 100, 400, 40)
                let half = r(100, 90, 460, 60), whole = r(100, 90, 510, 60)
                var nodes = [node(0, "AXTextArea", input, depth == 0 ? 30 : 1)]
                if depth > 0 {
                    for id in 1...depth {
                        nodes.append(node(id, "AXGroup", input, id == depth ? 30 : id + 1, [id - 1]))
                    }
                }
                nodes += [node(30, "AXGroup", half, 31, [depth == 0 ? 0 : depth, 32]),
                          node(31, "AXGroup", whole, 34, [30, 33]),
                          node(32, "AXButton", r(115, 105, 30, 30), 30),
                          node(33, "AXButton", r(565, 105, 30, 30), 31),
                          node(34, "AXGroup", r(80, 20, 900, 700), nil, [31])]
                XCTAssertEqual(target(nodes), whole, "scale \(scale), depth \(depth)")
            }
        }
    }

    func testAttachmentListBelongsToComposerButMessageListDoesNot() {
        let input = rect(100, 150, 500, 50), composer = rect(88, 70, 524, 185)
        XCTAssertEqual(target([
            node(0, "AXTextArea", input, 1), node(1, "AXGroup", composer, 6, [0, 2, 5]),
            node(2, "AXList", rect(100, 82, 220, 54), 1, [3, 4]),
            node(3, "AXStaticText", rect(112, 102, 140, 18), 2),
            node(4, "AXButton", rect(282, 90, 26, 26), 2),
            node(5, "AXButton", rect(565, 215, 30, 30), 1),
            ComposerNode(id: 6, role: "AXGroup", subrole: "AXLandmarkMain", frame: rect(70, 10, 700, 300), parent: nil, children: [1, 7]),
            node(7, "AXList", rect(80, 12, 650, 48), 6, [8, 9]),
            node(8, "AXStaticText", rect(120, 20, 400, 20), 7),
            node(9, "AXButton", rect(680, 20, 24, 24), 7)
        ]), composer)
    }
}
