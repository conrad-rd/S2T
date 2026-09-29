import AppKit
import S2TCore

// Preview-only geometry. The live Bezel keeps its fitted edge connector.
enum BezelDragShape {
    static let center = CGPoint(x: 100, y: 190)

    static func make(velocity: CGVector, wobble: Double = 0, side: BezelSide = .left, distance: Double = .infinity) -> BezelShape {
        let dx = min(1, max(-1, velocity.dx * (side == .right ? -1 : 1) / 900))
        let dy = min(1, max(-1, velocity.dy / 900))
        let speed = min(1, hypot(dx, dy))
        let rx = 29 + 19 * abs(dx) - 9 * abs(dy) + 6 * wobble
        let ry = 35 + 20 * abs(dy) - 10 * abs(dx) - 5 * wobble
        let direction = atan2(dy, dx)
        func point(_ angle: Double) -> CGPoint {
            let organic = 1 + 0.025 * speed * cos(angle - direction) + 0.035 * wobble * sin(2 * angle)
            return CGPoint(x: center.x + rx * cos(angle) * organic + 10 * dx * sin(angle),
                           y: center.y + ry * sin(angle) * organic + 7 * dy * cos(angle))
        }
        let proximity = min(1, max(0, (94 - distance) / 54))
        let contact = proximity * proximity * (3 - 2 * proximity)
        let path = CGMutablePath()
        if contact == 0 {
            appendCurve(points: (0..<64).map { point(Double($0) * .pi * 2 / 64) }, to: path, closed: true)
        } else {
            // Build the connector and droplet as one contour, with no overlapping fills.
            // Reflect the complete shape for Right so both sides have the same contact.
            let angle = contact * 1.12
            let firstAngle = Double.pi + angle
            let lastAngle = Double.pi * 3 - angle
            let points = (0...64).map { point(firstAngle + (lastAngle - firstAngle) * Double($0) / 64) }
            let edgeX = center.x - distance
            let neck = (ry + 12) * contact
            let top = CGPoint(x: edgeX, y: center.y - neck)
            let bottom = CGPoint(x: edgeX, y: center.y + neck)
            let first = points[0], last = points[64]
            let tangent = point(firstAngle + 0.01)
            let endTangent = point(lastAngle - 0.01)
            let span = max(0, min(first.x, last.x) - edgeX)
            let waistX = edgeX + span * 0.42
            let waist = max(0.15, 10 * contact * contact)
            let upperWaist = CGPoint(x: waistX, y: center.y - waist)
            let lowerWaist = CGPoint(x: waistX, y: center.y + waist)
            let handle = min(0.28, span / 160)
            path.move(to: top)
            path.addCurve(to: upperWaist,
                control1: CGPoint(x: edgeX, y: center.y - waist),
                control2: CGPoint(x: edgeX + span * 0.22, y: upperWaist.y))
            path.addCurve(to: first,
                control1: CGPoint(x: waistX + span * 0.25, y: upperWaist.y),
                control2: CGPoint(x: first.x - (tangent.x - first.x) * handle / 0.01,
                                  y: first.y - (tangent.y - first.y) * handle / 0.01))
            appendCurve(points: points, to: path, closed: false)
            path.addCurve(to: lowerWaist,
                control1: CGPoint(x: last.x + (last.x - endTangent.x) * handle / 0.01,
                                  y: last.y + (last.y - endTangent.y) * handle / 0.01),
                control2: CGPoint(x: waistX + span * 0.25, y: lowerWaist.y))
            path.addCurve(to: bottom,
                control1: CGPoint(x: edgeX + span * 0.22, y: lowerWaist.y),
                control2: CGPoint(x: edgeX, y: center.y + waist))
            path.closeSubpath()
        }
        var reflection = CGAffineTransform(a: side == .right ? -1 : 1, b: 0, c: 0, d: 1,
                                           tx: side == .right ? center.x * 2 : 0, ty: 0)
        return BezelShape(path: path.copy(using: &reflection)!, symbolCenter: center)
    }

    private static func appendCurve(points: [CGPoint], to path: CGMutablePath, closed: Bool) {
        if closed { path.move(to: points[0]) }
        let count = points.count
        func point(_ index: Int) -> CGPoint { points[closed ? (index + count) % count : min(count - 1, max(0, index))] }
        for index in 0..<(closed ? count : count - 1) {
            let p0 = point(index - 1), p1 = point(index), p2 = point(index + 1), p3 = point(index + 2)
            path.addCurve(to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if closed { path.closeSubpath() }
    }

    static func morph(_ source: BezelShape, into target: BezelShape, amount: Double) -> BezelShape {
        if amount <= 0 { return source }
        if amount >= 1 { return target }
        let a = envelope(source.path), b = envelope(target.path)
        func blend(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: first.x + (second.x - first.x) * amount,
                    y: first.y + (second.y - first.y) * amount)
        }
        let upper = zip(a.upper, b.upper).map { blend($0, $1) }
        let lower = zip(a.lower, b.lower).map { blend($0, $1) }.reversed()
        let path = CGMutablePath()
        path.move(to: upper[0])
        appendCurve(points: upper, to: path, closed: false)
        path.addLine(to: lower.first!)
        appendCurve(points: Array(lower), to: path, closed: false)
        path.closeSubpath()
        return BezelShape(path: path, symbolCenter: blend(source.symbolCenter, target.symbolCenter))
    }

    private static func envelope(_ path: CGPath) -> (upper: [CGPoint], lower: [CGPoint]) {
        let contour = samples(path)
        let bounds = path.boundingBoxOfPath
        var upper: [CGPoint] = [], lower: [CGPoint] = []
        for step in 0...128 {
            let x = bounds.minX + bounds.width * (1 - cos(.pi * Double(step) / 128)) / 2
            let probe = min(bounds.maxX - 0.001, max(bounds.minX + 0.001, x))
            var intersections: [Double] = []
            for index in contour.indices {
                let a = contour[index], b = contour[(index + 1) % contour.count]
                if min(a.x, b.x) <= probe, max(a.x, b.x) >= probe, abs(b.x - a.x) > 0.000001 {
                    intersections.append(a.y + (b.y - a.y) * (probe - a.x) / (b.x - a.x))
                }
            }
            upper.append(CGPoint(x: x, y: intersections.min() ?? bounds.midY))
            lower.append(CGPoint(x: x, y: intersections.max() ?? bounds.midY))
        }
        return (upper, lower)
    }

    private static func samples(_ path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = [], current = CGPoint.zero, first = CGPoint.zero
        path.applyWithBlock { item in
            let element = item.pointee
            switch element.type {
            case .moveToPoint: current = element.points[0]; first = current; points.append(current)
            case .addLineToPoint: current = element.points[0]; points.append(current)
            case .addCurveToPoint:
                let origin = current, a = element.points[0], b = element.points[1], end = element.points[2]
                let length = hypot(a.x - origin.x, a.y - origin.y) + hypot(b.x - a.x, b.y - a.y) + hypot(end.x - b.x, end.y - b.y)
                let steps = min(128, max(4, Int(ceil(length / 0.75))))
                for step in 1...steps {
                    let t = Double(step) / Double(steps), s = 1 - t
                    points.append(CGPoint(x: s*s*s*origin.x + 3*s*s*t*a.x + 3*s*t*t*b.x + t*t*t*end.x,
                                          y: s*s*s*origin.y + 3*s*s*t*a.y + 3*s*t*t*b.y + t*t*t*end.y))
                }
                current = end
            case .closeSubpath: points.append(first); current = first
            default: break
            }
        }
        return points
    }
}
