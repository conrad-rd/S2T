import AppKit

@MainActor enum SidebarGlyph: String, CaseIterable {
    case dashboard, appearance, models, keys, writing, meetings, recordings, dictation

    private enum Mark {
        case box(CGRect, CGFloat)
        case circle(CGPoint, CGFloat)
        case line([CGPoint])

        var path: NSBezierPath {
            switch self {
            case let .box(rect, radius): return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            case let .circle(center, radius): return NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            case let .line(points):
                let path = NSBezierPath()
                if let first = points.first { path.move(to: first) }
                points.dropFirst().forEach { path.line(to: $0) }
                return path
            }
        }
        var svg: String {
            switch self {
            case let .box(r, radius): return "<rect x=\"\(r.minX)\" y=\"\(r.minY)\" width=\"\(r.width)\" height=\"\(r.height)\" rx=\"\(radius)\"/>"
            case let .circle(c, radius): return "<circle cx=\"\(c.x)\" cy=\"\(c.y)\" r=\"\(radius)\"/>"
            case let .line(points): return "<polyline points=\"\(points.map { "\($0.x),\($0.y)" }.joined(separator: " "))\"/>"
            }
        }
    }

    private var marks: [Mark] {
        switch self {
        case .dictation:
            return [.box(CGRect(x: 9, y: 3, width: 6, height: 12), 3),
                    .line([CGPoint(x: 5, y: 11), CGPoint(x: 5, y: 13), CGPoint(x: 7, y: 17), CGPoint(x: 12, y: 19), CGPoint(x: 17, y: 17), CGPoint(x: 19, y: 13), CGPoint(x: 19, y: 11)]),
                    .line([CGPoint(x: 12, y: 19), CGPoint(x: 12, y: 22)]),
                    .line([CGPoint(x: 8, y: 22), CGPoint(x: 16, y: 22)])]
        case .recordings:
            return [.circle(CGPoint(x: 12, y: 12), 8), .line([CGPoint(x: 12, y: 7), CGPoint(x: 12, y: 12), CGPoint(x: 16, y: 14)])]
        case .dashboard:
            return [.box(CGRect(x: 3, y: 3, width: 18, height: 18), 4),
                    .line([CGPoint(x: 7, y: 16), CGPoint(x: 7, y: 12)]),
                    .line([CGPoint(x: 12, y: 16), CGPoint(x: 12, y: 7)]),
                    .line([CGPoint(x: 17, y: 16), CGPoint(x: 17, y: 10)])]
        case .appearance:
            return [.box(CGRect(x: 3, y: 4, width: 18, height: 16), 4),
                    .line([CGPoint(x: 7, y: 10), CGPoint(x: 12, y: 10)]),
                    .circle(CGPoint(x: 17, y: 10), 1),
                    .line([CGPoint(x: 7, y: 15), CGPoint(x: 17, y: 15)])]
        case .models:
            var result: [Mark] = [.box(CGRect(x: 6, y: 6, width: 12, height: 12), 3), .box(CGRect(x: 10, y: 10, width: 4, height: 4), 1)]
            for offset in [CGFloat(9), 15] {
                result += [.line([CGPoint(x: offset, y: 3), CGPoint(x: offset, y: 6)]),
                           .line([CGPoint(x: offset, y: 18), CGPoint(x: offset, y: 21)]),
                           .line([CGPoint(x: 3, y: offset), CGPoint(x: 6, y: offset)]),
                           .line([CGPoint(x: 18, y: offset), CGPoint(x: 21, y: offset)])]
            }
            return result
        case .meetings:
            return [.circle(CGPoint(x: 8, y: 7), 3), .circle(CGPoint(x: 17, y: 9), 2.5),
                    .box(CGRect(x: 2, y: 13, width: 12, height: 8), 3),
                    .line([CGPoint(x: 16, y: 15), CGPoint(x: 21, y: 15), CGPoint(x: 21, y: 21)])]
        case .writing:
            return [.box(CGRect(x: 5, y: 3, width: 14, height: 18), 2),
                    .line([CGPoint(x: 8, y: 8), CGPoint(x: 16, y: 8)]),
                    .line([CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)]),
                    .line([CGPoint(x: 8, y: 16), CGPoint(x: 13, y: 16)])]
        case .keys:
            return [.circle(CGPoint(x: 7, y: 10), 4),
                    .line([CGPoint(x: 11, y: 10), CGPoint(x: 21, y: 10), CGPoint(x: 21, y: 15), CGPoint(x: 17, y: 15), CGPoint(x: 17, y: 12)])]
        }
    }

    private static let images: [SidebarGlyph: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { icon in
        let paths = icon.marks.map(\.path)
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSColor.white.setStroke()
            for path in paths {
                path.lineWidth = 1.8
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = icon.rawValue
        return (icon, image)
    })
    var image: NSImage { Self.images[self]! }
    var svg: String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#fff\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(marks.map(\.svg).joined())</svg>"
    }
}
