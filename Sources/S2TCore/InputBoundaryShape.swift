import Foundation
import CoreGraphics

/// Shape uncertainty must not displace a successfully located field.
enum InputBoundaryShape {
    struct Estimate { let radius: CGFloat; let capsule: Bool }

    static func infer(field: CGRect, editor: CGRect, role: String, subrole: String, controls: [CGRect]) -> Estimate {
        let sizes = controls.map { min($0.width, $0.height) }.filter { $0 > 1 }.sorted()
        let unit = sizes.isEmpty ? nil : sizes[sizes.count / 2]
        // AX editor rectangles include caret/line-box padding. Requiring their
        // corners to fit a circle rejects native address and search controls.
        let compactRow = unit.map { unit in
            field.width >= field.height * 3 && field.height >= unit * 1.2 && field.height <= unit * 2.6
                && editor.height <= unit * 1.5 && abs(editor.midY - field.midY) <= unit * 0.5
                && controls.allSatisfy { field.contains($0) && abs($0.midY - field.midY) <= unit * 0.25 && $0.height <= unit * 1.5 }
        } ?? false
        if compactRow || subrole == "AXSearchField"
            || InputOutlineGeometry.isCapsule(field: field, editor: editor, role: role, controls: controls) {
            return Estimate(radius: field.height / 2, capsule: true)
        }
        // A footer and wrapped text change the bottom inset. Use matching side
        // and top spacing instead, so corners do not grow with multiline height.
        let spacing = [editor.minX - field.minX, field.maxX - editor.maxX, editor.minY - field.minY]
            .filter { $0 > 0 && $0.isFinite }.sorted()
        let pairs = zip(spacing, spacing.dropFirst()).filter { low, high in high - low <= high * 0.25 }
        // Prefer the matching pair over a smaller unrelated inset from an AX
        // editor that extends toward one edge.
        let cornerBudget = min(field.width, field.height) / 2
        // Matching side gaps may reserve entire buttons. They cannot describe
        // corners larger than the field allows; retain the smaller inset then.
        let measured = pairs.first.map { $0.0 <= cornerBudget ? $0.0 : spacing[0] }
        let fallback = unit.map { $0 / 2 } ?? (role == "AXTextField" || role == "AXComboBox" ? editor.height * 0.2 : 12)
        let radius = InputOutlineGeometry.radius(for: field.size, contentInset: measured ?? fallback)
        return Estimate(radius: radius, capsule: false)
    }
}
