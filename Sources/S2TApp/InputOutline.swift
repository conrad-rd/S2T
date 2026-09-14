import AppKit
import SwiftUI
import S2TCore

@MainActor final class InputOutlineLayout: ObservableObject {
    @Published var cornerRadius: CGFloat = 12
    @Published var cornerStyle: InputCornerStyle = .continuous
    @Published var outlineRect = CGRect.zero
}

struct InputOutline: View {
    @ObservedObject var animationClock = GlowAnimationClock()
    var renderedProfile: GlowProfile? = nil
    var showsBackdrop = true
    @State private var history = GlowHistory(smoothAudio: true)
    @ObservedObject var state: AppState
    @ObservedObject var layout = InputOutlineLayout()
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var reduceMotionOverride: Bool? = nil
    var levelProvider: (() -> Double)? = nil
    var spectrumProvider: (() -> [Double])? = nil
    var timeOverride: Double? = nil
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: timeOverride != nil || !animationClock.running)) { timeline in
            let time = timeOverride ?? timeline.date.timeIntervalSinceReferenceDate
            let profile: GlowProfile = {
                var frame = renderedProfile ?? history.frame(level: state.phase.busy ? 0 : levelProvider?() ?? state.glowLevel,
                    time: time, reducedMotion: reduceMotion, bands: state.phase.busy ? [] : spectrumProvider?() ?? state.speechSpectrum, active: !state.phase.busy)
                frame.inputOutline = InputOutlineBackdrop(rect: layout.outlineRect,
                    cornerRadius: layout.cornerRadius, cornerStyle: layout.cornerStyle, strength: state.glowStrength)
                frame.response = state.glowResponseSettings
                frame.active = !state.phase.busy
                frame.reducedMotion = reduceMotion
                return frame
            }()
            GeometryReader { geometry in
                ZStack {
                    if !state.phase.busy && timeOverride == nil && renderedProfile == nil {
                        PreparedChromaGlow(request: ChromaFrameRequest(geometry: .input(layout.outlineRect, layout.cornerRadius, layout.cornerStyle),
                            size: geometry.size, profile: profile, brightness: profile.speechGain,
                            backdrop: showsBackdrop && !reduceTransparency), cycleTime: reduceMotion ? nil : time)
                    } else {
                        if showsBackdrop && !reduceTransparency {
                            GlowBackdrop(profile: profile)
                        }
                        Canvas(colorMode: state.phase.busy ? .linear : .nonLinear) { context, size in
                            let rect = layout.outlineRect
                            let outline = InputOutlineBackdrop(rect: rect, cornerRadius: layout.cornerRadius, cornerStyle: layout.cornerStyle, strength: state.glowStrength)
                            let path = outline.path
                            let brightness = state.phase.busy ? 0.35
                                : profile.speechGain
                            context.drawLayer { halo in
                                var exterior = Path(CGRect(origin: .zero, size: size))
                                exterior.addPath(path)
                                halo.clip(to: exterior, style: FillStyle(eoFill: true))
                                if !state.phase.busy {
                                    ChromaAppearance.draw(context: &halo, geometry: .input(rect, layout.cornerRadius, layout.cornerStyle),
                                        size: size, brightness: brightness, distortion: profile.distortion, expansion: profile.speechExpansion, tuning: profile.response.tuning, cycleTime: reduceMotion || timeOverride != nil ? nil : time * profile.response.tuning.gradientSpeed * GlowColorCycle.duration)
                                }
                            }
                            if state.phase.busy {
                                InputOutlineProcessing.draw(context: &context, path: path, size: size, time: time,
                                    reducedMotion: reduceMotion, reducedTransparency: reduceTransparency)
                            }


                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor final class InputOutlineWindowController {
    private(set) var panel: NSPanel?
    private var visibility: OverlayVisibility?
    private let state: AppState
    private let layout = InputOutlineLayout()
    private let animationClock = GlowAnimationClock()

    init(state: AppState) { self.state = state }

    @discardableResult func prepare(field: CGRect, cornerRadius: CGFloat? = nil, cornerStyle: InputCornerStyle = .continuous) -> NSPanel {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let radius = cornerRadius ?? InputOutlineGeometry.radius(for: field.size)
        if layout.cornerRadius != radius { layout.cornerRadius = radius }
        if layout.cornerStyle != cornerStyle { layout.cornerStyle = cornerStyle }
        let display = NSScreen.screens.first(where: { $0.frame.contains(field) })?.frame
        let geometry = InputOutlineGeometry(field: field, paddingScale: state.glowResponseSettings.paddingScale, displayFrame: display)
        if layout.outlineRect != geometry.outlineRect { layout.outlineRect = geometry.outlineRect }
        let frame = geometry.windowFrame
        if panel == nil {
            let window = BackdropWindowHosting.makePanel()
            window.setFrame(frame, display: false)
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let root = ProgressiveBackdropView.hosting(InputOutline(animationClock: animationClock, state: state, layout: layout))
            root.preparesFramesAsynchronously = true
            root.frame = CGRect(origin: .zero, size: frame.size)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                var profile = GlowHistory().frame(level: state.phase.busy ? 0 : state.glowLevel,
                    time: 0, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    bands: state.phase.busy ? [] : state.speechSpectrum)
                profile.inputOutline = InputOutlineBackdrop(rect: geometry.outlineRect, cornerRadius: radius, cornerStyle: cornerStyle, strength: state.glowStrength)
                profile.response = state.glowResponseSettings
                root.profile = profile
            }
            window.contentView = root
            panel = window
            visibility = OverlayVisibility(panel: window, animationClock: animationClock)
        }
        let window = panel!
        if window.frame != frame { window.setFrame(frame, display: false) }
        if let root = window.contentView as? ProgressiveBackdropView {
            root.prepareGeometry(.input(geometry.outlineRect, radius, cornerStyle))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    func show(field: CGRect, cornerRadius: CGFloat? = nil, cornerStyle: InputCornerStyle = .continuous) {
        prepare(field: field, cornerRadius: cornerRadius, cornerStyle: cornerStyle)
        visibility?.setVisible(true)
    }

    func hide() { visibility?.setVisible(false) }
}
