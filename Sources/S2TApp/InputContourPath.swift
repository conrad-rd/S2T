import SwiftUI
import S2TCore

extension InputContour {
    private final class CachedPath {
        let path: Path
        init(_ path: Path) { self.path = path }
    }
    private static let paths: NSCache<NSString, CachedPath> = {
        let result = NSCache<NSString, CachedPath>(); result.countLimit = 64; return result
    }()

    var path: Path {
        let key = String(describing: self) as NSString
        if let cached = Self.paths.object(forKey: key) { return cached.path }
        var result = main.path.cgPath
        for bar in bars { result = result.union(bar.path.cgPath) }
        let path = Path(result)
        Self.paths.setObject(CachedPath(path), forKey: key)
        return path
    }
}

extension InputContour.Part {
    var path: Path {
        let radius = min(radius, min(rect.width, rect.height) / 2)
        if corners == .all {
            return radius >= rect.height / 2
                ? Capsule(style: .circular).path(in: rect)
                : RoundedRectangle(cornerRadius: radius, style: style == .circular ? .circular : .continuous).path(in: rect)
        }
        let top = corners == .top ? radius : 0
        let bottom = corners == .bottom ? radius : 0
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: style == .circular ? .circular : .continuous).path(in: rect)
    }
}
