import AppKit
import CoreImage
import SwiftUI
import S2TCore

@MainActor final class AppearancePreviewActivity: ObservableObject {
    @Published var running = false
    @Published var phase = 0 {
        didSet { if phase != oldValue { renderer.cancel() } }
    }
    @Published var sampleText = "S2T is the best app for transcription on Mac"
    let renderer = ChromaFrameRenderer()
    func stop() { running = false; renderer.cancel() }
}

enum AppearancePreviewScene {
    private static func loadWallpaper(_ name: String) -> NSImage? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Appearance/\(name).png")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Appearance/\(name).png")
        return [bundled, source].compactMap { $0 }.compactMap { NSImage(contentsOf: $0) }.first
    }
    static let wallpaper = loadWallpaper("SequoiaSunrise")
    static let bezelWallpaper = loadWallpaper("Bevel_Mac")
    static let bezelDisplay = CGRect(x: 66, y: 120, width: 837, height: 1095)
    static let inputPaddingPixels = 384
    static let inputPadding = CGFloat(inputPaddingPixels) * 969 / 1120
    static let inputWallpaper = loadWallpaper("ChatGPT-Upscaled")
    static let notchWallpaper = loadWallpaper("Notch-Mac")
    static let bottomWallpaper = loadWallpaper("Bottom_Mac")
    // The supplied 969 × 1215 image ends its display at row 416.
    static let bottomDisplayHeight = size.height * 416 / 1215
    static func renderSize(for mode: GlowAppearance) -> CGSize {
        if mode == .aroundInput { return CGSize(width: 969 + 2 * inputPadding, height: 1215) }
        if mode == .bottom { return CGSize(width: size.width, height: bottomDisplayHeight) }
        if mode == .aroundNotch { return CGSize(width: notch.frame.width, height: 1215 - 134) }
        return size(for: mode)
    }
    static func renderOrigin(for mode: GlowAppearance) -> CGPoint {
        if mode == .aroundInput { return CGPoint(x: -inputPadding, y: 0) }
        return mode == .aroundNotch ? CGPoint(x: notch.frame.minX, y: 134) : .zero
    }
    static let size = CGSize(width: 800, height: 1008)
    static let input = CGRect(x: 69 * 969.0 / 1120, y: 230 * 1215.0 / 1404,
        width: 984 * 969.0 / 1120, height: 140 * 1215.0 / 1404)
    static let inputRadius: CGFloat = 40
    // Image coordinates: display starts at row 134, housing spans x 342...588 to row 178.
    static let notch = TopGlowLayout(display: GlowDisplay(frame: CGRect(x: 0, y: 0, width: 969, height: 1215),
        safeTop: 44, topLeft: CGRect(x: 0, y: 1171, width: 342, height: 44),
        topRight: CGRect(x: 588, y: 1171, width: 381, height: 44)))
    static func size(for mode: GlowAppearance) -> CGSize {
        mode == .bottom ? size : CGSize(width: 969, height: 1215)
    }

    static func cycleTime(phase: Int, time: Double, reducedMotion: Bool) -> Double? {
        phase == 0 || reducedMotion ? nil : time
    }

    static func geometry(_ mode: GlowAppearance) -> ChromaAppearance.Geometry {
        switch mode {
        case .aroundNotch: return .notch(notch)
        case .aroundInput: return .input(input.offsetBy(dx: inputPadding, dy: 0), inputRadius)
        default: return .bottom
        }
    }

    @MainActor static func request(state: AppState, phase: Int, time: Double, reducedMotion: Bool, backdrop: Bool) -> ChromaFrameRequest {
        let energy = phase == 2 ? 0 : phase == 0 || reducedMotion ? 0.65 : 0.65 + 0.08 * sin(time * 2)
        let bands = (0..<7).map { index in max(0.05, 0.55 + 0.4 * sin(time * 1.3 + Double(index))) }
        var profile = GlowProfile(energy: energy, heights: [3], sweepStrength: state.glowStrength,
            distortion: phase == 1 ? GlowDistortion(bands: bands, reducedMotion: reducedMotion) : .identity,
            active: phase != 2, reducedMotion: reducedMotion, response: state.glowResponseSettings)
        let geometry = geometry(state.glowAppearance)
        switch geometry {
        case .bottom: break
        case let .notch(layout): profile.topLayout = layout
        case let .input(rect, radius, cornerStyle): profile.inputOutline = .init(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle, strength: state.glowStrength)
        }
        return .init(geometry: geometry, size: renderSize(for: state.glowAppearance), profile: profile, brightness: profile.speechGain, backdrop: backdrop)
    }

    private static let backgrounds: [GlowAppearance: NSImage] = Dictionary(uniqueKeysWithValues: GlowAppearance.allCases.compactMap { mode in
        let size = size(for: mode)
        if mode == .aroundInput, let pixels = inputWallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let source = CIImage(cgImage: pixels)
            let extent = source.extent.insetBy(dx: -CGFloat(inputPaddingPixels), dy: 0)
            let extended = source.clampedToExtent().cropped(to: extent)
            guard let padded = CIContext(options: [.cacheIntermediates: false]).createCGImage(extended, from: extent) else { return nil }
            return (mode, NSImage(cgImage: padded, size: renderSize(for: mode)))
        }
        guard let image = ContourMask.render(size: size, draw: { context in
            if let image = (mode == .bottom ? bottomWallpaper : mode == .aroundNotch ? notchWallpaper : mode == .aroundInput ? inputWallpaper : bezelWallpaper)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let width = size.width, height = size.height
                context.saveGState()
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height))
                context.restoreGState()
            }
        }) else { return nil }
        return (mode, image)
    })

    static let bottomDisplayBackground: NSImage = {
        let source = background(.bottom).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cropped = source.cropping(to: CGRect(x: 0, y: 0, width: size.width, height: bottomDisplayHeight))!
        return NSImage(cgImage: cropped, size: renderSize(for: .bottom))
    }()

    static let notchDisplayBackground: NSImage = {
        let source = background(.aroundNotch).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let rect = CGRect(origin: renderOrigin(for: .aroundNotch), size: renderSize(for: .aroundNotch))
        return NSImage(cgImage: source.cropping(to: rect)!, size: rect.size)
    }()

    static func background(_ mode: GlowAppearance) -> NSImage { backgrounds[mode]! }
}

struct AppearancePreview: View {
    @ObservedObject var state: AppState
    @ObservedObject var activity: AppearancePreviewActivity
    @ObservedObject private var renderer: ChromaFrameRenderer
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency

    init(state: AppState, activity: AppearancePreviewActivity) {
        self.state = state
        self.activity = activity
        self.renderer = activity.renderer
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !activity.running)) { timeline in
            let time = activity.running ? timeline.date.timeIntervalSinceReferenceDate : 0
            let sceneSize = AppearancePreviewScene.size(for: state.glowAppearance)
            let request = AppearancePreviewScene.request(state: state, phase: activity.phase, time: time,
                reducedMotion: reducedMotion, backdrop: !reducedTransparency)
            let frame = renderer.frame.flatMap { $0.request.geometry == request.geometry ? $0 : nil }
            GeometryReader { viewport in
                ZStack(alignment: .topLeading) {
                    AppearancePreviewBackdrop(image: AppearancePreviewScene.background(state.glowAppearance),
                        frame: state.glowAppearance == .aroundNotch || state.glowAppearance == .bottom || state.glowAppearance == .bezel || reducedTransparency || activity.phase == 2 ? nil : frame)
                        .frame(width: state.glowAppearance == .aroundInput ? request.size.width : sceneSize.width,
                               height: sceneSize.height)
                        .offset(x: state.glowAppearance == .aroundInput ? -AppearancePreviewScene.inputPadding : 0)
                        .allowsHitTesting(false)
                    if state.glowAppearance == .bottom || state.glowAppearance == .aroundNotch {
                        AppearancePreviewBackdrop(image: state.glowAppearance == .bottom ? AppearancePreviewScene.bottomDisplayBackground : AppearancePreviewScene.notchDisplayBackground,
                            frame: reducedTransparency || activity.phase == 2 ? nil : frame)
                            .frame(width: request.size.width, height: request.size.height)
                            .clipped().offset(x: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).x, y: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).y).allowsHitTesting(false)
                    }
                    if state.glowAppearance == .bezel {
                        AppearanceBezelPreview(side: state.bezelSide, position: state.bezelVerticalPosition, phase: activity.phase, time: time, reducedMotion: reducedMotion,
                            onMove: { side, position in state.bezelSide = side; state.bezelVerticalPosition = position })
                            .frame(width: AppearancePreviewScene.bezelDisplay.width, height: AppearancePreviewScene.bezelDisplay.height)
                            .offset(x: AppearancePreviewScene.bezelDisplay.minX, y: AppearancePreviewScene.bezelDisplay.minY)
                    } else if activity.phase == 2 {
                        AppearanceProcessingPreview(geometry: request.geometry, time: time, reducedMotion: reducedMotion, reducedTransparency: reducedTransparency, strength: state.glowStrength)
                            .frame(width: request.size.width, height: request.size.height).clipped()
                            .offset(x: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).x, y: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).y)
                    } else if let frame { ChromaFrameCanvas(frame: frame, cycleTime: AppearancePreviewScene.cycleTime(phase: activity.phase, time: time, reducedMotion: reducedMotion))
                        .frame(width: request.size.width, height: request.size.height).clipped().offset(x: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).x, y: AppearancePreviewScene.renderOrigin(for: state.glowAppearance).y).allowsHitTesting(false) }
                    if state.glowAppearance == .aroundInput {
                        AppearanceSampleField(text: $activity.sampleText)
                            .frame(width: 750, height: 30)
                            .background(Color.white)
                            .environment(\.colorScheme, .light)
                            .position(x: 456, y: 234)
                    }
                }
                .frame(width: sceneSize.width, height: sceneSize.height, alignment: .topLeading)
                .coordinateSpace(name: "appearanceScene")
                .scaleEffect(x: viewport.size.width / sceneSize.width, y: viewport.size.height / sceneSize.height, anchor: .topLeading)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .clipped()
            }
            .onChange(of: request, initial: true) { _, request in
                if activity.running, state.glowAppearance != .bezel { renderer.submit(request) }
            }
            .onChange(of: activity.running) { _, running in
                if running, state.glowAppearance != .bezel { renderer.submit(request) }
                else { renderer.cancel() }
            }
            .onChange(of: state.glowAppearance) { _, mode in if mode == .bezel { renderer.cancel() } }
            .onDisappear { renderer.cancel() }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Live appearance preview with a sample background")
    }
}

struct AppearancePreviewBackdrop: NSViewRepresentable {
    let image: NSImage
    let frame: ChromaFrame?
    func makeNSView(context: Context) -> AppearancePreviewBackdropView { .init() }
    func updateNSView(_ view: AppearancePreviewBackdropView, context: Context) { view.update(image: image, frame: frame) }
}

final class AppearancePreviewBackdropView: NSView {
    private(set) var displayedRequest: ChromaFrameRequest?
    private let source = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: AppearancePreviewScene.size))
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        source.preparesFramesAsynchronously = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { nil }
    func update(image: NSImage, frame: ChromaFrame?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer?.contents = pixels
        layer?.contentsScale = CGFloat(pixels?.width ?? 1) / max(1, image.size.width)
        displayedRequest = frame?.request
        if let frame, let map = frame.radiusMap, frame.request.profile.active {
            source.setFrameSize(frame.request.size)
            source.apply(profile: frame.request.profile, radiusMap: map)
            layer?.filters = source.layer?.sublayers?.first?.filters
        } else { layer?.filters = nil }
    }
}

private struct AppearanceBezelPreview: NSViewRepresentable {
    let side: BezelSide
    let position: Double
    let phase: Int
    let time: Double
    let reducedMotion: Bool
    let onMove: (BezelSide, Double) -> Void
    func makeNSView(context: Context) -> BezelPreviewContainer { BezelPreviewContainer() }
    func updateNSView(_ view: BezelPreviewContainer, context: Context) {
        view.onMove = onMove
        view.synchronize(side: side, position: position, phase: phase, time: time, reducedMotion: reducedMotion)
    }
}

private struct AppearanceProcessingPreview: View {
    let geometry: ChromaAppearance.Geometry
    let time: Double
    let reducedMotion: Bool
    let reducedTransparency: Bool
    let strength: Double
    var body: some View {
        switch geometry {
        case .bottom:
            BottomGlow(level: 0, strength: strength, phase: .processing, timeOverride: time,
                reduceMotionOverride: reducedMotion, reduceTransparencyOverride: reducedTransparency, showsBackdrop: false)
        case let .notch(layout):
            TopGlow(showsBackdrop: false, layout: layout, strength: strength, phase: .processing,
                levelProvider: { 0 }, timeOverride: time, reduceTransparencyOverride: reducedTransparency,
                reduceMotionOverride: reducedMotion)
        case let .input(rect, radius, cornerStyle):
            Canvas { context, size in
                InputOutlineProcessing.draw(context: &context, path: InputOutlineBackdrop(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle).path,
                    size: size, time: time, reducedMotion: reducedMotion, reducedTransparency: reducedTransparency)
            }
        }
    }
}
