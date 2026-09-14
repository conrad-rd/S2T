import CoreGraphics
import Foundation

public enum BezelSide: String, CaseIterable, Sendable {
    case left, right
    public var title: String { self == .left ? "Left" : "Right" }
}

public struct BezelForm: Equatable {
    public var depth: Double
    public var body: Double
    public var attachment: Double

    public static let hidden = BezelForm(depth: 0, body: 0, attachment: 0)
    public static let shown = BezelForm(depth: 1, body: 1, attachment: 1)

    public init(depth: Double, body: Double, attachment: Double) {
        self.depth = depth
        self.body = body
        self.attachment = attachment
    }
}

public struct BezelShape {
    public let path: CGPath
    public let symbolCenter: CGPoint
    public init(path: CGPath, symbolCenter: CGPoint) {
        self.path = path
        self.symbolCenter = symbolCenter
    }
}

public enum BezelGeometry {
    public static let size = CGSize(width: 200, height: 380)

    public static func frame(screen: CGRect, side: BezelSide, verticalPosition: Double = 0.5) -> CGRect {
        let inset = min(60, screen.height / 2)
        let position = verticalPosition.isFinite ? min(1, max(0, verticalPosition)) : 0.5
        let center = screen.maxY - inset - position * max(0, screen.height - 2 * inset)
        return CGRect(x: side == .left ? screen.minX : screen.maxX - size.width,
               y: floor(center - size.height / 2), width: size.width, height: size.height)
    }

    public static func shape(form: BezelForm, side: BezelSide, level: Double = 0, tilt: Double = 0) -> BezelShape {
        let speech = min(1, max(0, level))
        let extensionAmount = min(1.25, max(0, form.depth))
        let bodyAmount = min(1.25, max(0, form.body))
        let anchor = min(1.15, max(0, form.attachment))
        let pull = max(0, extensionAmount - bodyAmount)
        let attachmentWidth = 22 * anchor + 8 * pull
        let neckWidth = attachmentWidth - 2 * anchor
        let neckHeight = (20 + 4 * pull) * anchor
        let bodyWidth = (24 + speech) * extensionAmount
        let front = attachmentWidth + bodyWidth
        let halfHeight = (35 + speech) * bodyAmount / sqrt(max(0.75, extensionAmount))
        let corner = min(24 * bodyAmount, bodyWidth, halfHeight * 0.68)
        let shift = min(1, max(-1, tilt)) * 3 * bodyAmount
        let middle = size.height / 2 + shift
        var cursor = CGPoint(x: 0, y: middle - halfHeight - neckHeight)
        let path = CGMutablePath()
        path.move(to: cursor)
        func line(to point: CGPoint) {
            path.addLine(to: point)
            cursor = point
        }
        func turn(to end: CGPoint, verticalFirst: Bool) {
            LisseCorner(radius: 0.8, budget: 1).append(to: path, from: cursor, to: end, verticalFirst: verticalFirst)
            cursor = end
        }
        turn(to: CGPoint(x: neckWidth, y: middle - halfHeight), verticalFirst: true)
        line(to: CGPoint(x: front - corner, y: middle - halfHeight))
        turn(to: CGPoint(x: front, y: middle - halfHeight + corner), verticalFirst: false)
        line(to: CGPoint(x: front, y: middle + halfHeight - corner))
        turn(to: CGPoint(x: front - corner, y: middle + halfHeight), verticalFirst: true)
        line(to: CGPoint(x: neckWidth, y: middle + halfHeight))
        turn(to: CGPoint(x: 0, y: middle + halfHeight + neckHeight), verticalFirst: false)
        path.closeSubpath()
        var transform = side == .left ? CGAffineTransform.identity
            : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
        let center = CGPoint(x: front / 2, y: middle)
        return BezelShape(path: path.copy(using: &transform)!, symbolCenter: center.applying(transform))
    }

    public static func barLength(energy: Double) -> Double {
        2.5 + 14 * min(1, max(0, energy))
    }

}

public struct BezelMotion {
    public private(set) var isVisible = false
    private var depth = LiquidSpring()
    private var body = LiquidSpring()
    private var attachment = LiquidSpring()
    private var startedAt = 0.0
    public let duration = 0.95

    public init() {}

    public func form(at time: Double, reducedMotion: Bool = false) -> BezelForm {
        if reducedMotion || time - startedAt >= duration { return isVisible ? .shown : .hidden }
        let t = max(0, time - startedAt)
        return BezelForm(depth: depth.sample(at: t).position,
                         body: body.sample(at: t).position,
                         attachment: attachment.sample(at: t).position)
    }

    public mutating func setVisible(_ visible: Bool, at time: Double, reducedMotion: Bool = false) {
        guard visible != isVisible else { return }
        let elapsed = max(0, time - startedAt)
        let settled = reducedMotion || elapsed >= duration
        let previous = isVisible ? 1.0 : 0.0
        let target = visible ? 1.0 : 0.0
        depth = depth.retarget(at: elapsed, settled: settled, previous: previous, target: target,
                               frequency: visible ? 16 : 10, damping: visible ? 0.48 : 1)
        body = body.retarget(at: elapsed, settled: settled, previous: previous, target: target,
                             frequency: visible ? 12 : 20, damping: visible ? 0.50 : 1)
        attachment = attachment.retarget(at: elapsed, settled: settled, previous: previous, target: target,
                                         frequency: visible ? 20 : 8, damping: visible ? 0.76 : 1)
        startedAt = time
        isVisible = visible
    }
}

private struct LiquidSpring {
    var start = 0.0
    var velocity = 0.0
    var target = 0.0
    var frequency = 14.0
    var damping = 1.0

    func sample(at time: Double) -> (position: Double, velocity: Double) {
        let offset = start - target
        let decay = exp(-damping * frequency * time)
        if damping == 1 {
            let b = velocity + frequency * offset
            return (target + (offset + b * time) * decay,
                    (velocity - frequency * b * time) * decay)
        }
        let oscillation = frequency * sqrt(1 - damping * damping)
        let b = (velocity + damping * frequency * offset) / oscillation
        let wave = offset * cos(oscillation * time) + b * sin(oscillation * time)
        let slope = oscillation * (-offset * sin(oscillation * time) + b * cos(oscillation * time))
        return (target + wave * decay, (slope - damping * frequency * wave) * decay)
    }

    func retarget(at time: Double, settled: Bool, previous: Double, target: Double,
                  frequency: Double, damping: Double) -> Self {
        let current = settled ? (position: previous, velocity: 0.0) : sample(at: time)
        return Self(start: current.position, velocity: current.velocity, target: target,
                    frequency: frequency, damping: damping)
    }
}
