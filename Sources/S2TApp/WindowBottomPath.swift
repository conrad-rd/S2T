import SwiftUI
import S2TCore

extension WindowBottomLayout {
    var edgePath: Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: frame.height - leftRadius))
        if leftRadius > 0 {
            path.addArc(center: CGPoint(x: leftRadius, y: frame.height - leftRadius), radius: leftRadius,
                startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        }
        path.addLine(to: CGPoint(x: frame.width - rightRadius, y: frame.height))
        if rightRadius > 0 {
            path.addArc(center: CGPoint(x: frame.width - rightRadius, y: frame.height - rightRadius), radius: rightRadius,
                startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        }
        return path
    }

    var clipPath: Path {
        var path = edgePath
        path.addLine(to: CGPoint(x: frame.width, y: 0))
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }
}
