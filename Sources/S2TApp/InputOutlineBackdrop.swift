import AppKit
import SwiftUI
import S2TCore

struct InputOutlineBackdrop: Equatable {
    static let maximumBlurRadius = BrighterEdgeStyle.Mode.input.blurRadius
    var contour: InputContour
    var rect: CGRect { contour.bounds }
    var cornerRadius: CGFloat { contour.main.radius }
    var cornerStyle: InputCornerStyle { contour.main.style }
    var withinInput = false
    var geometry: ChromaAppearance.Geometry { withinInput ? .withinInput(contour) : .input(contour) }
    var strength: Double = 1

    init(rect: CGRect, cornerRadius: CGFloat, cornerStyle: InputCornerStyle = .continuous, strength: Double = 1) {
        contour = InputContour(rect: rect, radius: cornerRadius, style: cornerStyle)
        self.strength = strength
    }
    init(contour: InputContour, strength: Double = 1, withinInput: Bool = false) { self.contour = contour; self.strength = strength; self.withinInput = withinInput }
    var path: Path { contour.path }

    func colorMask(size: NSSize, scale: CGFloat, highlight: Bool = false) -> NSImage? {
        guard let assets = ChromaAppearance.assets(geometry: geometry, size: size) else { return nil }
        return highlight ? assets.edge : assets.color
    }

    func mask(size: NSSize, distortion: GlowDistortion = .identity, expansion: Double = 1, falloff: Double = 1) -> NSImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        if withinInput {
            return ChromaAppearance.radiusMap(geometry: geometry, size: size, distortion: distortion,
                exterior: WithinInputField(contour: contour).clipPath, expansion: expansion, falloff: falloff)
        }
        var exterior = Path(CGRect(origin: .zero, size: size))
        exterior.addPath(path)
        return ChromaAppearance.radiusMap(geometry: geometry, size: size,
            distortion: distortion, exterior: exterior, expansion: expansion, falloff: falloff)
    }
}
