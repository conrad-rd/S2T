import AppKit
import CoreImage
import SwiftUI
import S2TCore

@MainActor final class AppearancePreviewActivity: ObservableObject {
    @Published var mode: GlowAppearance {
        didSet { if mode != oldValue { renderer.cancel() } }
    }
    @Published var running = false
    @Published var phase = 0 {
        didSet { if phase != oldValue { renderer.cancel() } }
    }
    @Published var sampleText = "S2T is the best app for transcription on Mac"
    /// Height of the native toolbar over the full-height preview.
    @Published var topInset: CGFloat = 52
    var onClassicPlacement: ((NSView, CGRect, BezelSide?) -> Void)?
    let renderer = ChromaFrameRenderer()
    init(mode: GlowAppearance = .bottom) { self.mode = mode }
    func stop() { running = false; renderer.cancel() }
}

enum AppearancePreviewScene {
    private static let wallpaperCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 8
        return cache
    }()
    private static func loadWallpaper(_ name: String) -> NSImage? {
        if let image = wallpaperCache.object(forKey: name as NSString) { return image }
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Appearance/\(name).png")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Appearance/\(name).png")
        // The sidebar and preview compose the same original assets. Reuse those
        // images and only consult source artwork when the bundle lacks an asset.
        for url in [bundled, source].compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                wallpaperCache.setObject(image, forKey: name as NSString)
                return image
            }
        }
        return nil
    }
    static let wallpaper = loadWallpaper("SequoiaSunrise")
    static let bezelWallpaper = loadWallpaper("Bevel_Mac")
    static let bezelDisplay = CGRect(x: 66, y: 120, width: 837, height: 1095)
    static let inputPaddingPixels = 384
    static let inputPadding = CGFloat(inputPaddingPixels) * 969 / 1120
    static let inputBackgroundColor = NSColor(srgbRed: 33 / 255, green: 33 / 255, blue: 33 / 255, alpha: 1)
    static let inputComposerColor = NSColor(srgbRed: 48 / 255, green: 48 / 255, blue: 48 / 255, alpha: 1)
    static let inputWallpaper: NSImage? = {
        let size = CGSize(width: 1120, height: 1404)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 1404,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        let flip = AffineTransform(translationByX: 0, byY: size.height)
        var transform = flip
        transform.scale(x: 1, y: -1)
        (transform as NSAffineTransform).concat()
        let bounds = CGRect(origin: .zero, size: size)
        inputBackgroundColor.setFill()
        bounds.fill()
        inputComposerColor.setFill()
        context.cgContext.saveGState()
        context.cgContext.scaleBy(x: 1120 / 969, y: 1120 / 969)
        context.cgContext.addPath(inputContour.path.cgPath)
        context.cgContext.fillPath()
        context.cgContext.restoreGState()
        let ink = NSColor(white: 0.93, alpha: 1)
        func symbol(_ name: String, _ rect: CGRect, color: NSColor = ink) {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
            let tinted = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
            tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let footerY = input.maxY * 1120 / 969 - 59
        symbol("plus", CGRect(x: 239, y: footerY, width: 25, height: 25))
        ("6 Pro" as NSString).draw(at: CGPoint(x: 702, y: footerY + 3), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: ink])
        symbol("chevron.down", CGRect(x: 761, y: footerY + 8, width: 12, height: 9))
        symbol("mic", CGRect(x: 800, y: footerY - 2, width: 21, height: 28))
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: 844, y: footerY - 8, width: 40, height: 40)).fill()
        symbol("waveform", CGRect(x: 854, y: footerY + 2, width: 20, height: 20), color: inputBackgroundColor)
        guard let pixels = bitmap.cgImage else { return nil }
        return NSImage(cgImage: pixels, size: size)
    }()
    static let notchWallpaper = AppearanceDesignArtwork.compose(notch: true, load: loadWallpaper)
    static let bottomWallpaper = AppearanceDesignArtwork.compose(notch: false, load: loadWallpaper)
    static let sidebarLeadingWidth: CGFloat = 180

    static func sidebarWallpaper(for mode: GlowAppearance) -> NSImage? {
        if mode == .bottom || mode == .aroundNotch {
            return AppearanceDesignArtwork.compose(notch: mode == .aroundNotch,
                leadingWidth: sidebarLeadingWidth, load: loadWallpaper)
        }
        let scene = size(for: mode)
        let image = mode.followsInput ? inputWallpaper : bezelWallpaper
        return NSImage(size: CGSize(width: scene.width + sidebarLeadingWidth, height: scene.height), flipped: true) { bounds in
            (mode.followsInput ? inputBackgroundColor : NSColor.white).setFill()
            bounds.fill()
            image?.draw(in: CGRect(x: sidebarLeadingWidth, y: 0, width: scene.width, height: scene.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return true
        }
    }
    static let bottomDisplayHeight = AppearanceDesignArtwork.bottomEdge
    static func renderSize(for mode: GlowAppearance) -> CGSize {
        if mode.followsInput { return CGSize(width: 969 + 2 * inputPadding, height: size(for: mode).height) }
        if mode == .bottom { return CGSize(width: AppearanceDesignArtwork.size.width, height: bottomDisplayHeight) }
        if mode == .aroundNotch { return CGSize(width: notch.frame.width, height: AppearanceDesignArtwork.size.height - AppearanceDesignArtwork.notchTop) }
        return size(for: mode)
    }
    static func renderOrigin(for mode: GlowAppearance) -> CGPoint {
        if mode.followsInput { return CGPoint(x: -inputPadding, y: 0) }
        return mode == .aroundNotch ? CGPoint(x: notch.frame.minX, y: AppearanceDesignArtwork.notchTop) : .zero
    }
    static let size = CGSize(width: 800, height: 800 * 1215.0 / 969)
    static let input = CGRect(x: 211 * 969.0 / 1120, y: 230 * 969.0 / 1120,
        width: 698 * 969.0 / 1120, height: 240 * 969.0 / 1120)
    static func inputGreeting(fullName: String, accountName: String) -> String {
        let name = fullName.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            ?? accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "How can I help you?" : "How can I help you, \(name)?"
    }
    static let sampleField = CGRect(x: 205, y: 225, width: 550, height: 30)
    static let inputRadius: CGFloat = 40
    static let inputContour = InputContour(rect: input, radius: inputRadius, style: .circular)
    static let notch = TopGlowLayout(display: GlowDisplay(frame: CGRect(origin: .zero, size: AppearanceDesignArtwork.size),
        safeTop: AppearanceDesignArtwork.notchDepth,
        topLeft: CGRect(x: 0, y: AppearanceDesignArtwork.size.height - AppearanceDesignArtwork.notchDepth,
            width: AppearanceDesignArtwork.notchLeft, height: AppearanceDesignArtwork.notchDepth),
        topRight: CGRect(x: AppearanceDesignArtwork.notchLeft + AppearanceDesignArtwork.notchWidth,
            y: AppearanceDesignArtwork.size.height - AppearanceDesignArtwork.notchDepth,
            width: AppearanceDesignArtwork.size.width - AppearanceDesignArtwork.notchLeft - AppearanceDesignArtwork.notchWidth,
            height: AppearanceDesignArtwork.notchDepth)))
    static func size(for mode: GlowAppearance) -> CGSize {
        if mode.followsInput { return CGSize(width: 969, height: 1404 * 969.0 / 1120) }
        return mode == .bottom || mode == .aroundNotch ? AppearanceDesignArtwork.size : CGSize(width: 969, height: 1215)
    }

    static func scale(for mode: GlowAppearance, viewport: CGSize) -> CGFloat {
        let scene = size(for: mode)
        return max(viewport.width / scene.width, viewport.height / scene.height)
    }

    /// Distance from the bottom of the pane to the top of the settings panel.
    static let controlsReserve: CGFloat = 364
    static let subjectMargin: CGFloat = 24
    /// Scene rows (greeting to the composer's lower edge and its glow) that must stay
    /// visible between the toolbar and the settings panel.
    static func subject(for mode: GlowAppearance) -> ClosedRange<CGFloat>? {
        mode.followsInput ? 115...(input.maxY + 28) : nil
    }

    /// Scale and top-left scene origin in top-down viewport points. Input previews sit
    /// on a uniform background, so they shrink if needed and center in the free band.
    static func placement(for mode: GlowAppearance, viewport: CGSize, topInset: CGFloat) -> (scale: CGFloat, origin: CGPoint) {
        let scene = size(for: mode)
        var scale = scale(for: mode, viewport: viewport)
        var y: CGFloat = 0
        if let subject = subject(for: mode) {
            let top = topInset + subjectMargin
            let bottom = viewport.height - controlsReserve - subjectMargin
            let height = subject.upperBound - subject.lowerBound
            scale = max(0.1, min(scale, (bottom - top) / height))
            y = (top + bottom) / 2 - (subject.lowerBound + subject.upperBound) / 2 * scale
        } else if mode == .bottom {
            // The glow sits on the pictured display's lower edge. In wide panes, lift the
            // scene so that edge stays above the settings panel; only wallpaper is cropped.
            let limit = viewport.height - controlsReserve - subjectMargin
            y = max(viewport.height - scene.height * scale, min(0, limit - bottomDisplayHeight * scale))
        }
        return (scale, CGPoint(x: (viewport.width - scene.width * scale) / 2, y: y))
    }

    /// Whether the preview is light where it runs under the window title.
    static func hasLightTop(_ mode: GlowAppearance) -> Bool { !mode.followsInput && mode != .bottom }

    /// The native toolbar height above a full-height view.
    @MainActor static func topInset(of view: NSView) -> CGFloat {
        guard let window = view.window, let content = window.contentView else { return 0 }
        return max(0, content.bounds.height - window.contentLayoutRect.maxY)
    }

    static func bezelPreviewDisplay(in viewport: CGSize) -> CGRect {
        let scale = scale(for: .bezel, viewport: viewport)
        let availableBottom = viewport.height / scale
        return CGRect(x: bezelDisplay.minX, y: bezelDisplay.minY, width: bezelDisplay.width,
                      height: max(120, min(bezelDisplay.height, availableBottom - bezelDisplay.minY)))
    }

    static func cycleTime(phase: Int, time: Double, reducedMotion: Bool) -> Double? {
        reducedMotion ? nil : time
    }

    static func geometry(_ mode: GlowAppearance) -> ChromaAppearance.Geometry {
        switch mode {
        case .aroundNotch: return .notch(notch)
        case .withinInput: return .withinInput(inputContour.offsetBy(dx: inputPadding, dy: 0))
        case .aroundInput: return .input(inputContour.offsetBy(dx: inputPadding, dy: 0))
        default: return .bottom
        }
    }

    @MainActor static func request(state: AppState, mode: GlowAppearance? = nil, phase: Int, time: Double, reducedMotion: Bool, backdrop: Bool) -> ChromaFrameRequest {
        let mode = mode ?? state.glowAppearance
        let energy = phase == 2 ? 0 : phase == 0 || reducedMotion ? 0.65 : 0.65 + 0.08 * sin(time * 2)
        let bands = (0..<7).map { index in max(0.05, 0.55 + 0.4 * sin(time * 1.3 + Double(index))) }
        var response = state.glowResponseSettings
        if mode == .withinInput { response.tuning = response.tuning.forInput(size: .zero, preview: true) }
        if phase == 0 { response.minimum = 1; response.maximum = 1 }
        var profile = GlowProfile(energy: energy, heights: [3], sweepStrength: state.glowStrength,
            distortion: phase == 1 ? GlowDistortion(bands: bands, reducedMotion: reducedMotion) : .identity,
            active: phase != 2, reducedMotion: reducedMotion, response: response)
        let geometry = geometry(mode)
        switch geometry {
        case .bottom: break
        case let .windowBottom(layout): profile.windowBottom = layout
        case let .notch(layout): profile.topLayout = layout
        case let .withinInput(contour): profile.inputOutline = .init(contour: contour, strength: state.glowStrength, withinInput: true)
        case let .input(contour): profile.inputOutline = .init(contour: contour, strength: state.glowStrength)
        }
        if case let .withinInput(contour) = geometry, phase == 2 {
            profile.processingInput = InputProcessingGlow.profile(contour: contour, time: time, reducedMotion: reducedMotion).processingInput
            profile.active = true
        }
        return .init(geometry: geometry, size: renderSize(for: mode), profile: profile, brightness: profile.speechGain, backdrop: backdrop)
    }

    private static let inputBackground = makeBackground(.aroundInput)
    private static let bottomBackground = makeBackground(.bottom)
    private static let notchBackground = makeBackground(.aroundNotch)
    private static let classicBackground = makeBackground(.bezel)

    private static func makeBackground(_ mode: GlowAppearance) -> NSImage {
        let size = size(for: mode)
        if mode.followsInput, let pixels = inputWallpaper?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let source = CIImage(cgImage: pixels)
            let extent = source.extent.insetBy(dx: -CGFloat(inputPaddingPixels), dy: 0)
            let extended = source.clampedToExtent().cropped(to: extent)
            if let padded = CIContext(options: [.cacheIntermediates: false]).createCGImage(extended, from: extent) {
                return NSImage(cgImage: padded, size: renderSize(for: mode))
            }
        }
        guard let pixels = (mode == .bottom ? bottomWallpaper : mode == .aroundNotch ? notchWallpaper : bezelWallpaper)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return NSImage(size: size) }
        return NSImage(cgImage: pixels, size: size)
    }

    static let bottomDisplayBackground: NSImage = {
        let source = background(.bottom).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cropped = source.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(source.width), height: bottomDisplayHeight * CGFloat(source.height) / AppearanceDesignArtwork.size.height))!
        return NSImage(cgImage: cropped, size: renderSize(for: .bottom))
    }()

    static let notchDisplayBackground: NSImage = {
        let source = background(.aroundNotch).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let rect = CGRect(origin: renderOrigin(for: .aroundNotch), size: renderSize(for: .aroundNotch))
        let scale = CGFloat(source.width) / AppearanceDesignArtwork.size.width
        return NSImage(cgImage: source.cropping(to: rect.applying(CGAffineTransform(scaleX: scale, y: scale)))!, size: rect.size)
    }()

    static func background(_ mode: GlowAppearance) -> NSImage {
        if mode.followsInput { return inputBackground }
        if mode == .bottom { return bottomBackground }
        if mode == .aroundNotch { return notchBackground }
        return classicBackground
    }
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
        previewContent
            .ignoresSafeArea()
            .accessibilityLabel("Live appearance preview with a sample background")
    }

    @ViewBuilder private var previewContent: some View {
        if activity.mode.isClassic {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !activity.running)) { timeline in
                GeometryReader { viewport in
                    let scene = AppearancePreviewScene.size(for: .bezel)
                    let scale = AppearancePreviewScene.scale(for: .bezel, viewport: viewport.size)
                    let display = AppearancePreviewScene.bezelPreviewDisplay(in: viewport.size)
                    ZStack(alignment: .topLeading) {
                        AppearancePreviewBackdrop(image: AppearancePreviewScene.background(.bezel), frame: nil)
                            .frame(width: scene.width, height: scene.height).allowsHitTesting(false)
                        ClassicPreview(state: state, phase: activity.phase, time: timeline.date.timeIntervalSinceReferenceDate,
                            onPlacement: activity.onClassicPlacement,
                            reducedMotion: reducedMotion, reducedTransparency: reducedTransparency)
                            .frame(width: display.width, height: display.height)
                            .offset(x: display.minX, y: display.minY)
                    }
                    .frame(width: scene.width, height: scene.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: (viewport.size.width - scene.width * scale) / 2)
                    .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                    .clipped()
                }
            }
            .onAppear { renderer.cancel() }
        } else { glowPreview }
    }

    private var glowPreview: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !activity.running)) { timeline in
            let time = activity.running ? timeline.date.timeIntervalSinceReferenceDate : 0
            let sceneSize = AppearancePreviewScene.size(for: activity.mode)
            let request = AppearancePreviewScene.request(state: state, mode: activity.mode, phase: activity.phase, time: time,
                reducedMotion: reducedMotion, backdrop: !reducedTransparency)
            let frame = renderer.frame.flatMap { $0.request.geometry == request.geometry ? $0 : nil }
            GeometryReader { viewport in
                let placement = AppearancePreviewScene.placement(for: activity.mode, viewport: viewport.size, topInset: activity.topInset)
                let scale = placement.scale
                let bezelDisplay = AppearancePreviewScene.bezelPreviewDisplay(in: viewport.size)
                ZStack(alignment: .topLeading) {
                    AppearancePreviewBackdrop(image: AppearancePreviewScene.background(activity.mode),
                        frame: activity.mode == .aroundNotch || activity.mode == .bottom || activity.mode == .bezel || reducedTransparency || (activity.phase == 2 && activity.mode != .withinInput) ? nil : frame)
                        .frame(width: activity.mode.followsInput ? request.size.width : sceneSize.width,
                               height: sceneSize.height)
                        .offset(x: activity.mode.followsInput ? -AppearancePreviewScene.inputPadding : 0)
                        .allowsHitTesting(false)
                    if activity.mode == .bottom || activity.mode == .aroundNotch {
                        AppearancePreviewBackdrop(image: activity.mode == .bottom ? AppearancePreviewScene.bottomDisplayBackground : AppearancePreviewScene.notchDisplayBackground,
                            frame: reducedTransparency || (activity.phase == 2 && activity.mode != .withinInput) ? nil : frame)
                            .frame(width: request.size.width, height: request.size.height)
                            .clipped().offset(x: AppearancePreviewScene.renderOrigin(for: activity.mode).x, y: AppearancePreviewScene.renderOrigin(for: activity.mode).y).allowsHitTesting(false)
                    }
                    if activity.mode.followsInput {
                        Text(AppearancePreviewScene.inputGreeting(
                            fullName: state.isPreview ? "Alex Example" : NSFullUserName(),
                            accountName: state.isPreview ? "alex" : NSUserName()))
                            .font(.system(size: 24))
                            .foregroundStyle(Color(white: 0.93))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 650, height: 50)
                            .background(Color(nsColor: AppearancePreviewScene.inputBackgroundColor))
                            .position(x: 484.5, y: 145)
                            .allowsHitTesting(false)
                    }
                    if activity.mode.followsInput {
                        let field = AppearancePreviewScene.sampleField
                        let origin = AppearancePreviewScene.renderOrigin(for: activity.mode)
                        let processing = request.profile.processingInput.map {
                            InputProcessingBackdrop(contour: $0.contour.offsetBy(dx: origin.x - field.minX, dy: origin.y - field.minY), time: $0.time)
                        }
                        AppearanceSampleField(text: $activity.sampleText, processing: reducedTransparency ? nil : processing)
                            .frame(width: field.width, height: field.height)
                            .background(Color(nsColor: AppearancePreviewScene.inputComposerColor))
                            .environment(\.colorScheme, .dark)
                            .position(x: field.midX, y: field.midY)
                    }
                    if activity.mode == .bezel {
                        AppearanceBezelPreview(side: state.bezelSide, position: state.bezelVerticalPosition, phase: activity.phase, time: time, reducedMotion: reducedMotion,
                            onMove: { side, position in state.bezelSide = side; state.bezelVerticalPosition = position })
                            .frame(width: bezelDisplay.width, height: bezelDisplay.height)
                            .offset(x: bezelDisplay.minX, y: bezelDisplay.minY)
                    } else if activity.phase == 2 {
                        AppearanceProcessingPreview(geometry: request.geometry, time: time, reducedMotion: reducedMotion, reducedTransparency: reducedTransparency, strength: state.glowStrength, gradient: state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init())
                            .allowsHitTesting(false)
                            .frame(width: request.size.width, height: request.size.height).clipped()
                            .offset(x: AppearancePreviewScene.renderOrigin(for: activity.mode).x, y: AppearancePreviewScene.renderOrigin(for: activity.mode).y)
                    } else if let frame { ChromaFrameCanvas(frame: frame, cycleTime: AppearancePreviewScene.cycleTime(phase: activity.phase, time: time, reducedMotion: reducedMotion))
                        .frame(width: request.size.width, height: request.size.height).clipped().offset(x: AppearancePreviewScene.renderOrigin(for: activity.mode).x, y: AppearancePreviewScene.renderOrigin(for: activity.mode).y).allowsHitTesting(false) }
                }
                .frame(width: sceneSize.width, height: sceneSize.height, alignment: .topLeading)
                .coordinateSpace(name: "appearanceScene")
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: placement.origin.x, y: placement.origin.y)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
                .background(activity.mode.followsInput ? Color(nsColor: AppearancePreviewScene.inputBackgroundColor) : .clear)
                .clipped()
            }
            .onChange(of: request, initial: true) { _, request in
                if activity.running, activity.mode != .bezel { renderer.submit(request) }
            }
            .onChange(of: activity.running) { _, running in
                if running, activity.mode != .bezel { renderer.submit(request) }
                else { renderer.cancel() }
            }
            .onChange(of: activity.mode) { _, mode in if mode == .bezel { renderer.cancel() } }
        }
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
    private lazy var source: ProgressiveBackdropView = {
        let view = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: AppearancePreviewScene.size))
        view.preparesFramesAsynchronously = true
        return view
    }()
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspect
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
    var gradient: GlowGradient = .init()
    var body: some View {
        switch geometry {
        case .bottom:
            BottomGlow(level: 0, strength: strength, phase: .processing, timeOverride: time,
                reduceMotionOverride: reducedMotion, reduceTransparencyOverride: reducedTransparency, showsBackdrop: false)
        case let .windowBottom(layout):
            BottomGlow(level: 0, strength: strength, phase: .processing, timeOverride: time,
                reduceMotionOverride: reducedMotion, reduceTransparencyOverride: reducedTransparency,
                windowBottom: layout)
        case let .notch(layout):
            TopGlow(showsBackdrop: false, layout: layout, strength: strength, phase: .processing,
                levelProvider: { 0 }, timeOverride: time, reduceTransparencyOverride: reducedTransparency,
                reduceMotionOverride: reducedMotion)
        case let .withinInput(contour):
            Canvas(opaque: false, colorMode: .extendedLinear) { context, size in
                WithinInputProcessing.draw(context: &context, contour: contour, time: time,
                    reducedMotion: reducedMotion, gradient: gradient)
            }
        case let .input(contour):
            Canvas { context, size in
                InputOutlineProcessing.draw(context: &context, path: InputOutlineBackdrop(contour: contour).path,
                    size: size, time: time, reducedMotion: reducedMotion, reducedTransparency: reducedTransparency)
            }
        }
    }
}
