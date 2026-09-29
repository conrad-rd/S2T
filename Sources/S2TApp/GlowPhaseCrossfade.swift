import Foundation
import S2TCore

/// Crossfades the live glow and the processing indicator instead of cutting between them.
/// Mutated during view evaluation, like GlowHistory.
final class GlowPhaseCrossfade {
    private var handoff = GlowPhaseHandoff()
    var fromWorking: Bool { handoff.fromWorking }
    /// The last listening frame, held still while it fades out.
    var listeningRequest: ChromaFrameRequest?

    func progress(working: Bool, completing: Bool, time: Double, reducedMotion: Bool) -> Double {
        handoff.progress(working: working, completing: completing, time: time, reducedMotion: reducedMotion)
    }

    static func listeningOpacity(working: Bool, progress: Double) -> Double {
        GlowPhaseHandoff.listeningOpacity(working: working, progress: progress)
    }
}
