import XCTest
@testable import S2TCore

final class InputTargetPresetTests: XCTestCase {
    func testRoundedPresetCornersScaleWithControlsInsteadOfEditorHeight() throws {
        for preset in InputTargetPreset.allCases where preset.usesComposerBoundary {
            let controlSize: CGFloat = preset == .chatGPT ? 30 : preset == .gemini ? 29 : 28
            var baseRadius: CGFloat?
            for scale in [CGFloat(1), 0.5, 0.75, 1.25, 1.5, 2, 3] {
                for growth in [CGFloat(0), 60, 140] {
                    let transform = CGAffineTransform(scaleX: scale, y: scale)
                    let field = CGRect(x: 100, y: 200, width: 600, height: 96 + growth).applying(transform)
                    let editor = CGRect(x: 120, y: 216, width: 560, height: 32 + growth).applying(transform)
                    let button = CGRect(x: 640, y: 258 + growth, width: controlSize, height: controlSize).applying(transform)
                    var nodes = [0: ComposerNode(id: 0, role: "AXTextArea", frame: editor, parent: 1),
                                 1: ComposerNode(id: 1, role: "AXGroup", frame: field, parent: nil, children: [0, 2]),
                                 2: ComposerNode(id: 2, role: "AXButton", frame: button, parent: 1)]
                    let target = try XCTUnwrap(preset.resolve(editor: 0, nodes: nodes), preset.title)
                    if baseRadius == nil { baseRadius = target.cornerRadius }
                    XCTAssertEqual(target.cornerRadius, baseRadius! * scale, accuracy: 0.00001, preset.title)
                    nodes[1] = ComposerNode(id: 1, role: "AXGroup", frame: field, parent: nil, children: [0, 2, 3, 4])
                    for id in [3, 4] {
                        nodes[id] = ComposerNode(id: id, role: "AXPopUpButton",
                            frame: CGRect(x: CGFloat(130 + (id - 3) * 120), y: 248 + growth, width: 100, height: 40).applying(transform), parent: 1)
                    }
                    XCTAssertEqual(preset.resolve(editor: 0, nodes: nodes)?.cornerRadius, target.cornerRadius,
                        "Adding wide model selectors must not change the corner radius")
                }
            }
        }
    }

    func testNativeAndWebsiteIdentity() {
        let apps: [(String, InputTargetPreset)] = [
            ("com.anthropic.claudefordesktop", .claude), ("com.openai.chat", .chatGPT),
            ("com.hnc.Discord", .discord), ("net.whatsapp.WhatsApp", .whatsApp),
            ("ru.keepcoder.Telegram", .telegram), ("com.apple.MobileSMS", .messages),
            ("com.t3tools.t3code", .t3Code), ("com.openai.codex", .codex),
            ("com.apple.Safari", .safari), ("com.apple.Terminal", .terminal),
            ("com.mitchellh.ghostty", .terminal)
        ]
        for (bundle, expected) in apps {
            XCTAssertEqual(InputTargetPreset.match(bundleID: bundle, webURL: nil, inWebContent: false), expected)
        }
        let sites: [(String, InputTargetPreset)] = [
            ("https://claude.ai/new", .claude), ("https://chatgpt.com/c/123", .chatGPT),
            ("https://x.com/compose/post", .x), ("https://discord.com/channels/@me", .discord),
            ("https://web.whatsapp.com/", .whatsApp), ("https://web.telegram.org/a/", .telegram),
            ("https://gemini.google.com/app", .gemini), ("https://www.google.de/search?q=private", .google)
        ]
        for (url, expected) in sites {
            XCTAssertEqual(InputTargetPreset.match(bundleID: "com.apple.Safari", webURL: URL(string: url), inWebContent: true), expected)
        }
        XCTAssertNil(InputTargetPreset.match(bundleID: "com.apple.Safari", webURL: URL(string: "https://unrelated.test"), inWebContent: true))
        XCTAssertNil(InputTargetPreset.match(bundleID: "unknown", webURL: URL(string: "https://chatgpt.com.evil.test"), inWebContent: true))
        XCTAssertNil(InputTargetPreset.match(bundleID: "unknown", webURL: URL(string: "https://evilchatgpt.com"), inWebContent: true))
        XCTAssertNil(InputTargetPreset.match(bundleID: "unknown", webURL: URL(string: "https://chatgpt.com"), inWebContent: false))
    }

    func testPresetsFitPreviouslyMeasuredLayoutsWithoutAutomaticResolver() throws {
        struct Fixture: Decodable { let editor: Int; let expected: CGRect; let nodes: [ComposerNode] }
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Composers")
        for (name, preset) in [("chatgpt", InputTargetPreset.chatGPT), ("gemini", .gemini)] {
            let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
            for scale in [CGFloat(0.75), 1, 1.5, 2] {
                let transform = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: 30, y: -20)
                let nodes = Dictionary(uniqueKeysWithValues: fixture.nodes.map { node in
                    (node.id, ComposerNode(id: node.id, role: node.role, subrole: node.subrole, editable: node.editable,
                        frame: node.frame?.applying(transform), parent: node.parent, children: node.children, childrenComplete: node.childrenComplete))
                })
                let target = preset.resolve(editor: fixture.editor, nodes: nodes)
                XCTAssertEqual(target?.frame, fixture.expected.applying(transform), name)
                XCTAssertEqual(target?.cornerRadius, fixture.expected.height * scale / 2, "Known capsule ends must match the field exactly at every zoom level")
                XCTAssertEqual(target?.cornerStyle, .circular)
            }
        }
    }

    func testComposerPresetsRejectOtherFieldsAndIncompleteTrees() {
        for preset in InputTargetPreset.allCases where preset.usesComposerBoundary {
            let input = CGRect(x: 150, y: 420, width: 400, height: 30)
            let boundary = CGRect(x: 100, y: 400, width: 500, height: 70)
            let leaf = ComposerNode(id: 0, role: "AXTextArea", frame: input, parent: 1)
            let button = ComposerNode(id: 2, role: "AXButton", frame: CGRect(x: 560, y: 420, width: 28, height: 28), parent: 1)
            let group = ComposerNode(id: 1, role: "AXGroup", frame: boundary, parent: nil, children: [0, 2])
            XCTAssertEqual(preset.resolve(editor: 0, nodes: [0: leaf, 1: group, 2: button])?.frame, boundary, preset.rawValue)
            let sibling = ComposerNode(id: 2, role: "AXTextField", frame: button.frame, parent: 1)
            XCTAssertNil(preset.resolve(editor: 0, nodes: [0: leaf, 1: group, 2: sibling]), preset.rawValue)
            let incomplete = ComposerNode(id: 1, role: "AXGroup", frame: boundary, parent: nil, children: [0, 2], childrenComplete: false)
            XCTAssertNil(preset.resolve(editor: 0, nodes: [0: leaf, 1: incomplete, 2: button]), preset.rawValue)
            let secure = ComposerNode(id: 0, role: "AXTextArea", subrole: "AXSecureTextField", frame: input, parent: 1)
            XCTAssertNil(preset.resolve(editor: 0, nodes: [0: secure, 1: group, 2: button]), preset.rawValue)
        }
    }

    func testTerminalUsesCaretLineAndNeverTheScrollbackDocument() {
        let viewport = CGRect(x: 100, y: 100, width: 900, height: 700)
        let caret = CGRect(x: 330, y: 640, width: 0, height: 18)
        let result = InputTargetPreset.terminalTarget(viewport: viewport, caret: caret)
        XCTAssertEqual(result?.frame, CGRect(x: 100, y: 635.5, width: 900, height: 27))
        XCTAssertNil(InputTargetPreset.terminalTarget(viewport: viewport, caret: CGRect(x: 330, y: 900, width: 0, height: 18)))
        XCTAssertNil(InputTargetPreset.terminalTarget(viewport: viewport, caret: .zero))
    }
}
