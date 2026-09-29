import CoreGraphics
import Foundation

public struct WindowBottomLayout: Equatable, Sendable {
    public let frame: CGRect
    public let leftRadius: CGFloat
    public let rightRadius: CGFloat

    public init(window: CGRect, leftRadius: CGFloat, rightRadius: CGFloat, maximumHeight: CGFloat) {
        frame = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(window.height, maximumHeight))
        let limit = min(window.width, window.height) / 2
        self.leftRadius = min(limit, max(0, leftRadius))
        self.rightRadius = min(limit, max(0, rightRadius))
    }

    // Top-down local coordinates, shared by color, processing and native blur.
    public func boundaryY(at x: CGFloat) -> CGFloat {
        let radius: CGFloat
        let inset: CGFloat
        if x < leftRadius { radius = leftRadius; inset = max(0, x) }
        else if x > frame.width - rightRadius { radius = rightRadius; inset = max(0, frame.width - x) }
        else { return frame.height }
        let offset = radius - inset
        return frame.height - radius + sqrt(max(0, radius * radius - offset * offset))
    }

    public func distance(at point: CGPoint) -> CGFloat { boundaryY(at: point.x) - point.y }
}
