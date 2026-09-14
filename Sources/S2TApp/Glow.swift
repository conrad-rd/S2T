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
    @State private var history = GlowHistory(smoothAudio: true)
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
                let working = phase.busy
                let live = working ? 0 : levelProvider?() ?? level
                let profile: GlowProfile = {
                    var frame = renderedProfile ?? history.frame(level: live, time: time, reducedMotion: reduceMotion, bands: working ? [] : spectrumProvider?() ?? [], active: !working)
                    frame.sweepStrength = strength
                    frame.response = response
                    frame.active = !working
                    frame.reducedMotion = reduceMotion
                    return frame
                }()
                let fieldHeight = min(geometry.size.height, GlowProfile.extent * response.paddingScale)
                ZStack(alignment: .bottom) {
                    if !working && timeOverride == nil && renderedProfile == nil {
                        PreparedChromaGlow(request: ChromaFrameRequest(geometry: .bottom,
                            size: CGSize(width: geometry.size.width, height: fieldHeight), profile: profile,
                            brightness: phase == .complete ? 0.22 : profile.speechGain,
                            backdrop: showsBackdrop && !reduceTransparency), cycleTime: reduceMotion ? nil : time)
                            .frame(height: fieldHeight)
                    } else {
                        if showsBackdrop && !reduceTransparency {
                            GlowBackdrop(profile: profile)
                                .frame(maxWidth: .infinity)
                                .frame(height: fieldHeight)
                        }
                        Canvas(colorMode: working ? .linear : .nonLinear) { context, size in
                            if working {
                                loadingLine(context: &context, size: size, time: time)
                            } else {
                                listening(context: &context, size: size, profile: profile, time: time)
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func listening(context: inout GraphicsContext, size: CGSize, profile: GlowProfile, time: Double) {
        let brightness = phase == .complete ? 0.22 : profile.speechGain
        ChromaAppearance.draw(context: &context, geometry: .bottom, size: size,
                              brightness: brightness, distortion: profile.distortion, expansion: profile.speechExpansion, width: profile.response.width, tuning: profile.response.tuning, cycleTime: reduceMotion || timeOverride != nil ? nil : time * profile.response.tuning.gradientSpeed * GlowColorCycle.duration)
    }

    private func loadingLine(context: inout GraphicsContext, size: CGSize, time: Double) {
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


}

enum S2TTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
}
final class GlowOverlayPlacement: ObservableObject {
    @Published var top: TopGlowLayout?
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
                BottomGlow(level: 0, strength: state.glowStrength, phase: state.phase, levelProvider: levelProvider ?? { state.glowLevel }, spectrumProvider: spectrumProvider ?? { state.speechSpectrum }, showsBackdrop: true, animationClock: animationClock, response: state.glowResponseSettings)
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
    private lazy var bezel = BezelWindowController(state: state)
    private lazy var inputOutline = InputOutlineWindowController(state: state)

    init(state: AppState) {
        self.state = state
        state.$glowAppearance.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPresented else { return }
                self.inputTracker.invalidate()
                self.update(visible: true)
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self, self.isPresented else { return }
                self.update(visible: true)
            }.store(in: &subscriptions)
    }

    func update(visible: Bool) {
        isPresented = visible
        guard visible else {
            displayTimer?.invalidate()
            displayTimer = nil
            visibility?.setVisible(false)
            inputTracker.invalidate()
            inputOutline.hide()
            bezel.hide()
            return
        }
        if displayTimer == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(visible: true) }
            }
            RunLoop.main.add(timer, forMode: .common)
            displayTimer = timer
        }
        if state.glowAppearance == .bezel {
            visibility?.setVisible(false)
            inputTracker.invalidate()
            inputOutline.hide()
            bezel.show(screens: NSScreen.screens, pointer: NSEvent.mouseLocation)
            return
        }
        bezel.hide()
        if state.glowAppearance == .aroundInput {
            inputTracker.refresh(disabledPresets: state.disabledInputPresets) { [weak self] frame, notice in
                guard let self, self.isPresented, self.state.glowAppearance == .aroundInput else { return }
                if self.state.inputOutlineNotice != notice { self.state.inputOutlineNotice = notice }
                if let frame {
                    self.visibility?.setVisible(false)
                    self.inputOutline.show(field: frame.frame, cornerRadius: frame.cornerRadius, cornerStyle: frame.cornerStyle)
                } else {
                    self.inputOutline.hide()
                    self.showScreenGlow()
                }
            }
            return
        }
        inputOutline.hide()
        if state.inputOutlineNotice != nil { state.inputOutlineNotice = nil }
        showScreenGlow()
    }

    private func showScreenGlow() {
        guard prepareWindow(screens: NSScreen.screens, pointer: NSEvent.mouseLocation) != nil else {
            visibility?.setVisible(false)
            return
        }
        visibility?.setVisible(true)
    }

    func prepareWindow(screens: [NSScreen], pointer: NSPoint) -> NSPanel? {
        let displays = screens.map { GlowDisplay(screen: $0) }
        guard let index = GlowDisplay.preferredIndex(in: displays, pointer: pointer) else { return nil }
        let screen = screens[index]
        let top = state.glowAppearance == .aroundNotch ? TopGlowLayout(display: displays[index], paddingScale: state.glowResponseSettings.paddingScale) : nil
        let frame = top?.frame ?? NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: min(screen.frame.height, GlowProfile.extent * state.glowResponseSettings.paddingScale))
        let level = top == nil ? NSWindow.Level.statusBar : NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        if let panel, panel.frame == frame, placement.top == top, panel.level == level { return panel }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if placement.top != top { placement.top = top }
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
            visibility = OverlayVisibility(panel: panel, animationClock: animationClock)
        }
        guard let panel else { return nil }
        if panel.level != level { panel.level = level }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        (panel.contentView as? ProgressiveBackdropView)?.prepareGeometry(top.map { .notch($0) } ?? .bottom)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        return panel
    }

    deinit { displayTimer?.invalidate() }

}

@MainActor final class OverlayVisibility {
    private let panel: NSPanel
    private var transition = 0
    private var targetVisible = false
    private let animationClock: GlowAnimationClock?

    init(panel: NSPanel, animationClock: GlowAnimationClock? = nil) {
        self.panel = panel
        self.animationClock = animationClock
    }

    func setVisible(_ visible: Bool) {
        guard visible != targetVisible else { return }
        targetVisible = visible
        transition += 1
        let generation = transition
        if visible {
            animationClock?.running = true
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (visible ? 0.18 : 0.22)
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
