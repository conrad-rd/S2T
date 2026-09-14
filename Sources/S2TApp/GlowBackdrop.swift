import AppKit
import S2TCore
import SwiftUI
import Glur
import GlurBackdrop

struct GlowProfile: Equatable {
    static let extent: CGFloat = max(640, ceil(ChromaPreset.bottom.fieldExtent))
    static let bodyOpacity = 0.5
    let energy: Double
    let heights: [Double]
    var topLayout: TopGlowLayout? = nil
    var inputOutline: InputOutlineBackdrop? = nil
    var bezel: BezelBackdrop? = nil
    var sweepStrength: Double = 1
    var distortion: GlowDistortion = .identity
    var active = true
    var reducedMotion = false
    var response = GlowResponseSettings()
    var chromaGeometry: ChromaAppearance.Geometry {
        if let inputOutline { return .input(inputOutline.rect, inputOutline.cornerRadius, inputOutline.cornerStyle) }
        if let topLayout { return .notch(topLayout) }
        return .bottom
    }
    var selectedStrength: Double { inputOutline?.strength ?? sweepStrength }
    var speechGain: Double { active ? GlowSpeechEnvelope.gain(energy: energy, selected: selectedStrength, settings: response) : 0 }
    var blurGain: Double { GlowSpeechEnvelope.blurGain(speechGain) * response.tuning.backgroundBlur }
    var speechExpansion: Double { GlowSpeechEnvelope.expansion(energy: energy, selected: selectedStrength, reducedMotion: reducedMotion, settings: response) }
    var leftFade: Double = 0.13
    var rightFade: Double = 0.88
    var maximumHeight: Double { heights.max() ?? 3 }

    func path(in size: CGSize, extendingBelow bottomPadding: CGFloat = 0) -> Path {
        Path { path in
            for (index, height) in heights.enumerated() {
                let point = CGPoint(x: Double(index) / Double(max(1, heights.count - 1)) * size.width,
                                    y: size.height - height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height + bottomPadding))
            path.addLine(to: CGPoint(x: 0, y: size.height + bottomPadding))
            path.closeSubpath()
        }
    }

}

final class GlowHistory {
    private let smoothAudio: Bool
    private var speechResponse = NotchSpeechResponse()
    init(smoothAudio: Bool = false) { self.smoothAudio = smoothAudio }

    private var distortion = GlowDistortion.identity
    private var previousTime: Double?

    func frame(level: Double, time: Double, reducedMotion: Bool, bands: [Double] = [], active: Bool = true) -> GlowProfile {
        if smoothAudio {
            speechResponse.update(level: level, bands: bands, time: time, reducedMotion: reducedMotion, active: active)
            return GlowProfile(energy: speechResponse.energy, heights: [3], distortion: speechResponse.distortion, active: active, reducedMotion: reducedMotion)
        }
        let energy = pow(max(0, min(1, (level - 0.06) / 0.94)), 0.7)
        let target = GlowDistortion(bands: bands, reducedMotion: reducedMotion)
        if target.isIdentity || previousTime == nil || time < previousTime! || time - previousTime! > 0.25 {
            distortion = target
        } else {
            distortion = distortion.blended(toward: target, fraction: 1 - exp(-(time - previousTime!) / 0.09))
        }
        previousTime = time
        return GlowProfile(energy: active ? energy : 0, heights: [3], distortion: active ? distortion : .identity, active: active, reducedMotion: reducedMotion)
    }
}

struct GlowBackdrop: NSViewRepresentable {
    let profile: GlowProfile
    var radiusMap: NSImage? = nil

    func makeNSView(context: Context) -> GlowBackdropBridge {
        GlowBackdropBridge()
    }

    func updateNSView(_ view: GlowBackdropBridge, context: Context) {
        view.apply(profile: profile, radiusMap: radiusMap)
    }

    static func dismantleNSView(_ view: GlowBackdropBridge, coordinator: ()) {
        view.clear()
    }

    static func mask(profile: GlowProfile, size: NSSize = NSSize(width: 384, height: GlowProfile.extent)) -> NSImage? {
        if let bezel = profile.bezel { return bezel.mask(size: size) }
        if let outline = profile.inputOutline { return outline.mask(size: size, distortion: profile.distortion, expansion: profile.speechExpansion, falloff: profile.response.tuning.falloff) }
        if let layout = profile.topLayout { return TopGlow.radiusMap(layout: layout, energy: profile.energy, size: size, strength: profile.sweepStrength, distortion: profile.distortion, expansion: profile.speechExpansion, width: profile.response.width, falloff: profile.response.tuning.falloff) }
        return ChromaAppearance.radiusMap(geometry: .bottom, size: size, distortion: profile.distortion,
            exterior: Path(CGRect(origin: .zero, size: size)), expansion: profile.speechExpansion, width: profile.response.width, falloff: profile.response.tuning.falloff)
    }


}

// SwiftUI supplies the speech frame, while the sampler stays outside its layers.
final class GlowBackdropBridge: NSView {
    private var profile: GlowProfile?
    private var radiusMap: NSImage?
    private weak var target: ProgressiveBackdropView?

    func apply(profile: GlowProfile, radiusMap: NSImage?) {
        self.profile = profile
        self.radiusMap = radiusMap
        forwardFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        forwardFrame()
    }

    private func forwardFrame() {
        guard let target = window?.contentView as? ProgressiveBackdropView, let profile else { return }
        if self.target !== target { self.target?.clear(source: self) }
        self.target = target
        target.apply(profile: profile, radiusMap: radiusMap, source: self)
    }

    func clear() {
        target?.clear(source: self)
        target = nil
        profile = nil
        radiusMap = nil
    }
}

// Glur supplies the variable-radius filter. S2T configures its sampler for other
// applications because Glur's default macOS layer only samples its own context.
final class ProgressiveBackdropView: GlurBackdropNSView {
    private var backdrop: CALayer?
    private var filterParameters: NSObject?
    private let backgroundGlow = CAGradientLayer()
    private let backgroundGlowMask = CALayer()
    private weak var hostedWindow: NSWindow?
    private var updatingBackdrop = false
    private var currentProfile: GlowProfile?
    private var currentMap: NSImage? { didSet { currentBlurMap = nil } }
    private var submittedMap: NSImage?
    private var submittedRadius: Double?
    private var submittedBounds = CGRect.zero
    private var submittedScale: CGFloat = 0
    private var submittedFilter: NSObject?
    private var currentBlurMap: NSImage?
    private weak var frameSource: GlowBackdropBridge?
    var preparesFramesAsynchronously = false
    private var preparedGeometry: ChromaAppearance.Geometry?

    func prepareGeometry(_ geometry: ChromaAppearance.Geometry) {
        guard preparedGeometry != geometry else { return }
        preparedGeometry = geometry
        var next = currentProfile ?? GlowProfile(energy: 0, heights: [3])
        next.topLayout = nil
        next.inputOutline = nil
        switch geometry {
        case .bottom: break
        case let .notch(layout): next.topLayout = layout
        case let .input(rect, radius, cornerStyle): next.inputOutline = InputOutlineBackdrop(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle)
        }
        profile = next
    }
    var isProgressiveBlurAvailable: Bool { backdrop?.filters?.first != nil }
    var isBackdropAttached: Bool { backdrop?.superlayer === layer && isProgressiveBlurAvailable }
    var profile: GlowProfile? {
        get { currentProfile }
        set {
            frameSource = nil
            currentProfile = newValue
            currentMap = nil
            updateBackdrop()
        }
    }

    init(frame frameRect: NSRect = .zero) {
        super.init(radius: 0, mask: .linear())
        backdrop = layer?.sublayers?.first { String(describing: type(of: $0)) == "CABackdropLayer" }
        filterParameters = backdrop?.filters?.first as? NSObject
        backdrop?.setValue(UUID().uuidString, forKey: "groupName")
        backgroundGlow.name = "speechBackgroundGlow"
        backgroundGlow.compositingFilter = "plusL"
        backgroundGlow.startPoint = CGPoint(x: 0, y: 0.5)
        backgroundGlow.endPoint = CGPoint(x: 1, y: 0.5)
        backgroundGlow.colors = [
            NSColor(red: 0.2, green: 0.75, blue: 1, alpha: 1).cgColor,
            NSColor(red: 0.45, green: 0.4, blue: 1, alpha: 1).cgColor,
            NSColor(red: 0.84, green: 0.4, blue: 0.76, alpha: 1).cgColor,
            NSColor(red: 1, green: 0.65, blue: 0.43, alpha: 1).cgColor
        ]
        backgroundGlow.mask = backgroundGlowMask
        frame = frameRect
        layerUsesCoreImageFilters = false
        updateBackdrop()
    }

    required init?(coder: NSCoder) { nil }

    static func hosting<Content: View>(_ content: Content) -> ProgressiveBackdropView {
        let backdrop = ProgressiveBackdropView()
        let color = NSHostingView(rootView: content)
        color.frame = backdrop.bounds
        color.autoresizingMask = [.width, .height]
        backdrop.addSubview(color)
        return backdrop
    }

    @objc private func _shouldAutoFlattenLayerTree() -> Bool { false }

    func apply(profile: GlowProfile, radiusMap: NSImage?, source: GlowBackdropBridge? = nil) {
        if preparesFramesAsynchronously, let preparedGeometry, profile.chromaGeometry != preparedGeometry { return }
        frameSource = source
        let wasSilent = currentProfile?.energy == 0
        let sameOutline = profile.inputOutline != nil && currentProfile?.inputOutline == profile.inputOutline && currentProfile?.distortion == profile.distortion && currentProfile?.speechExpansion == profile.speechExpansion
        let sameBezel = profile.bezel != nil && currentProfile?.bezel == profile.bezel
        let sameProfile = currentProfile == profile
        currentProfile = profile
        if !sameProfile && !sameOutline && !sameBezel && !(preparesFramesAsynchronously && !profile.active) {
            if profile.bezel == nil || !wasSilent || profile.energy != 0 || radiusMap != nil { currentMap = radiusMap }
        }
        if let radiusMap, currentMap !== radiusMap { currentMap = radiusMap }
        updateBackdrop()
    }

    func clear(source: GlowBackdropBridge) {
        guard frameSource === source else { return }
        profile = nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateBackdrop()
    }

    override func layout() {
        super.layout()
        updateBackdrop()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackdrop()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hostedWindow = nil
        updateBackdrop()
    }

    private func updateBackdrop() {
        guard !updatingBackdrop, let layer, let backdrop else { return }
        updatingBackdrop = true
        defer { updatingBackdrop = false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if layer.sublayers?.first !== backdrop { layer.insertSublayer(backdrop, at: 0) }
        if backgroundGlow.superlayer !== layer { layer.insertSublayer(backgroundGlow, above: backdrop) }
        for child in subviews.compactMap(\.layer) where child.superlayer !== layer {
            layer.addSublayer(child)
        }
        for (key, value) in [("windowServerAware", true), ("allowsGroupBlending", false),
                             ("allowsInPlaceFiltering", false), ("allowsSubstituteColor", false)] {
            let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
            guard backdrop.responds(to: NSSelectorFromString(setter)) else {
                backdrop.isHidden = true
                backgroundGlow.isHidden = true
                return
            }
            backdrop.setValue(value, forKey: key)
        }
        backdrop.frame = bounds
        backgroundGlow.frame = bounds
        backgroundGlowMask.frame = backgroundGlow.bounds
        backdrop.contentsScale = window?.backingScaleFactor ?? 2
        backdrop.setValue(backdrop.contentsScale, forKey: "scale")
        if let window, hostedWindow !== window || !BackdropWindowHosting.isEnabled(in: window) {
            if BackdropWindowHosting.configure(window) { hostedWindow = window }
        }
        if !preparesFramesAsynchronously, currentMap?.size != bounds.size, let profile, bounds.width > 0, bounds.height > 0 {
            currentMap = GlowBackdrop.mask(profile: profile, size: bounds.size)
        }
        guard let profile, let image = currentMap, image.size == bounds.size,
              let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            backdrop.isHidden = true
            backgroundGlow.isHidden = true
            return
        }
        backgroundGlow.locations = [profile.leftFade, 0.38 + profile.leftFade - 0.13,
                                    0.66 + profile.leftFade - 0.13, profile.rightFade].map { NSNumber(value: $0) }
        backgroundGlowMask.contents = mask
        backgroundGlow.opacity = Float(0.45 * profile.energy * GlowProfile.bodyOpacity)
        backgroundGlow.isHidden = true
        if currentBlurMap == nil { currentBlurMap = image }
        guard let blurMask = currentBlurMap?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            backdrop.isHidden = true
            return
        }
        let radius = profile.bezel.map { _ in Double(BezelBackdrop.radius) }
            ?? profile.chromaGeometry.maximumBlurRadius
        // Keep the sharp original from overwhelming the bezel's variable-radius result.
        backdrop.opacity = profile.bezel == nil ? 1 : BezelBackdrop.opacity
        let gain = profile.bezel == nil ? profile.blurGain : min(1, profile.energy)
        let effectiveRadius = radius * gain
        if submittedMap === image, submittedRadius == effectiveRadius, submittedBounds == bounds,
           submittedScale == backdrop.contentsScale,
           let submittedFilter, backdrop.filters?.first as? NSObject === submittedFilter {
            backdrop.isHidden = gain == 0
            return
        }
        update(radius: effectiveRadius, mask: .image(blurMask), layoutDirection: .leftToRight)
        // CAFilter mutations do not invalidate the layer's submitted render value.
        // Glur owns the mutable parameters; publish an immutable copy each frame.
        if let filterParameters {
            let copy = filterParameters.copy() as? NSObject
            submittedFilter = copy
            backdrop.filters = copy.map { [$0] }
        }
        submittedMap = image
        submittedRadius = effectiveRadius
        submittedBounds = bounds
        submittedScale = backdrop.contentsScale
        backdrop.isHidden = gain == 0
    }
}

// A window must publish its live layer tree to WindowServer to sample other apps.
// This configures only S2T's transparent overlay windows, never another app's window.
enum BackdropWindowHosting {
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        configure(panel)
        return panel
    }

    private static func isSupported(_ window: NSWindow) -> Bool {
        window.responds(to: NSSelectorFromString("setCanHostLayersInWindowServer:"))
            && window.responds(to: NSSelectorFromString("canHostLayersInWindowServer"))
            && window.responds(to: NSSelectorFromString("_setShouldAutoFlattenLayerTree:"))
            && window.responds(to: NSSelectorFromString("_shouldAutoFlattenLayerTree"))
    }

    @discardableResult static func configure(_ window: NSWindow) -> Bool {
        guard isSupported(window) else { return false }
        window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
        if window.value(forKey: "canHostLayersInWindowServer") as? Bool != true {
            window.setValue(true, forKey: "canHostLayersInWindowServer")
        }
        window.isOpaque = false
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        return isEnabled(in: window)
    }

    static func isEnabled(in window: NSWindow) -> Bool {
        guard isSupported(window) else { return false }
        return window.value(forKey: "canHostLayersInWindowServer") as? Bool == true
            && window.value(forKey: "shouldAutoFlattenLayerTree") as? Bool == false
            && !window.isOpaque
    }
}
