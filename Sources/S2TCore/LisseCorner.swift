import Foundation
import CoreGraphics

// Adapted from Jace Attard's MIT-licensed Lisse corner-params.ts and curves/squircle.ts.
// https://github.com/JaceThings/Lisse, license in Resources/ThirdParty/Lisse-LICENSE.txt.
struct LisseCorner {
    let a, b, c, d, p, arc: Double
    let radius, smoothing: Double

    init(radius: Double, smoothing: Double = 0.65, budget: Double) {
        self.radius = max(0, radius)
        self.smoothing = min(1, max(0, smoothing))
        guard radius > 0, budget > 0 else {
            a = 0; b = 0; c = 0; d = 0; p = 0; arc = 0
            return
        }
        let reach = (1 + self.smoothing) * radius
        let beta = .pi / 4 * self.smoothing
        arc = sin(.pi / 4 * (1 - self.smoothing)) * radius * sqrt(2)
        c = radius * tan(beta / 2) * cos(beta)
        d = c * tan(beta)
        var shoulder = (reach - arc - c - d) / 3
        var entry = 2 * shoulder
        if reach > budget {
            let available = budget - d - arc - c
            shoulder = min(shoulder, available * 5 / 6)
            entry = available - shoulder
        }
        a = entry
        b = shoulder
        p = min(reach, budget)
    }

    func append(to path: CGMutablePath, from start: CGPoint, to end: CGPoint, verticalFirst: Bool) {
        guard p > 0 else { path.addLine(to: end); return }
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: start.x + (end.x - start.x) * (verticalFirst ? y : x) / p,
                    y: start.y + (end.y - start.y) * (verticalFirst ? x : y) / p)
        }
        let x = a + b + c
        path.addCurve(to: point(x, d), control1: point(a, 0), control2: point(a + b, 0))
        if arc > 0 {
            let beta = .pi / 4 * smoothing
            let handle = 4 / 3 * tan(.pi / 8 * (1 - smoothing)) * radius
            path.addCurve(to: point(x + arc, d + arc),
                control1: point(x + handle * cos(beta), d + handle * sin(beta)),
                control2: point(x + arc - handle * sin(beta), d + arc - handle * cos(beta)))
        }
        path.addCurve(to: end,
            control1: point(x + arc + d, d + arc + c),
            control2: point(x + arc + d, d + arc + b + c))
    }
}
