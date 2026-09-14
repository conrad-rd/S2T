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
            let organic = 1 + (0.06 + 0.13 * speed) * cos(3 * angle - direction) + 0.07 * wobble * sin(2 * angle)
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
            let neck = (ry + 18) * contact
            let top = CGPoint(x: edgeX, y: center.y - neck)
            let bottom = CGPoint(x: edgeX, y: center.y + neck)
            let first = points[0], last = points[64]
            let tangent = point(firstAngle + 0.01)
            let endTangent = point(lastAngle - 0.01)
            let handle = min(0.55, max(0.18, distance / 130))
            path.move(to: top)
            path.addCurve(to: first,
                control1: CGPoint(x: edgeX, y: top.y + neck * 0.7),
                control2: CGPoint(x: first.x - (tangent.x - first.x) * handle / 0.01,
                                  y: first.y - (tangent.y - first.y) * handle / 0.01))
            appendCurve(points: points, to: path, closed: false)
            path.addCurve(to: bottom,
                control1: CGPoint(x: last.x + (last.x - endTangent.x) * handle / 0.01,
                                  y: last.y + (last.y - endTangent.y) * handle / 0.01),
                control2: CGPoint(x: edgeX, y: bottom.y - neck * 0.7))
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
        let a = samples(source.path), b = samples(target.path)
        let path = CGMutablePath()
        for index in a.indices {
            let point = CGPoint(x: a[index].x + (b[index].x - a[index].x) * amount,
                                y: a[index].y + (b[index].y - a[index].y) * amount)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return BezelShape(path: path, symbolCenter: center)
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
                for step in 1...12 {
                    let t = Double(step) / 12, s = 1 - t
                    points.append(CGPoint(x: s*s*s*origin.x + 3*s*s*t*a.x + 3*s*t*t*b.x + t*t*t*end.x,
                                          y: s*s*s*origin.y + 3*s*s*t*a.y + 3*s*t*t*b.y + t*t*t*end.y))
                }
                current = end
            case .closeSubpath: points.append(first); current = first
            default: break
            }
        }
        var lengths = [0.0]
        for index in 1..<points.count { lengths.append(lengths.last! + hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)) }
        var segment = 1
        return (0..<192).map { index in
            let distance = lengths.last! * Double(index) / 192
            while segment < lengths.count - 1 && lengths[segment] < distance { segment += 1 }
            let fraction = (distance - lengths[segment - 1]) / max(0.0001, lengths[segment] - lengths[segment - 1])
            return CGPoint(x: points[segment - 1].x + (points[segment].x - points[segment - 1].x) * fraction,
                           y: points[segment - 1].y + (points[segment].y - points[segment - 1].y) * fraction)
        }
    }
}
