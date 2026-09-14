import Foundation
import CoreGraphics

public struct DiscoveredInput {
    public let id: Int
    public let frame: CGRect
    public let boundary: CGRect
    public let focused: Bool

    public init(id: Int, frame: CGRect, boundary: CGRect, focused: Bool = false) {
        self.id = id; self.frame = frame; self.boundary = boundary; self.focused = focused
    }
}

public enum InputDiscovery {
    public static func samplePoints(in window: CGRect, anchor: CGPoint?) -> [CGPoint] {
        var points = [CGPoint]()
        if let anchor, window.contains(anchor) { points.append(anchor) }
        for y in [0.97, 0.93, 0.86, 0.72, 0.50, 0.28, 0.14, 0.07, 0.035] {
            for x in [0.5, 0.2, 0.8] {
                let point = CGPoint(x: window.minX + window.width * x, y: window.minY + window.height * y)
                if !points.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 2 }) { points.append(point) }
            }
        }
        return points
    }

    public static func choose(_ inputs: [DiscoveredInput], window: CGRect, anchor: CGPoint?) -> Int? {
        let valid = inputs.filter { $0.frame.width >= 24 && $0.frame.height >= 8 && window.intersects($0.frame) }
        let focused = valid.filter(\.focused)
        if focused.count == 1 { return focused[0].id }
        if focused.count > 1 { return nil }
        if let anchor {
            let anchored = valid.filter { $0.boundary.contains(anchor) }
            if let closest = anchored.min(by: { area($0.boundary) < area($1.boundary) }) { return closest.id }
        }
        if valid.count == 1 { return valid[0].id }
        let ranked = valid.map { input -> (DiscoveredInput, Double) in
            let width = min(1, input.frame.width / max(1, window.width))
            let height = min(1, input.frame.height / max(1, window.height * 0.08))
            let position = min(1, max(0, (input.frame.midY - window.minY) / max(1, window.height)))
            return (input, Double(width * 100 + height * 15 + position * 20))
        }.sorted { $0.1 > $1.1 }
        guard ranked.count >= 2, let best = ranked.first,
              best.0.frame.width >= window.width * 0.3, best.1 - ranked[1].1 >= 25 else { return nil }
        return best.0.id
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
