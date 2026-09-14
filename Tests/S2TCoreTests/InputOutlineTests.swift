import XCTest
@testable import S2TCore

final class InputOutlineTests: XCTestCase {
    func testRoundedCornersFollowMeasuredInsetsAtEveryScale() {
        for scale in [CGFloat(0.5), 0.75, 1, 1.25, 1.5, 2, 3] {
            for height in [CGFloat(80), 160, 280] {
                XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 600 * scale, height: height * scale),
                    contentInset: 24 * scale), 24 * scale)
            }
        }
        XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 20, height: 100), contentInset: 24), 10)
        XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 600, height: 80), contentInset: 4), 4)
    }

    func testExactFieldBoundaryAcrossFractionalPositionsAndPanelPadding() {
        for field in [CGRect(x: 100.25, y: 200.75, width: 634.5, height: 57.25),
                      CGRect(x: -1700.5, y: 380.25, width: 500.75, height: 90.5)] {
            for padding in [1.0, 2, 5] {
                let geometry = InputOutlineGeometry(field: field, paddingScale: padding)
                let outline = geometry.outlineRect
                XCTAssertEqual(geometry.windowFrame.minX + outline.minX, field.minX)
                XCTAssertEqual(geometry.windowFrame.minX + outline.maxX, field.maxX)
                XCTAssertEqual(geometry.windowFrame.maxY - outline.maxY, field.minY)
                XCTAssertEqual(geometry.windowFrame.maxY - outline.minY, field.maxY)
            }
        }
    }

    func testMultilineGrowthDoesNotChangeCornerShape() {
        XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 600, height: 80)),
                       InputOutlineGeometry.radius(for: CGSize(width: 600, height: 240)))
        XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 600, height: 80), contentInset: 15), 15)
        XCTAssertEqual(InputOutlineGeometry.radius(for: CGSize(width: 600, height: 240), contentInset: 15), 15)
    }

    func testCapsuleRowsWithoutSearchMetadata() {
        let bounds = CGRect(x: 100, y: 200, width: 600, height: 56)
        let editor = CGRect(x: 120, y: 216, width: 520, height: 24)
        let button = CGRect(x: 650, y: 212, width: 32, height: 32)
        for scale in [CGFloat(0.75), 1, 2] {
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            XCTAssertTrue(InputOutlineGeometry.isCapsule(field: bounds.applying(transform),
                editor: editor.applying(transform), role: "AXTextArea", controls: [button.applying(transform)]))
        }
        XCTAssertTrue(InputOutlineGeometry.isCapsule(field: CGRect(x: 0, y: 0, width: 400, height: 44),
            editor: CGRect(x: 20, y: 10, width: 360, height: 24), role: "AXTextField", controls: []))
    }

    func testCapsuleDetectionRejectsFooterRowsAndTallEditors() {
        let editor = CGRect(x: 120, y: 216, width: 520, height: 64)
        let button = CGRect(x: 650, y: 292, width: 32, height: 32)
        XCTAssertFalse(InputOutlineGeometry.isCapsule(field: CGRect(x: 100, y: 200, width: 600, height: 140),
            editor: editor, role: "AXTextArea", controls: [button]))
        XCTAssertFalse(InputOutlineGeometry.isCapsule(field: CGRect(x: 100, y: 200, width: 600, height: 120),
            editor: CGRect(x: 120, y: 212, width: 520, height: 96), role: "AXTextArea",
            controls: [CGRect(x: 650, y: 244, width: 32, height: 32)]))
        XCTAssertFalse(InputOutlineGeometry.isCapsule(field: CGRect(x: 0, y: 0, width: 400, height: 44),
            editor: CGRect(x: 10, y: 10, width: 380, height: 24), role: "AXTextField", controls: []))
        XCTAssertFalse(InputOutlineGeometry.isCapsule(field: CGRect(x: 0, y: 0, width: 600, height: 100),
            editor: CGRect(x: 20, y: 10, width: 560, height: 80), role: "AXTextArea", controls: []))
    }

    func testEditableFieldsAndWebEditorsAreEligible() {
        for role in ["AXTextArea", "AXTextField"] {
            XCTAssertTrue(InputOutlineGeometry.isInput(role: role, subrole: "", editable: false))
        }
        XCTAssertTrue(InputOutlineGeometry.isInput(role: "AXComboBox", subrole: "", editable: true))
        XCTAssertFalse(InputOutlineGeometry.isInput(role: "AXComboBox", subrole: "", editable: false))
        XCTAssertTrue(InputOutlineGeometry.isInput(role: "AXGroup", subrole: "", editable: true))
        XCTAssertFalse(InputOutlineGeometry.isInput(role: "AXTextField", subrole: "AXSecureTextField", editable: true))
        for role in ["AXButton", "AXWindow", "AXWebArea", "AXStaticText"] {
            XCTAssertFalse(InputOutlineGeometry.isInput(role: role, subrole: "", editable: false))
        }
    }

    func testAccessibilityCoordinatesAcrossOffsetDisplays() {
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: 200, width: 1920, height: 1080),
                       CGRect(x: 0, y: -1080, width: 1920, height: 1080)]
        XCTAssertEqual(InputOutlineGeometry.screenFrame(accessibilityFrame: CGRect(x: -1800, y: -150, width: 600, height: 80), primaryTop: 982, screens: screens),
                       CGRect(x: -1800, y: 1052, width: 600, height: 80))
        XCTAssertEqual(InputOutlineGeometry.screenFrame(accessibilityFrame: CGRect(x: 200, y: 1100, width: 600, height: 80), primaryTop: 982, screens: screens),
                       CGRect(x: 200, y: -198, width: 600, height: 80))
    }

    func testInvalidOffscreenAndWindowSizedTargetsAreRejected() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for frame in [CGRect.zero, CGRect(x: 2000, y: 50, width: 300, height: 80),
                      CGRect(x: 0, y: 0, width: 1440, height: 900),
                      CGRect(x: 100, y: 200, width: -100, height: 50),
                      CGRect(x: CGFloat.nan, y: 0, width: 500, height: 80)] {
            XCTAssertNil(InputOutlineGeometry.screenFrame(accessibilityFrame: frame, primaryTop: 900, screens: [screen]))
        }
    }

    func testOutlinePaddingDoesNotCoverInputContents() {
        let field = CGRect(x: 100, y: 200, width: 600, height: 80)
        let layout = InputOutlineGeometry(field: field)
        XCTAssertTrue(layout.windowFrame.contains(field))
        XCTAssertEqual(layout.outlineRect.offsetBy(dx: layout.windowFrame.minX, dy: layout.windowFrame.minY), field)
        XCTAssertEqual(GlowAppearance(rawValue: "aroundInput")?.title, "Around Input")
    }

    func testFractionalFieldCoordinatesKeepTheExactBoundary() {
        let field = CGRect(x: 100.25, y: 200.75, width: 600.5, height: 80.25)
        let layout = InputOutlineGeometry(field: field)
        let local = layout.outlineRect
        XCTAssertEqual(layout.windowFrame.minX + local.minX, field.minX)
        XCTAssertEqual(layout.windowFrame.maxY - local.maxY, field.minY)
        XCTAssertEqual(local.size, field.size)
    }
}
