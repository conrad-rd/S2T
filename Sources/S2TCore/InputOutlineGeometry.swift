import Foundation
import CoreGraphics

public enum InputCornerStyle: String, Codable, Sendable {
    case continuous, circular
}

public struct InputOutlineTarget {
    public enum Kind { case input, focusedWindow }
    public let kind: Kind
    public let frame: CGRect
    public let contour: InputContour
    public var cornerRadius: CGFloat { contour.main.radius }
    public var cornerStyle: InputCornerStyle { contour.main.style }
    public init(frame: CGRect, cornerRadius: CGFloat, cornerStyle: InputCornerStyle = .continuous, kind: Kind = .input) {
        self.kind = kind
        self.frame = frame
        contour = InputContour(rect: CGRect(origin: .zero, size: frame.size), radius: cornerRadius, style: cornerStyle)
    }
    public init(contour: InputContour, kind: Kind = .input) {
        self.kind = kind
        frame = contour.bounds
        self.contour = contour.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }
    public init(frame: CGRect, contour: InputContour, kind: Kind = .input) {
        self.kind = kind
        self.frame = frame; self.contour = contour
    }

    public func onScreens(primaryTop: CGFloat, screens: [CGRect]) -> InputOutlineTarget? {
        guard var converted = InputOutlineGeometry.screenFrame(accessibilityFrame: frame,
            primaryTop: primaryTop, screens: screens, kind: kind) else { return nil }
        if kind == .focusedWindow {
            // Leave a visible edge when an exterior outline would fall off the display.
            if let display = screens.first(where: { $0.contains(converted) }) {
                let left: CGFloat = abs(converted.minX - display.minX) < 1 ? 3 : 0
                let right: CGFloat = abs(converted.maxX - display.maxX) < 1 ? 3 : 0
                let bottom: CGFloat = abs(converted.minY - display.minY) < 1 ? 3 : 0
                let top: CGFloat = abs(converted.maxY - display.maxY) < 1 ? 3 : 0
                converted = CGRect(x: converted.minX + left, y: converted.minY + bottom,
                    width: converted.width - left - right, height: converted.height - top - bottom)
            }
            return InputOutlineTarget(frame: converted, cornerRadius: cornerRadius, cornerStyle: cornerStyle, kind: kind)
        }
        return InputOutlineTarget(frame: converted, contour: contour, kind: kind)
    }
}

public struct InputOutlineGeometry: Equatable {
    public static let colorExtent: CGFloat = 72
    public static let backdropExtent: CGFloat = 104
    public static let padding: CGFloat = ceil(ChromaPreset.box.fieldExtent) + 12
    public let windowFrame: CGRect
    public let outlineRect: CGRect
    public let cornerRadius: CGFloat

    public init(field: CGRect, paddingScale: Double = 1, displayFrame: CGRect? = nil, clipsToDisplay: Bool = false) {
        let padded = field.insetBy(dx: -Self.padding * max(1, paddingScale), dy: -Self.padding * max(1, paddingScale)).integral
        if let displayFrame, clipsToDisplay || (paddingScale > 1 && displayFrame.contains(field)) {
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

    public static func screenFrame(accessibilityFrame frame: CGRect, primaryTop: CGFloat, screens: [CGRect], kind: InputOutlineTarget.Kind = .input) -> CGRect? {
        guard [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, primaryTop].allSatisfy(\.isFinite),
              frame.size.width >= 30, frame.size.height >= 8 else { return nil }
        let converted = CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
        if kind == .focusedWindow {
            return screens.contains(where: { area($0.intersection(converted)) >= 240 }) ? converted : nil
        }
        guard let screen = screens.max(by: { area($0.intersection(converted)) < area($1.intersection(converted)) }),
              area(screen.intersection(converted)) >= area(converted) * 0.85,
              converted.height <= screen.height * 0.65, area(converted) < area(screen) * 0.65 else { return nil }
        return converted
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
