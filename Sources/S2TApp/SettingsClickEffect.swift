import AppKit
import QuartzCore

@MainActor enum SettingsClickEffect {
    static let animationKey = "settings.clickScale"

    static func target(at point: NSPoint, in content: NSView) -> NSView? {
        var candidate = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
        while let view = candidate {
            if let control = view as? NSControl,
               control is NSButton || control is NSSwitch || control is NSSegmentedControl {
                return control.isEnabled ? control : nil
            }
            if let row = view as? SettingsSidebarRow { return row.isHeading ? nil : row }
            if view === content { break }
            candidate = view.superview
        }
        return nil
    }

    static func animate(_ view: NSView,
                        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        guard !reduceMotion, view.bounds.width > 0, view.bounds.height > 0 else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let scale: CGFloat = 0.97
        let center = CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x),
                             y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
        var pressed = CATransform3DMakeTranslation(center.x * (1 - scale), center.y * (1 - scale), 0)
        pressed = CATransform3DScale(pressed, scale, scale, 1)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [NSValue(caTransform3D: CATransform3DIdentity),
                            NSValue(caTransform3D: pressed),
                            NSValue(caTransform3D: CATransform3DIdentity)]
        animation.keyTimes = [0, 0.3, 1]
        animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                     CAMediaTimingFunction(name: .easeInEaseOut)]
        animation.duration = 0.22
        layer.add(animation, forKey: animationKey)
    }
}
