import AppKit
import SwiftUI
import S2TCore

@MainActor final class InputOutlineLayout: ObservableObject {
    let renderer: ChromaFrameRenderer
    init(renderer: ChromaFrameRenderer? = nil) { self.renderer = renderer ?? ChromaFrameRenderer() }
    var renderSize = CGSize.zero
    var lastGeometrySubmission = -Double.infinity
    func submitProcessingAnimation(_ request: ChromaFrameRequest) {
        guard request.profile.reducedMotion || CACurrentMediaTime() - lastGeometrySubmission >= 1.0 / 30 else { return }
        renderer.submit(request)
    }
    @Published var contour = InputContour(rect: .zero, radius: 12)
    var cornerRadius: CGFloat {
        get { contour.main.radius }
        set { contour.main.radius = newValue }
    }
    var cornerStyle: InputCornerStyle {
        get { contour.main.style }
        set { contour.main.style = newValue }
    }
    var outlineRect: CGRect {
        get { contour.bounds }
        set { contour = InputContour(rect: newValue, radius: cornerRadius, style: cornerStyle) }
    }
}

struct InputOutline: View {
    @ObservedObject var animationClock = GlowAnimationClock()
    var renderedProfile: GlowProfile? = nil
    var showsBackdrop = true
    @State private var history = GlowHistory(smoothAudio: true)
    @State private var crossfade = GlowPhaseCrossfade()
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

    private var processing: Bool { Self.showsProcessing(state.phase) }
    static func showsProcessing(_ phase: DictationPhase) -> Bool {
        phase == .transcribing || phase == .processing
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: timeOverride != nil || !animationClock.running)) { timeline in
            let time = timeOverride ?? timeline.date.timeIntervalSinceReferenceDate
            let profile: GlowProfile = {
                var frame = renderedProfile ?? history.frame(level: processing ? 0 : levelProvider?() ?? state.glowLevel,
                    time: time, reducedMotion: reduceMotion, bands: processing ? [] : spectrumProvider?() ?? state.speechSpectrum, active: !processing)
                frame.inputOutline = InputOutlineBackdrop(contour: layout.contour, strength: state.glowStrength, withinInput: state.glowAppearance == .withinInput)
                frame.response = state.glowResponseSettings
                if state.glowAppearance == .withinInput { frame.response.tuning = frame.response.tuning.forInput(size: layout.contour.bounds.size) }
                frame.active = !processing
                frame.reducedMotion = reduceMotion
                return frame
            }()
            let live = timeOverride == nil && renderedProfile == nil
            let handoff = live ? crossfade.progress(working: processing, completing: state.phase == .complete, time: time, reducedMotion: reduceMotion) : 1
            let loading = processing || (handoff < 1 && crossfade.fromWorking)
            GeometryReader { geometry in
                let listeningRequest: ChromaFrameRequest? = {
                    guard live else { return nil }
                    guard !processing else {
                        // Never fade out a frame drawn for an input that has since moved or resized.
                        guard handoff < 1, let held = crossfade.listeningRequest,
                              held.geometry == profile.inputOutline!.geometry else { return nil }
                        return held
                    }
                    let request = ChromaFrameRequest(geometry: profile.inputOutline!.geometry,
                        size: layout.renderSize == .zero ? geometry.size : layout.renderSize, profile: profile, brightness: profile.speechGain,
                        backdrop: showsBackdrop && !reduceTransparency)
                    crossfade.listeningRequest = request
                    return request
                }()
                ZStack {
                    if let listeningRequest {
                        PreparedChromaGlow(request: listeningRequest, cycleTime: reduceMotion ? nil : time,
                            fade: GlowPhaseCrossfade.listeningOpacity(working: processing, progress: handoff),
                            backdropFade: processing ? 0 : handoff, renderer: layout.renderer,
                            submitRequest: { request in
                                if animationClock.running { layout.renderer.submit(request) }
                            })
                    }
                    if !live || loading {
                        if showsBackdrop && !reduceTransparency && (handoff == 1 || processing) {
                            GlowBackdrop(profile: profile)
                        }
                        Canvas(colorMode: loading ? .linear : .nonLinear) { context, size in
                            let processing = loading
                            let outline = InputOutlineBackdrop(contour: layout.contour, strength: state.glowStrength, withinInput: state.glowAppearance == .withinInput)
                            let path = outline.path
                            let brightness = processing ? 0.35
                                : profile.speechGain
                            context.drawLayer { halo in
                                var exterior = Path(CGRect(origin: .zero, size: size))
                                exterior.addPath(path)
                                if state.glowAppearance == .withinInput { halo.clip(to: WithinInputField(contour: layout.contour).clipPath) }
                                else { halo.clip(to: exterior, style: FillStyle(eoFill: true)) }
                                if !processing {
                                    ChromaAppearance.draw(context: &halo, geometry: profile.inputOutline!.geometry,
                                        size: size, brightness: brightness, distortion: profile.distortion, expansion: profile.speechExpansion, tuning: profile.response.tuning, cycleTime: reduceMotion || timeOverride != nil ? nil : time * profile.response.tuning.gradientSpeed * GlowColorCycle.duration)
                                }
                            }
                            if processing && state.glowAppearance != .withinInput {
                                InputOutlineProcessing.draw(context: &context, path: path, size: size, time: time,
                                    reducedMotion: reduceMotion, reducedTransparency: reduceTransparency)
                            }
                        }
                        .opacity(!live ? 1 : processing ? handoff : 1 - handoff)
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

    init(state: AppState) {
        self.state = state
        animationClock.running = false
    }

    @discardableResult func prepare(field: CGRect, cornerRadius: CGFloat? = nil, cornerStyle: InputCornerStyle = .continuous) -> NSPanel {
        prepare(target: InputOutlineTarget(frame: field, cornerRadius: cornerRadius ?? InputOutlineGeometry.radius(for: field.size), cornerStyle: cornerStyle))
    }

    @discardableResult func prepare(target: InputOutlineTarget) -> NSPanel {
        let field = target.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let isWindow = target.kind == .focusedWindow
        let display = isWindow
            ? NSScreen.screens.map(\.frame).filter { $0.intersects(field) }.reduce(CGRect.null) { $0.union($1) }
            : NSScreen.screens.first(where: { $0.frame.contains(field) })?.frame
        let geometry = InputOutlineGeometry(field: field, paddingScale: state.glowResponseSettings.paddingScale,
            displayFrame: display, clipsToDisplay: isWindow)
        let contour = target.contour.offsetBy(dx: geometry.outlineRect.minX, dy: geometry.outlineRect.minY)
        layout.renderSize = geometry.windowFrame.size
        layout.renderer.prepareGeometry(state.glowAppearance == .withinInput ? .withinInput(contour) : .input(contour), size: geometry.windowFrame.size)
        if let panel, panel.frame == geometry.windowFrame, layout.contour == contour {
            (panel.contentView as? ProgressiveBackdropView)?.prepareGeometry(state.glowAppearance == .withinInput ? .withinInput(contour) : .input(contour))
            return panel
        }
        if layout.contour != contour { layout.contour = contour }
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
                var profile = GlowHistory().frame(level: InputOutline.showsProcessing(state.phase) ? 0 : state.glowLevel,
                    time: 0, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    bands: InputOutline.showsProcessing(state.phase) ? [] : state.speechSpectrum)
                profile.inputOutline = InputOutlineBackdrop(contour: contour, strength: state.glowStrength, withinInput: state.glowAppearance == .withinInput)
                profile.response = state.glowResponseSettings
                if state.glowAppearance == .withinInput { profile.response.tuning = profile.response.tuning.forInput(size: contour.bounds.size) }
                root.profile = profile
            }
            window.contentView = root
            panel = window
            visibility = OverlayVisibility(panel: window, animationClock: animationClock, appearanceDuration: 0)
        }
        let window = panel!
        if window.frame != frame { window.setFrame(frame, display: false) }
        if let root = window.contentView as? ProgressiveBackdropView {
            root.prepareGeometry(state.glowAppearance == .withinInput ? .withinInput(contour) : .input(contour))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    var preparedFrame: ChromaFrame? { layout.renderer.frame }

    func prepareForActivation(target: InputOutlineTarget) {
        guard panel?.isVisible != true else { return }
        animationClock.running = false
        let panel = prepare(target: target)
        var profile = GlowHistory().frame(level: 0, time: 0,
            reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, bands: [])
        profile.inputOutline = InputOutlineBackdrop(contour: layout.contour, strength: state.glowStrength,
            withinInput: state.glowAppearance == .withinInput)
        profile.response = state.glowResponseSettings
        if state.glowAppearance == .withinInput {
            profile.response.tuning = profile.response.tuning.forInput(size: layout.contour.bounds.size)
        }
        layout.renderer.submit(ChromaFrameRequest(geometry: profile.chromaGeometry, size: panel.frame.size,
            profile: profile, brightness: profile.speechGain,
            backdrop: !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
    }

    func show(field: CGRect, cornerRadius: CGFloat? = nil, cornerStyle: InputCornerStyle = .continuous) {
        prepare(field: field, cornerRadius: cornerRadius, cornerStyle: cornerStyle)
        visibility?.setVisible(true)
    }

    func show(target: InputOutlineTarget) {
        prepare(target: target)
        visibility?.setVisible(true)
    }

    func hide() { visibility?.setVisible(false) }
}
