import Foundation
import CoreGraphics

/// Retains the top and bottom pixels while resizing only the straight sides of an input.
public struct InputHeightResize {
    public let sourceStart, sourceEnd, targetStart, targetEnd: CGFloat

    public init?(source: InputContour, target: InputContour) {
        let old = source.main, new = target.main
        guard old.radius == new.radius, old.style == new.style, old.corners == .all, new.corners == .all,
              old.rect.minX == new.rect.minX, old.rect.width == new.rect.width,
              source.bars.count == target.bars.count else { return nil }
        let margin = old.radius * (old.style == .continuous ? 2 : 1) + 1
        sourceStart = old.rect.minY + margin; sourceEnd = old.rect.maxY - margin
        targetStart = new.rect.minY + margin; targetEnd = new.rect.maxY - margin
        guard sourceEnd > sourceStart, targetEnd > targetStart else { return nil }
        for (before, after) in zip(source.bars, target.bars) {
            let shift: CGFloat
            if before.rect.maxY <= sourceStart && after.rect.maxY <= targetStart {
                shift = new.rect.minY - old.rect.minY
            } else if before.rect.minY >= sourceEnd && after.rect.minY >= targetEnd {
                shift = new.rect.maxY - old.rect.maxY
            } else { return nil }
            var expected = before
            expected.rect = before.rect.offsetBy(dx: 0, dy: shift)
            guard after == expected else { return nil }
        }
    }

    public func sourceY(_ y: CGFloat) -> CGFloat {
        if y <= targetStart { return y + sourceStart - targetStart }
        if y >= targetEnd { return y + sourceEnd - targetEnd }
        return sourceStart + (y - targetStart) * (sourceEnd - sourceStart) / (targetEnd - targetStart)
    }
}
