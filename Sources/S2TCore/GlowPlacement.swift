import CoreGraphics
import Foundation

public enum GlowAppearance: String, CaseIterable, Sendable {
    case bottom, aroundNotch, aroundInput, bezel

    public var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .aroundNotch: return "Around Notch"
        case .aroundInput: return "Around Input"
        case .bezel: return "Bezel"
        }
    }
}

public struct GlowDisplay {
    public let frame: CGRect
    public let notch: CGRect?

    public init(frame: CGRect, safeTop: CGFloat = 0, topLeft: CGRect? = nil, topRight: CGRect? = nil) {
        self.frame = frame
        if safeTop > 0, safeTop < frame.height, let left = topLeft, let right = topRight,
           left.width > 0, right.width > 0, left.maxX < right.minX,
           left.maxX > frame.minX, right.minX < frame.maxX,
           abs(left.maxY - frame.maxY) < 1, abs(right.maxY - frame.maxY) < 1 {
            notch = CGRect(x: left.maxX, y: frame.maxY - safeTop,
                           width: right.minX - left.maxX, height: safeTop)
        } else {
            notch = nil
        }
    }

    public static func preferredIndex(in displays: [GlowDisplay], pointer: CGPoint) -> Int? {
        return displays.firstIndex(where: { $0.frame.contains(pointer) }) ?? displays.indices.first
    }
}

public struct TopGlowLayout: Equatable {
    public let frame: CGRect
    public let displayWidth: CGFloat
    public let displayOffsetX: CGFloat
    // Local drawing coordinates start at the top-left, unlike AppKit screen coordinates.
    public let notch: CGRect?
    public var cornerRadius: CGFloat { min(8, (notch?.height ?? 0) / 2) }
    public var topJoinRadius: CGFloat { min(6, (notch?.height ?? 0) / 2) }

    public init(display: GlowDisplay, paddingScale: Double = 1) {
        displayWidth = display.frame.width
        let padding = ceil(ChromaPreset.notch.fieldExtent * max(1, paddingScale))
        if let housing = display.notch {
            let left = max(display.frame.minX, housing.minX - 192)
            let right = min(display.frame.maxX, housing.maxX + 192)
            frame = CGRect(x: left, y: display.frame.maxY - housing.height - padding,
                           width: right - left, height: housing.height + padding)
            notch = CGRect(x: housing.minX - left, y: 0, width: housing.width, height: housing.height)
        } else {
            let width = min(320, display.frame.width * 0.5)
            frame = CGRect(x: display.frame.midX - width / 2, y: display.frame.maxY - padding, width: width, height: padding)
            notch = nil
        }
        displayOffsetX = frame.minX - display.frame.minX
    }

    public func distance(at point: CGPoint) -> CGFloat {
        guard let notch else { return point.y }
        let side = abs(point.x - notch.midX) - notch.width / 2
        let join = topJoinRadius
        if side >= 0, side < join, point.y < join {
            return join - hypot(join - side, join - point.y)
        }
        let radius = cornerRadius
        let x = abs(point.x - notch.midX) - (notch.width / 2 - radius)
        let y = point.y - (notch.maxY - radius)
        let housing = hypot(max(0, x), max(0, y)) + min(max(x, y), 0) - radius
        return min(point.y, housing)
    }

    public func sideOpacity(at x: CGFloat) -> Double { sideOpacity(at: x, wing: 48) }
    public func blurSideOpacity(at x: CGFloat) -> Double { sideOpacity(at: x) }

    private func sideOpacity(at x: CGFloat, wing: CGFloat) -> Double {
        let inset = notch.map { max(0, $0.minX - wing) } ?? 0
        let width = frame.width - inset * 2
        return GlowSweep.sideFade(x: Double((x - inset) / width))
    }
}
