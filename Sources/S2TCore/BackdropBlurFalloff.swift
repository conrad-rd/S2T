import Foundation

public enum BackdropBlurFalloff {
    public static func strength(_ coverage: Double, remainingFraction: Double = 1) -> Double {
        let tail = max(0, min(1, remainingFraction))
        return 0.6 * sqrt(max(0, min(1, coverage))) * tail * tail * (3 - 2 * tail)
    }
}
