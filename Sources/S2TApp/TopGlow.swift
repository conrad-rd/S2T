import AppKit
import SwiftUI
import S2TCore

extension GlowDisplay {
    init(screen: NSScreen) {
        self.init(frame: screen.frame, safeTop: screen.safeAreaInsets.top,
                  topLeft: screen.auxiliaryTopLeftArea, topRight: screen.auxiliaryTopRightArea)
    }
}

struct TopGlow: View {
    var renderedProfile: GlowProfile? = nil
    var showsBackdrop = true
    let layout: TopGlowLayout
    let strength: Double
    let phase: DictationPhase
    let levelProvider: () -> Double
    var spectrumProvider: (() -> [Double])? = nil
    var timeOverride: Double? = nil
    var reduceTransparencyOverride: Bool? = nil
    @State private var history = GlowHistory(smoothAudio: true)
    @State private var crossfade = GlowPhaseCrossfade()
    var reduceMotionOverride: Bool? = nil
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ObservedObject var animationClock = GlowAnimationClock()
    var response = GlowResponseSettings()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: timeOverride != nil || !animationClock.running)) { timeline in
            let time = timeOverride ?? timeline.date.timeIntervalSinceReferenceDate
            let profile = profile(time: time)
            let working = phase.processingAudio
            let live = timeOverride == nil && renderedProfile == nil
            let handoff = live ? crossfade.progress(working: working, completing: phase == .complete, time: time, reducedMotion: reduceMotion) : 1
            let listeningRequest: ChromaFrameRequest? = {
                guard live else { return nil }
                guard !working else { return handoff < 1 ? crossfade.listeningRequest : nil }
                let request = ChromaFrameRequest(geometry: .notch(layout), size: layout.frame.size,
                    profile: profile, brightness: phase == .complete ? 0.3 : profile.speechGain,
                    backdrop: showsBackdrop && !(reduceTransparencyOverride ?? reduceTransparency))
                crossfade.listeningRequest = request
                return request
            }()
            let loading = working || (handoff < 1 && crossfade.fromWorking)
            ZStack {
                if let listeningRequest {
                    PreparedChromaGlow(request: listeningRequest, cycleTime: reduceMotion ? nil : time,
                        fade: GlowPhaseCrossfade.listeningOpacity(working: working, progress: handoff),
                            backdropFade: working ? 0 : handoff)
                }
                if !live || loading {
                    if showsBackdrop && !(reduceTransparencyOverride ?? reduceTransparency) && (handoff == 1 || working) {
                        GlowBackdrop(profile: profile)
                    }
                    Canvas(colorMode: loading ? .linear : .nonLinear) { context, size in
                        draw(context: &context, size: size, profile: profile, time: time, loading: loading)
                    }
                    .opacity(!live ? 1 : working ? handoff : 1 - handoff)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    private func profile(time: Double) -> GlowProfile {
        if var renderedProfile {
            renderedProfile.response = response
            renderedProfile.active = !phase.processingAudio
            renderedProfile.reducedMotion = reduceMotion
            return renderedProfile
        }
        var profile = history.frame(level: phase.processingAudio ? 0 : levelProvider(), time: time, reducedMotion: reduceMotion, bands: phase.processingAudio ? [] : spectrumProvider?() ?? [], active: !phase.processingAudio)
        profile.sweepStrength = strength
        profile.response = response
        profile.topLayout = layout
        return profile
    }

    private func edgePath() -> Path { Self.edgePath(layout: layout) }

    static func edgePath(layout: TopGlowLayout) -> Path {
        Path { path in
            path.move(to: .zero)
            if let notch = layout.notch {
                let r = layout.cornerRadius
                let c = r * 0.55228475
                let join = layout.topJoinRadius
                let joinControl = join * 0.55228475
                path.addLine(to: CGPoint(x: notch.minX - join, y: 0))
                path.addCurve(to: CGPoint(x: notch.minX, y: join),
                              control1: CGPoint(x: notch.minX - join + joinControl, y: 0),
                              control2: CGPoint(x: notch.minX, y: join - joinControl))
                path.addLine(to: CGPoint(x: notch.minX, y: notch.maxY - r))
                path.addCurve(to: CGPoint(x: notch.minX + r, y: notch.maxY),
                              control1: CGPoint(x: notch.minX, y: notch.maxY - r + c),
                              control2: CGPoint(x: notch.minX + r - c, y: notch.maxY))
                path.addLine(to: CGPoint(x: notch.maxX - r, y: notch.maxY))
                path.addCurve(to: CGPoint(x: notch.maxX, y: notch.maxY - r),
                              control1: CGPoint(x: notch.maxX - r + c, y: notch.maxY),
                              control2: CGPoint(x: notch.maxX, y: notch.maxY - r + c))
                path.addLine(to: CGPoint(x: notch.maxX, y: join))
                path.addCurve(to: CGPoint(x: notch.maxX + join, y: 0),
                              control1: CGPoint(x: notch.maxX, y: join - joinControl),
                              control2: CGPoint(x: notch.maxX + join - joinControl, y: 0))
            }
            path.addLine(to: CGPoint(x: layout.frame.width, y: 0))
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, profile: GlowProfile, time: Double, loading: Bool) {
        let edge = edgePath()
        var outside = edge
        outside.addLine(to: CGPoint(x: size.width, y: size.height))
        outside.addLine(to: CGPoint(x: 0, y: size.height))
        outside.closeSubpath()
        context.clip(to: outside)
        let gradient = auraGradient(distortion: profile.distortion)
        let brightness = loading ? 0.75 : phase == .complete ? 0.3 : profile.speechGain
        context.drawLayer { strip in
            if loading {
                ContourGlow.draw(context: &strip, path: edge, gradient: gradient,
                                 extent: 10, brightness: brightness, gentle: true)
            } else {
                drawAura(context: &strip, edge: edge, size: size, profile: profile, brightness: brightness, time: time)
            }
            if loading {
                let progress = reduceMotion ? 0.5 : time.truncatingRemainder(dividingBy: 2.8) / 2.8
                let center = progress * (size.width + 140) - 70
                strip.stroke(edge, with: .linearGradient(Gradient(colors: [.clear, .white, .clear]),
                    startPoint: CGPoint(x: center - 70, y: 0), endPoint: CGPoint(x: center + 70, y: 0)), lineWidth: 3)
            }
            strip.opacity = 1
            strip.blendMode = .destinationIn
            let stops = (0...64).map { index in
                Gradient.Stop(color: .white.opacity(layout.sideOpacity(at: size.width * Double(index) / 64)), location: Double(index) / 64)
            }
            strip.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: stops),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
        }
    }

    private func auraGradient(distortion: GlowDistortion, light: Double = 0) -> GraphicsContext.Shading {
        let bounds = NotchAura.paletteBounds(layout: layout)
        let stops: [Gradient.Stop] = (0...64).map { index in
            let position = Double(index) / 64
            let authored = NotchAura.palette
            let next = authored.firstIndex(where: { $0.position >= position }) ?? authored.count - 1
            let previous = max(0, next - 1)
            let a = authored[previous], b = authored[next]
            let t = next == previous ? 0 : (position - a.position) / (b.position - a.position)
            let rgb = (0..<3).map { light + (1 - light) * (a.rgb[$0] + (b.rgb[$0] - a.rgb[$0]) * t) }
            let color = phase == .failed ? Color.orange : Color(red: rgb[0], green: rgb[1], blue: rgb[2])
            return .init(color: color.opacity(NotchAura.illumination(at: position, distortion: distortion)), location: position)
        }
        return .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: bounds.lowerBound, y: 0),
                               endPoint: CGPoint(x: bounds.upperBound, y: 0))
    }

    private func drawAura(context: inout GraphicsContext, edge: Path, size: CGSize,
                          profile: GlowProfile, brightness: Double, time: Double) {
        ChromaAppearance.draw(context: &context, geometry: .notch(layout), size: size,
            brightness: brightness, distortion: NotchAura.deformation(profile.distortion), expansion: profile.speechExpansion, width: profile.response.width, tuning: profile.response.tuning, cycleTime: reduceMotion || timeOverride != nil ? nil : time * profile.response.tuning.gradientSpeed * GlowColorCycle.duration)
    }

    static func colorMask(layout: TopGlowLayout, size: NSSize, strength: Double, distortion: GlowDistortion, scale: CGFloat = 1) -> NSImage? {
        ChromaAppearance.assets(geometry: .notch(layout), size: size)?.color
    }

    static func highlightMask(layout: TopGlowLayout, size: NSSize, scale: CGFloat) -> NSImage? {
        ChromaAppearance.assets(geometry: .notch(layout), size: size)?.edge
    }

    static func radiusMap(layout: TopGlowLayout, energy: Double, size: NSSize, strength: Double = 1, distortion: GlowDistortion = .identity, expansion: Double = 1, width: Double = 1, falloff: Double = 1) -> NSImage? {
        var outside = edgePath(layout: layout)
        outside.addLine(to: CGPoint(x: size.width, y: size.height))
        outside.addLine(to: CGPoint(x: 0, y: size.height))
        outside.closeSubpath()
        return ChromaAppearance.radiusMap(geometry: .notch(layout), size: size,
            distortion: NotchAura.deformation(distortion), exterior: outside, expansion: expansion, width: width, falloff: falloff)
    }
}
