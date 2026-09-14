import Foundation
import CoreGraphics

public enum InputCornerStyle: String, Codable, Sendable {
    case continuous, circular
}

public struct InputOutlineTarget {
    public let frame: CGRect
    public let cornerRadius: CGFloat
    public let cornerStyle: InputCornerStyle
    public init(frame: CGRect, cornerRadius: CGFloat, cornerStyle: InputCornerStyle = .continuous) {
        self.frame = frame; self.cornerRadius = cornerRadius; self.cornerStyle = cornerStyle
    }
}

public struct InputOutlineGeometry: Equatable {
    public static let colorExtent: CGFloat = 72
    public static let backdropExtent: CGFloat = 104
    public static let padding: CGFloat = ceil(ChromaPreset.box.fieldExtent) + 12
    public let windowFrame: CGRect
    public let outlineRect: CGRect
    public let cornerRadius: CGFloat

    public init(field: CGRect, paddingScale: Double = 1, displayFrame: CGRect? = nil) {
        let padded = field.insetBy(dx: -Self.padding * max(1, paddingScale), dy: -Self.padding * max(1, paddingScale)).integral
        if let displayFrame, paddingScale > 1, displayFrame.contains(field) {
            windowFrame = padded.intersection(displayFrame)
        } else { windowFrame = padded }
        outlineRect = CGRect(x: field.minX - windowFrame.minX, y: windowFrame.maxY - field.maxY, width: field.width, height: field.height)
        cornerRadius = Self.radius(for: field.size)
    }

    public static func radius(for size: CGSize, contentInset: CGFloat? = nil, capsule: Bool = false) -> CGFloat {
        if capsule { return size.height / 2 }
        let inset = contentInset.flatMap { $0.isFinite ? $0 : nil } ?? 12
        return min(min(size.width, size.height) / 2, max(0, inset))
    }

    public static func isCapsule(field: CGRect, editor: CGRect, role: String, controls: [CGRect]) -> Bool {
        guard field.height > 0, editor.height > 0, field.width >= field.height * 3,
              field.contains(editor) else { return false }
        let top = editor.minY - field.minY
        let bottom = field.maxY - editor.maxY
        if controls.isEmpty {
            guard role == "AXTextField" || role == "AXComboBox" else { return false }
            let endInset = min(editor.minX - field.minX, field.maxX - editor.maxX)
            return top > 0 && bottom > 0 && abs(top - bottom) <= editor.height * 0.2
                && endInset >= max(field.height * 0.3, max(top, bottom) * 1.5)
                && field.height <= editor.height * 2.5
        }
        guard controls.allSatisfy({ $0.width > 0 && $0.height > 0 && field.contains($0) }) else { return false }
        let sizes = controls.map { min($0.width, $0.height) }.sorted()
        let unit = sizes[sizes.count / 2]
        guard editor.height <= unit * 1.5, field.height >= unit * 1.2, field.height <= unit * 2.6,
              abs(editor.midY - field.midY) <= unit * 0.2,
              controls.allSatisfy({ abs($0.midY - field.midY) <= unit * 0.2 && $0.height <= unit * 1.5 }) else { return false }
        let radius = field.height / 2
        return (controls + [editor]).allSatisfy { content in
            let vertical = max(abs(content.minY - field.midY), abs(content.maxY - field.midY))
            let endInset = radius - sqrt(max(0, radius * radius - vertical * vertical))
            return content.minX >= field.minX + endInset && content.maxX <= field.maxX - endInset
        }
    }

    public static func isInput(role: String, subrole: String, editable: Bool) -> Bool {
        guard subrole != "AXSecureTextField" else { return false }
        return ["AXTextArea", "AXTextField"].contains(role)
            || (editable && ["AXGroup", "AXLayoutArea", "AXComboBox", "AXUnknown"].contains(role))
    }

    public static func screenFrame(accessibilityFrame frame: CGRect, primaryTop: CGFloat, screens: [CGRect]) -> CGRect? {
        guard [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, primaryTop].allSatisfy(\.isFinite),
              frame.size.width >= 30, frame.size.height >= 8 else { return nil }
        let converted = CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
        guard let screen = screens.max(by: { area($0.intersection(converted)) < area($1.intersection(converted)) }),
              area(screen.intersection(converted)) >= area(converted) * 0.85,
              converted.height <= screen.height * 0.65, area(converted) < area(screen) * 0.65 else { return nil }
        return converted
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
