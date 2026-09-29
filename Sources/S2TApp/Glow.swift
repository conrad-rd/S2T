import AppKit
import SwiftUI
import Combine
import S2TCore

struct BottomGlow: View {
    let level: Double
    let strength: Double
    let phase: DictationPhase
    var timeOverride: Double? = nil
    var levelProvider: (() -> Double)? = nil
    var spectrumProvider: (() -> [Double])? = nil
    var reduceMotionOverride: Bool? = nil
    var reduceTransparencyOverride: Bool? = nil
    var showsBackdrop = false
    var renderedProfile: GlowProfile? = nil
    var windowBottom: WindowBottomLayout? = nil
    @State private var history = GlowHistory(smoothAudio: true)
    @State private var crossfade = GlowPhaseCrossfade()
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    @ObservedObject var animationClock = GlowAnimationClock()
    var response = GlowResponseSettings()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: timeOverride != nil || !animationClock.running)) { timeline in
                let time = timeOverride ?? timeline.date.timeIntervalSinceReferenceDate
                let working = phase.processingAudio
                let liveLevel = working ? 0 : levelProvider?() ?? level
                let profile: GlowProfile = {
                    var frame = renderedProfile ?? history.frame(level: liveLevel, time: time, reducedMotion: reduceMotion, bands: working ? [] : spectrumProvider?() ?? [], active: !working)
                    frame.windowBottom = windowBottom
                    frame.sweepStrength = strength
                    frame.response = response
                    frame.active = !working
                    frame.reducedMotion = reduceMotion
                    return frame
                }()
                let fieldHeight = min(geometry.size.height, GlowProfile.extent * response.paddingScale)
                let live = timeOverride == nil && renderedProfile == nil
                let handoff = live ? crossfade.progress(working: working, completing: phase == .complete, time: time, reducedMotion: reduceMotion) : 1
                let listeningRequest: ChromaFrameRequest? = {
                    guard live else { return nil }
                    let size = CGSize(width: geometry.size.width, height: fieldHeight)
                    guard !working else {
                        // A followed window may move while processing; drop a frame drawn for the old spot.
                        guard handoff < 1, let held = crossfade.listeningRequest,
                              held.geometry == profile.chromaGeometry, held.size == size else { return nil }
                        return held
                    }
                    let request = ChromaFrameRequest(geometry: profile.chromaGeometry,
                        size: size, profile: profile,
                        brightness: phase == .complete ? 0.22 : profile.speechGain,
                        backdrop: showsBackdrop && !reduceTransparency)
                    crossfade.listeningRequest = request
                    return request
                }()
                let loading = working || (handoff < 1 && crossfade.fromWorking)
                let loadingOpacity = !live ? 1 : working ? handoff : 1 - handoff
                ZStack(alignment: .bottom) {
                    if let listeningRequest {
                        PreparedChromaGlow(request: listeningRequest, cycleTime: reduceMotion ? nil : time,
                            fade: GlowPhaseCrossfade.listeningOpacity(working: working, progress: handoff),
                            backdropFade: working ? 0 : handoff)
                            .frame(height: fieldHeight)
                    }
                    if !live || loading {
                        // During a handoff the listening frame owns native blur, so the
                        // indicator's zero-blur profile cannot flicker against it.
                        if showsBackdrop && !reduceTransparency && (handoff == 1 || working) {
                            GlowBackdrop(profile: profile)
                                .frame(maxWidth: .infinity)
                                .frame(height: fieldHeight)
                        }
                        Canvas(colorMode: loading ? .linear : .nonLinear) { context, size in
                            if loading {
                                loadingLine(context: &context, size: size, time: time)
                            } else {
                                listening(context: &context, size: size, profile: profile, time: time)
                            }
                        }
                        .opacity(loadingOpacity)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func listening(context: inout GraphicsContext, size: CGSize, profile: GlowProfile, time: Double) {
        let brightness = phase == .complete ? 0.22 : profile.speechGain
        ChromaAppearance.draw(context: &context, geometry: profile.chromaGeometry, size: size,
                              brightness: brightness, distortion: profile.distortion, expansion: profile.speechExpansion, width: profile.response.width, tuning: profile.response.tuning, cycleTime: reduceMotion || timeOverride != nil ? nil : time * profile.response.tuning.gradientSpeed * GlowColorCycle.duration)
    }

    private func loadingLine(context: inout GraphicsContext, size: CGSize, time: Double) {
        if let windowBottom {
            windowLoading(context: &context, layout: windowBottom, time: time)
            return
        }
        let brightness = 0.4 + min(1, max(0, strength)) * 0.5
        let blue = Color(red: 0.28, green: 0.55, blue: 1)
        let violet = Color(red: 0.68, green: 0.4, blue: 1)
        let base = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [blue.opacity(0.25), violet, blue.opacity(0.25)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        let edge = Path(CGRect(x: 0, y: size.height - 3, width: size.width, height: 3))
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 6))
            glow.opacity = brightness * 0.70
            glow.fill(Path(CGRect(x: 0, y: size.height - 5, width: size.width, height: 5)), with: base)
        }
        context.drawLayer { track in
            track.opacity = brightness * 0.70
            track.fill(edge, with: base)
        }

        let width = size.width * 0.3
        let progress = time.truncatingRemainder(dividingBy: 2.8) / 2.8
        let start = reduceMotion ? (size.width - width) / 2 : progress * (size.width + width) - width
        let shimmer = GraphicsContext.Shading.linearGradient(
            Gradient(stops: ProcessingSweep.stops.map { stop in
                .init(color: Color(red: stop.rgb[0], green: stop.rgb[1], blue: stop.rgb[2]).opacity(stop.opacity),
                      location: stop.position)
            }), startPoint: CGPoint(x: start, y: 0), endPoint: CGPoint(x: start + width, y: 0))
        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: 5))
            bloom.opacity = brightness
            bloom.fill(Path(CGRect(x: 0, y: size.height - 6, width: size.width, height: 6)), with: shimmer)
        }
        context.opacity = brightness
        context.fill(edge, with: shimmer)
    }

    private func windowLoading(context: inout GraphicsContext, layout: WindowBottomLayout, time: Double) {
        context.clip(to: layout.clipPath)
        let path = layout.edgePath
        let width = layout.frame.width * 0.3
        let start = WindowBottomLoading.start(width: layout.frame.width, time: time, reducedMotion: reduceMotion)
        let shading = GraphicsContext.Shading.linearGradient(Gradient(stops: ProcessingSweep.stops.map {
            .init(color: Color(red: $0.rgb[0], green: $0.rgb[1], blue: $0.rgb[2]).opacity($0.opacity), location: $0.position)
        }), startPoint: CGPoint(x: start, y: 0), endPoint: CGPoint(x: start + width, y: 0))
        context.stroke(path, with: .color(Color(red: 0.38, green: 0.45, blue: 1).opacity(0.35)), lineWidth: 4)
        context.drawLayer { bloom in
            bloom.addFilter(.blur(radius: 5))
            bloom.stroke(path, with: shading, lineWidth: 10)
        }
        context.stroke(path, with: shading, lineWidth: 6)
    }

}

enum WindowBottomLoading {
    static func start(width: Double, time: Double, reducedMotion: Bool) -> Double {
        let travel = width * 0.7
        return reducedMotion ? travel / 2 : travel * (0.5 - 0.5 * cos(time * .pi / 1.4))
    }
}

enum S2TTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
}
final class GlowOverlayPlacement: ObservableObject {
    @Published var top: TopGlowLayout?
    @Published var bottom: WindowBottomLayout?
}

@MainActor final class GlowAnimationClock: ObservableObject {
    @Published var running = true
}

struct OverlayContent: View {
    @ObservedObject var animationClock = GlowAnimationClock()
    @ObservedObject var state: AppState
    @ObservedObject var placement = GlowOverlayPlacement()
    var levelProvider: (() -> Double)? = nil
    var spectrumProvider: (() -> [Double])? = nil
    var body: some View {
        ZStack(alignment: placement.top == nil ? .bottom : .top) {
            if let top = placement.top {
                TopGlow(layout: top, strength: state.glowStrength, phase: state.phase, levelProvider: levelProvider ?? { state.glowLevel }, spectrumProvider: spectrumProvider ?? { state.speechSpectrum }, animationClock: animationClock, response: state.glowResponseSettings)
            } else {
                BottomGlow(level: 0, strength: state.glowStrength, phase: state.phase, levelProvider: levelProvider ?? { state.glowLevel }, spectrumProvider: spectrumProvider ?? { state.speechSpectrum }, showsBackdrop: true, windowBottom: placement.bottom, animationClock: animationClock, response: state.glowResponseSettings)
            }
            if state.phase == .complete, let hint = state.pasteHint {
                Text(hint)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .padding(placement.top == nil ? .bottom : .top, (placement.top?.notch?.height ?? 0) + 20)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

@MainActor final class GlowWindowController {
    private var panel: NSPanel?
    private let state: AppState
    private var visibility: OverlayVisibility?
    private let placement = GlowOverlayPlacement()
    private let animationClock = GlowAnimationClock()
    private var subscriptions = Set<AnyCancellable>()
    private var isPresented = false
    private var displayTimer: Timer?
    private let inputTracker = FocusedInputTracker()
    private var inputPreparation: Task<Void, Never>?
    private lazy var glass = GlassWaveformController(state: state)
    private let inputProcessing = InputProcessingController()
    private lazy var inputOutline = InputOutlineWindowController(state: state)

    init(state: AppState) {
        self.state = state
        inputTracker.onFocusChanged = { [weak self] in self?.prepareInputAppearance() }
        state.$glowAppearance.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.prepareInputAccessibility()
                guard self.isPresented else { return }
                self.inputTracker.invalidate()
                self.state.bottomWindowTracker.invalidate()
                self.update(visible: true)
            }
        }.store(in: &subscriptions)
        state.$phase.map(\.processingAudio).removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented, self.state.glowAppearance == .withinInput else { return }
                self.inputTracker.invalidate()
                self.update(visible: true)
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.prepareInputAccessibility()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, self.isPresented else { return }
                self.update(visible: true)
            }.store(in: &subscriptions)
        prepareInputAccessibility()
    }

    private func prepareInputAccessibility() {
        guard !state.isPreview, !state.needsInstallation, state.glowAppearance.followsInput else { return }
        inputTracker.prepareAccessibility()
        prepareInputAppearance()
    }

    private func prepareInputAppearance() {
        inputPreparation?.cancel()
        guard !isPresented, !state.isPreview, !state.needsInstallation, state.glowAppearance.followsInput else { return }
        inputPreparation = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self, !self.isPresented, self.state.glowAppearance.followsInput else { return }
            for _ in 0..<12 where self.inputOutline.panel?.isVisible == true {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
            guard !Task.isCancelled, !self.isPresented, self.inputOutline.panel?.isVisible != true else { return }
            self.inputTracker.refresh(disabledPresets: self.state.disabledInputPresets) { [weak self] target, _ in
                guard let self, !self.isPresented, self.state.glowAppearance.followsInput,
                      let target, target.kind == .input else { return }
                self.inputOutline.prepareForActivation(target: target)
            }
        }
    }

    func update(visible: Bool) {
        isPresented = visible
        inputPreparation?.cancel()
        guard visible else {
            displayTimer?.invalidate()
            displayTimer = nil
            visibility?.setVisible(false)
            inputTracker.invalidate()
            state.bottomWindowTracker.invalidate()
            inputOutline.hide()
            inputProcessing.hide()
            glass.hide()
            prepareInputAppearance()
            return
        }
        if !state.glowAppearance.isClassic { glass.hide() }
        let processingInput = state.glowAppearance == .withinInput && WithinInputProcessing.isActive(state.phase)
        if !processingInput { inputProcessing.hide() }
        if state.glowAppearance == .withinInput && !processingInput && (state.phase == .complete || state.phase == .failed || state.phase == .idle) {
            inputTracker.invalidate()
            inputOutline.hide()
            visibility?.setVisible(false)
            return
        }
        let interval = state.glowAppearance.followsInput ? FocusedInputTracker.refreshInterval : state.glowAppearance == .bottom ? 1.0 / 30 : 0.2
        if displayTimer?.timeInterval != interval {
            displayTimer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(visible: true) }
            }
            RunLoop.main.add(timer, forMode: .common)
            displayTimer = timer
        }
        if state.glowAppearance.isClassic {
            visibility?.setVisible(false)
            inputTracker.invalidate()
            inputOutline.hide()
            glass.show(screens: NSScreen.screens, pointer: NSEvent.mouseLocation)
            return
        }
        glass.hide()
        if state.glowAppearance.followsInput {
            let pinned = state.promptDeliveryTarget
            let completion: (InputOutlineTarget?, String?) -> Void = { [weak self] frame, notice in
                guard let self, self.isPresented, self.state.glowAppearance.followsInput else { return }
                guard (pinned != nil) == (self.state.promptDeliveryTarget != nil) else { return }
                guard processingInput == (self.state.glowAppearance == .withinInput && WithinInputProcessing.isActive(self.state.phase)) else { return }
                if pinned != nil, frame == nil {
                    self.inputOutline.hide()
                    self.inputProcessing.hide()
                    self.visibility?.setVisible(false)
                    return
                }
                if processingInput {
                    self.inputOutline.hide()
                    if let frame, WithinInputProcessing.accepts(frame) {
                        if self.state.inputOutlineNotice != nil { self.state.inputOutlineNotice = nil }
                        self.visibility?.setVisible(false)
                        self.inputProcessing.show(target: frame, gradient: self.state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init())
                    } else {
                        self.inputProcessing.hide()
                        self.state.inputOutlineNotice = "Message bar unavailable. Using Bottom."
                        self.showScreenGlow()
                    }
                    return
                }
                if self.state.glowAppearance == .withinInput && (self.state.phase == .complete || self.state.phase == .failed || self.state.phase == .idle) { return }
                if self.state.inputOutlineNotice != notice { self.state.inputOutlineNotice = notice }
                if let frame, frame.kind == .input {
                    self.visibility?.setVisible(false)
                    self.inputOutline.show(target: frame)
                } else {
                    self.inputOutline.hide()
                    if self.state.glowAppearance == .withinInput {
                        self.state.inputOutlineNotice = "Message bar unavailable. Using Bottom."
                        self.showScreenGlow()
                    } else { self.showScreenGlow() }
                }
            }
            if let pinned { inputTracker.refreshPinned(pinned, disabledPresets: state.disabledInputPresets, completion: completion) }
            else { inputTracker.refresh(disabledPresets: state.disabledInputPresets, completion: completion) }
            return
        }
        inputOutline.hide()
        if state.inputOutlineNotice != nil { state.inputOutlineNotice = nil }
        if state.glowAppearance == .bottom && !state.isPreview {
            state.bottomWindowTracker.refresh { [weak self] target in
                guard let self, self.isPresented, self.state.glowAppearance == .bottom else { return }
                if target == nil, self.state.bottomWindowTracker.pinsPromptDestination {
                    self.visibility?.setVisible(false)
                    return
                }
                self.showScreenGlow(window: target)
            }
        } else { showScreenGlow() }
    }

    private func showScreenGlow(window: BottomWindowFrame? = nil) {
        guard prepareWindow(screens: NSScreen.screens, pointer: NSEvent.mouseLocation, window: window) != nil else {
            visibility?.setVisible(false)
            return
        }
        visibility?.setVisible(true)
    }

    func prepareWindow(screens: [NSScreen], pointer: NSPoint, window: BottomWindowFrame? = nil) -> NSPanel? {
        let displays = screens.map { GlowDisplay(screen: $0) }
        guard let index = GlowDisplay.preferredIndex(in: displays, pointer: pointer) else { return nil }
        let screen = screens[index]
        let top = state.glowAppearance == .aroundNotch ? TopGlowLayout(display: displays[index], paddingScale: state.glowResponseSettings.paddingScale) : nil
        let bounds = screen.frame
        let windowLayout = state.glowAppearance == .bottom ? window?.layout(maximumHeight: GlowProfile.extent * state.glowResponseSettings.paddingScale) : nil
        let bottom = windowLayout.map { WindowBottomLayout(window: CGRect(origin: .zero, size: $0.frame.size), leftRadius: $0.leftRadius, rightRadius: $0.rightRadius, maximumHeight: $0.frame.height) }
        let frame = top?.frame ?? windowLayout?.frame ?? NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: min(bounds.height, GlowProfile.extent * state.glowResponseSettings.paddingScale))
        let level = top == nil ? NSWindow.Level.statusBar : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        if let panel, panel.frame == frame, placement.top == top, placement.bottom == bottom, panel.level == level { return panel }
        if let panel, panel.frame.size == frame.size, placement.top == top, placement.bottom == bottom, panel.level == level {
            panel.setFrameOrigin(frame.origin)
            return panel
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if placement.top != top { placement.top = top }
        if placement.bottom != bottom { placement.bottom = bottom }
        if panel == nil {
            let panel = BackdropWindowHosting.makePanel()
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = level
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.setFrame(frame, display: false)
            let root = ProgressiveBackdropView.hosting(OverlayContent(animationClock: animationClock, state: state, placement: placement))
            root.preparesFramesAsynchronously = true
            panel.contentView = root
            self.panel = panel
            visibility = OverlayVisibility(panel: panel, animationClock: animationClock, appearanceDuration: 0)
        }
        guard let panel else { return nil }
        if panel.level != level { panel.level = level }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        (panel.contentView as? ProgressiveBackdropView)?.prepareGeometry(top.map { .notch($0) } ?? bottom.map { .windowBottom($0) } ?? .bottom)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        return panel
    }

    deinit { displayTimer?.invalidate(); inputPreparation?.cancel() }

}

@MainActor final class OverlayVisibility {
    private let panel: NSPanel
    private var transition = 0
    private var targetVisible = false
    private let animationClock: GlowAnimationClock?
    let appearanceDuration: TimeInterval

    init(panel: NSPanel, animationClock: GlowAnimationClock? = nil, appearanceDuration: TimeInterval = 0.18) {
        self.panel = panel
        self.animationClock = animationClock
        self.appearanceDuration = appearanceDuration
    }

    func setVisible(_ visible: Bool) {
        guard visible != targetVisible else { return }
        targetVisible = visible
        transition += 1
        let generation = transition
        if visible {
            animationClock?.running = true
            if !panel.isVisible { panel.alphaValue = appearanceDuration == 0 ? 1 : 0 }
            panel.orderFrontRegardless()
            if appearanceDuration == 0 { panel.alphaValue = 1; return }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (visible ? appearanceDuration : 0.22)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.transition == generation, !self.targetVisible else { return }
                self.panel.orderOut(nil)
                self.animationClock?.running = false
            }
        }
    }
}
