import Foundation

/// Timing for crossfading the live glow and the processing indicator.
/// Only live, continuous handoffs animate: listening into processing, and processing
/// into the completion glow. A new session, a paused timeline or Reduce Motion switches immediately.
public struct GlowPhaseHandoff {
    public static let duration = 0.32
    private var lastWorking: Bool?
    private var lastTime = -Double.infinity
    private var changedAt = -Double.infinity
    /// Whether the phase being faded out was the processing indicator.
    public private(set) var fromWorking = false

    public init() {}

    /// 0 at the handoff, easing to 1 once the new phase fully owns the overlay.
    /// Repeated evaluation of one timestamp returns the same value.
    public mutating func progress(working: Bool, completing: Bool, time: Double, reducedMotion: Bool) -> Double {
        let continuous = time >= lastTime && time - lastTime < 0.25
        if let lastWorking, lastWorking != working {
            if continuous && !reducedMotion && (working || completing) {
                changedAt = time
                fromWorking = lastWorking
            } else {
                changedAt = -.infinity
            }
        }
        lastWorking = working
        lastTime = time
        if reducedMotion { changedAt = -.infinity }
        let linear = min(1, max(0, (time - changedAt) / Self.duration))
        return linear * linear * (3 - 2 * linear)
    }

    /// Opacity for the listening glow during a handoff; 1 outside one.
    public static func listeningOpacity(working: Bool, progress: Double) -> Double {
        working ? 1 - progress : progress
    }
}
