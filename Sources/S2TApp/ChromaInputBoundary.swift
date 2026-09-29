import AppKit
import S2TCore

struct ChromaInputBoundary {
    private let parts: [(InputContour.Part, RoundedInputBoundary?)]

    init(rect: CGRect, radius: CGFloat, cornerStyle: InputCornerStyle = .continuous) {
        self.init(contour: InputContour(rect: rect, radius: radius, style: cornerStyle))
    }

    init(contour: InputContour) {
        parts = contour.parts.map { part in
            (part, part.style == .continuous && part.radius < part.rect.height / 2
                ? RoundedInputBoundary(rect: part.rect, radius: part.radius, cornerStyle: part.style) : nil)
        }
    }

    func distance(_ point: CGPoint) -> Double {
        if parts.count == 1, let rounded = parts[0].1 { return rounded.distance(point) }
        var nearest = Double.greatestFiniteMagnitude
        for (part, rounded) in parts {
            nearest = min(nearest, rounded?.distance(point) ?? sample(point, part: part).distance)
        }
        return nearest
    }

    func outwardVector(_ point: CGPoint) -> CGPoint {
        if parts.count == 1 {
            return parts[0].1?.outwardVector(point) ?? sample(point, part: parts[0].0).vector
        }
        var nearest = Double.greatestFiniteMagnitude
        var result = CGPoint.zero
        for (part, rounded) in parts {
            let sample = rounded.map { (distance: $0.distance(point), vector: $0.outwardVector(point)) }
                ?? sample(point, part: part)
            if sample.distance <= 0 { return .zero }
            if sample.distance < nearest { nearest = sample.distance; result = sample.vector }
        }
        return result
    }

    private func sample(_ p: CGPoint, part: InputContour.Part) -> (distance: Double, vector: CGPoint) {
        let rect = part.rect
        let rounded = part.corners == .all || part.corners == .top && p.y <= rect.midY || part.corners == .bottom && p.y >= rect.midY
        let radius = rounded ? min(part.radius, min(rect.width, rect.height) / 2) : 0
        let x = abs(p.x - rect.midX) - rect.width / 2 + radius
        let y = abs(p.y - rect.midY) - rect.height / 2 + radius
        let dx = max(0, x), dy = max(0, y), length = hypot(dx, dy)
        let distance = length + min(max(x, y), 0) - radius
        guard distance > 0 else { return (distance, .zero) }
        let nx = length > 0 ? dx / length : x >= y ? 1.0 : 0
        let ny = length > 0 ? dy / length : y > x ? 1.0 : 0
        return (distance, CGPoint(x: nx * distance * (p.x < rect.midX ? -1 : 1),
                                  y: ny * distance * (p.y < rect.midY ? -1 : 1)))
    }
}
