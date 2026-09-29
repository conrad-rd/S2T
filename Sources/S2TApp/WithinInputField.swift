import AppKit
import SwiftUI
import S2TCore

/// The lower edge anchors the field, while only its diffuse tail can clear the top.
struct WithinInputField {
    let contour: InputContour
    private var rect: CGRect { contour.main.rect }
    private var radius: Double { min(contour.main.radius, min(rect.width, rect.height) / 2) }

    func lowerEdge(at x: Double) -> Double {
        let r = radius
        guard r > 0 else { return rect.maxY }
        let corner = max(0, abs(x - rect.midX) - (rect.width / 2 - r)) / r
        let power = contour.main.style == .circular || r >= rect.height / 2 ? 2.0 : 2.8
        return rect.maxY - r + r * pow(max(0, 1 - pow(min(1, corner), power)), 1 / power)
    }

    func distance(_ point: CGPoint) -> Double { lowerEdge(at: point.x) - point.y }

    static let upperSideSpill = 36.0

    private func upperSpread(at y: Double) -> Double {
        Self.upperSideSpill * smooth((rect.minY + 64 - y) / 96)
    }

    var hazeExtent: Double { max(80, rect.height + 72) }

    func haze(_ point: CGPoint) -> Double {
        let falloff = 1 - smooth(max(0, distance(point)) / hazeExtent)
        let spread = upperSpread(at: point.y)
        let lateral = pow(max(0, sin(Double.pi * min(1, max(0, (point.x - rect.minX + spread) / (rect.width + 2 * spread))))), 0.48)
        return falloff * falloff * lateral
    }

    func coverage(_ point: CGPoint) -> Double {
        let spread = upperSpread(at: point.y)
        let side = min(point.x - rect.minX + spread, rect.maxX + spread - point.x)
        let horizontal = smooth((side + 4) / max(10, radius * 0.6))
        return horizontal
    }

    var clipPath: Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 0))
            for index in 0...320 {
                let x = rect.maxX - rect.width * Double(index) / 320
                path.addLine(to: CGPoint(x: x, y: lowerEdge(at: x)))
            }
            path.closeSubpath()
            for x in [rect.minX - Self.upperSideSpill, rect.maxX] {
                path.addRect(CGRect(x: x, y: 0, width: Self.upperSideSpill, height: max(0, rect.minY)))
            }
        }
    }

    private func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
