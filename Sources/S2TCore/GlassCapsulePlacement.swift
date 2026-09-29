import CoreGraphics
import Foundation

public struct GlassCapsuleAnchor: Codable, Equatable {
    public let displayID: String
    public let x: Double
    public let y: Double
    public let centered: Bool?
    public let dockedSide: String?

    public var side: BezelSide? { dockedSide.flatMap(BezelSide.init(rawValue:)) }

    public static func dockingSide(pointer: CGPoint, screen: CGRect, attached: BezelSide? = nil) -> BezelSide? {
        if attached == .left, pointer.x <= screen.minX + 72 { return .left }
        if attached == .right, pointer.x >= screen.maxX - 72 { return .right }
        if pointer.x <= screen.minX + 36 { return .left }
        if pointer.x >= screen.maxX - 36 { return .right }
        return nil
    }

    public init(center: CGPoint, visibleFrame: CGRect, displayID: String, screenMidX: CGFloat? = nil, side: BezelSide? = nil) {
        self.dockedSide = side?.rawValue
        self.displayID = displayID
        x = min(1, max(0, (center.x - visibleFrame.minX) / max(1, visibleFrame.width)))
        y = min(1, max(0, (center.y - visibleFrame.minY) / max(1, visibleFrame.height)))
        centered = abs(center.x - (screenMidX ?? visibleFrame.midX)) <= 0.5
    }

    public func center(in frame: CGRect, screenMidX: CGFloat? = nil) -> CGPoint {
        let point = CGPoint(x: centered == true ? (screenMidX ?? frame.midX) : frame.minX + (x.isFinite ? x : 0.5) * frame.width,
                            y: frame.minY + (y.isFinite ? y : 0.5) * frame.height)
        return Self.clamp(point, to: frame)
    }

    public static func clamp(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        let dx = min(66, frame.width / 2), dy = min(28, frame.height / 2)
        return CGPoint(x: min(frame.maxX - dx, max(frame.minX + dx, point.x)),
                       y: min(frame.maxY - dy, max(frame.minY + dy, point.y)))
    }
}

public struct GlassCapsuleDrag {
    public private(set) var snapped: Bool
    private let pointer: CGPoint
    private let center: CGPoint
    private var snapLine: CGFloat

    public init(pointer: CGPoint, center: CGPoint, screenMidX: CGFloat) {
        self.pointer = pointer
        self.center = center
        snapLine = screenMidX
        snapped = abs(center.x - screenMidX) <= 0.5
    }

    public mutating func update(pointer: CGPoint, visibleFrame: CGRect, screenMidX: CGFloat? = nil) -> CGPoint {
        var next = CGPoint(x: center.x + pointer.x - self.pointer.x,
                           y: center.y + pointer.y - self.pointer.y)
        let line = screenMidX ?? visibleFrame.midX
        if snapLine != line { snapped = false; snapLine = line }
        let distance = abs(next.x - snapLine)
        if snapped { snapped = distance <= 28 }
        else { snapped = distance <= 12 }
        if snapped { next.x = snapLine }
        return GlassCapsuleAnchor.clamp(next, to: visibleFrame)
    }
}
