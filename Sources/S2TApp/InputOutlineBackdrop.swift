import AppKit
import SwiftUI
import S2TCore

struct InputOutlineBackdrop: Equatable {
    static let maximumBlurRadius = BrighterEdgeStyle.Mode.input.blurRadius
    let rect: CGRect
    let cornerRadius: CGFloat
    var cornerStyle: InputCornerStyle = .continuous
    var strength: Double = 1

    var path: Path {
        cornerRadius >= rect.height / 2
            ? Capsule(style: .circular).path(in: rect)
            : RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle == .circular ? .circular : .continuous).path(in: rect)
    }

    func colorMask(size: NSSize, scale: CGFloat, highlight: Bool = false) -> NSImage? {
        guard let assets = ChromaAppearance.assets(geometry: .input(rect, cornerRadius, cornerStyle), size: size) else { return nil }
        return highlight ? assets.edge : assets.color
    }

    func mask(size: NSSize, distortion: GlowDistortion = .identity, expansion: Double = 1, falloff: Double = 1) -> NSImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        var exterior = Path(CGRect(origin: .zero, size: size))
        exterior.addPath(path)
        return ChromaAppearance.radiusMap(geometry: .input(rect, cornerRadius, cornerStyle), size: size,
            distortion: distortion, exterior: exterior, expansion: expansion, falloff: falloff)
    }
}
