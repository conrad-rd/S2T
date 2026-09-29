import AppKit
import QuartzCore

@MainActor final class GradientStopGlow {
    let layer = CALayer()
    let halo = CAShapeLayer()
    let shimmer = CAGradientLayer()
    private let highlight = CALayer()
    private let mask = CAShapeLayer()

    init() {
        layer.name = "gradient.selectedGlow"
        layer.masksToBounds = false
        layer.isHidden = true
        halo.shadowOffset = .zero
        halo.shadowRadius = 6
        halo.shadowOpacity = 0.42
        highlight.mask = mask
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.locations = [0, 0.5, 1]
        shimmer.colors = [NSColor.white.withAlphaComponent(0).cgColor,
                          NSColor.white.withAlphaComponent(0.22).cgColor,
                          NSColor.white.withAlphaComponent(0).cgColor]
        shimmer.transform = CATransform3DMakeRotation(-.pi / 7, 0, 0, 1)
        layer.addSublayer(halo)
        layer.addSublayer(highlight)
        highlight.addSublayer(shimmer)
    }

    func layout(in bounds: CGRect, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        halo.frame = layer.bounds
        halo.contentsScale = scale
        let circle = CGPath(ellipseIn: layer.bounds.insetBy(dx: 7, dy: 7), transform: nil)
        halo.path = circle
        halo.shadowPath = circle
        highlight.frame = layer.bounds
        mask.frame = highlight.bounds
        mask.path = CGPath(ellipseIn: highlight.bounds.insetBy(dx: 7.5, dy: 7.5), transform: nil)
        mask.contentsScale = scale
        shimmer.bounds = CGRect(x: 0, y: 0, width: 12, height: bounds.height + 12)
        shimmer.position = CGPoint(x: 8, y: bounds.midY)
        CATransaction.commit()
    }

    func update(color: NSColor, selected: Bool, reducedMotion: Bool, visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.isHidden = !selected
        halo.fillColor = color.withAlphaComponent(0.12).cgColor
        halo.shadowColor = color.cgColor
        CATransaction.commit()
        if selected && visible && !reducedMotion {
            guard shimmer.animation(forKey: "sweep") == nil else { return }
            let sweep = CAKeyframeAnimation(keyPath: "position.x")
            sweep.values = [-12, -12, 44, 44]
            sweep.keyTimes = [0, 0.22, 0.66, 1]
            sweep.timingFunctions = [.init(name: .linear), .init(name: .easeInEaseOut), .init(name: .linear)]
            sweep.duration = 5.6
            sweep.repeatCount = .infinity
            shimmer.add(sweep, forKey: "sweep")
        } else {
            shimmer.removeAnimation(forKey: "sweep")
        }
    }
}
