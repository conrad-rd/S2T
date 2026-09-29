import Foundation
import CoreGraphics

public struct InputContour: Equatable, Sendable {
    public enum Corners: Equatable, Sendable { case all, top, bottom }
    public struct Part: Equatable, Sendable {
        public var rect: CGRect
        public var radius: CGFloat
        public var style: InputCornerStyle
        public var corners: Corners

        public init(rect: CGRect, radius: CGFloat, style: InputCornerStyle = .continuous, corners: Corners = .all) {
            self.rect = rect; self.radius = radius; self.style = style; self.corners = corners
        }
    }
    public var main: Part
    public var bars: [Part]
    public var parts: [Part] { [main] + bars }
    public var bounds: CGRect { bars.reduce(main.rect) { $0.union($1.rect) } }

    public init(rect: CGRect, radius: CGFloat, style: InputCornerStyle = .continuous) {
        main = Part(rect: rect, radius: radius, style: style)
        bars = []
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> Self {
        var result = self
        result.main.rect = main.rect.offsetBy(dx: dx, dy: dy)
        result.bars = bars.map { part in
            var moved = part; moved.rect = part.rect.offsetBy(dx: dx, dy: dy); return moved
        }
        return result
    }
}
