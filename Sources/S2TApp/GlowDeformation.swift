import CoreGraphics
import S2TCore

extension GlowDistortion {
    func transform(in size: CGSize, bottom: Bool = false) -> CGAffineTransform {
        let center = CGPoint(x: size.width / 2, y: bottom ? size.height : size.height / 2)
        let dx = horizontal * (bottom ? 8 : 1)
        let dy = bottom ? 0 : vertical
        let sx = 1 + stretch * (bottom ? 0.025 : 2 / max(1, size.width))
        let sy = 1 + (bottom ? vertical * 0.025 : -stretch * 2 / max(1, size.height))
        return CGAffineTransform(translationX: center.x + dx, y: center.y + dy)
            .scaledBy(x: sx, y: sy).translatedBy(x: -center.x, y: -center.y)
    }
}
