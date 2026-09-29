import AppKit
import SwiftUI
import S2TCore

struct InputProcessingBackdrop: Equatable {
    static let radius = 1.25
    var contour: InputContour
    var time = 0.0

    func mask(size: CGSize) -> NSImage? {
        WithinInputProcessing.radiusMap(size: size, time: time, contour: contour)
    }
}

enum WithinInputProcessing {
    static func isActive(_ phase: DictationPhase) -> Bool { phase == .transcribing || phase == .processing }

    static func accepts(_ target: InputOutlineTarget?) -> Bool { target?.kind == .input }

    static let cycleDuration = ReferenceLoadingField.paletteDuration
    static let haloPadding: CGFloat = 24

    static func loadingImage(size: CGSize, time: Double, gradient: GlowGradient, contour: InputContour? = nil,
                             surface: ProcessingGlassRefraction.Surface = .messageBar) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let grid = ProcessingDiffusion.Grid(size: size)
        let frame = ReferenceLoadingField.Frame(time: time, gradient: gradient)
        let rows = (0..<grid.paddedHeight).map { y in
            frame.row(heightFraction: grid.y(y))
        }
        let columns = (0..<grid.paddedWidth).map { ReferenceLoadingField.Row.across(widthFraction: grid.x($0)) }
        return fieldImage(grid: grid, contour: contour, rim: frame.rim, surface: surface) { x, y in
            rows[y].sample(opening: Float(columns[x] * rows[y].shoulder))
        }
    }

    static func radiusMap(size: CGSize, time: Double, contour: InputContour) -> NSImage? {
        let fieldSize = contour.bounds.size
        guard fieldSize.width > 0, fieldSize.height > 0 else { return nil }
        let grid = ProcessingDiffusion.Grid(size: fieldSize)
        let frame = ReferenceLoadingField.Frame(time: time, gradient: .init())
        let rows = (0..<grid.paddedHeight).map { frame.row(heightFraction: grid.y($0)) }
        let columns = (0..<grid.paddedWidth).map { ReferenceLoadingField.Row.across(widthFraction: grid.x($0)) }
        let local = contour.offsetBy(dx: -contour.bounds.minX, dy: -contour.bounds.minY)
        guard let image = fieldImage(grid: grid, contour: local, rim: nil,
                                    sample: { x, y in SIMD4(repeating: 0.08 + 0.32 * Float(columns[x] * rows[y].shoulder)) }),
              let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return ContourMask.render(size: size) { context in
            context.addPath(contour.path.cgPath)
            context.clip()
            context.translateBy(x: contour.bounds.minX, y: contour.bounds.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(pixels, in: CGRect(origin: .zero, size: fieldSize))
        }
    }

    private static func fieldImage(grid: ProcessingDiffusion.Grid, contour: InputContour?, rim: SIMD3<Float>?,
                                   surface: ProcessingGlassRefraction.Surface = .indicator,
                                   sample: (Int, Int) -> SIMD4<Float>) -> NSImage? {
        let width = grid.width, height = grid.height, size = grid.size
        var source = [Float](repeating: 0, count: grid.paddedWidth * grid.paddedHeight * 4)
        for y in 0..<grid.paddedHeight { for x in 0..<grid.paddedWidth {
            let offset = (y * grid.paddedWidth + x) * 4
            let value = sample(x, y)
            for channel in 0..<4 { source[offset + channel] = value[channel] }
        } }
        var pixels = ProcessingDiffusion.apply(source, grid: grid)
        if let contour {
            pixels = ProcessingGlassRefraction.apply(pixels, width: width, height: height, size: size, contour: contour,
                rim: rim, surface: surface)
        } else if surface == .messageBar {
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let visibility = ProcessingGlassRefraction.messageBarVisibility(alpha: pixels[offset + 3])
                for channel in 0..<4 { pixels[offset + channel] *= visibility }
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
                bytesPerRow: width * 16, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.floatComponents).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    static func draw(context: inout GraphicsContext, contour: InputContour, time: Double,
                     reducedMotion: Bool, gradient: GlowGradient = .init(), preparedImage: NSImage? = nil) {
        let time = reducedMotion ? 0.3 : time
        context.drawLayer { halo in
            halo.addFilter(.blur(radius: 7))
            halo.stroke(contour.path, with: lowerAccent(boundary: contour.path, time: time,
                gradient: gradient, opacity: 0.10), lineWidth: 5)
        }
        let size = contour.bounds.size
        let localContour = contour.offsetBy(dx: -contour.bounds.minX, dy: -contour.bounds.minY)
        guard let image = preparedImage ?? loadingImage(size: size, time: time, gradient: gradient, contour: localContour) else { return }
        let rect = CGRect(origin: .zero, size: size)
        let source = Image(nsImage: image).interpolation(.high)
        context.drawLayer { interior in
            interior.clip(to: contour.path)
            interior.translateBy(x: contour.bounds.minX, y: contour.bounds.minY)
            interior.draw(source, in: rect)
        }
        drawBorder(context: &context, boundary: contour.path, size: size, time: time, gradient: gradient)
    }

    static func drawBorder(context: inout GraphicsContext, boundary: Path, size: CGSize,
                           time: Double, gradient: GlowGradient) {
        context.drawLayer { rim in
            rim.addFilter(.blur(radius: 1.2))
            rim.stroke(boundary, with: .color(.white.opacity(0.06)), lineWidth: 0.8)
            rim.stroke(boundary, with: lowerAccent(boundary: boundary, time: time,
                gradient: gradient, opacity: 0.20), lineWidth: 1.2)
        }
    }

    private static func lowerAccent(boundary: Path, time: Double, gradient: GlowGradient,
                                    opacity: Double) -> GraphicsContext.Shading {
        let rgb = ReferenceLoadingField.Frame(time: time, gradient: gradient).paletteColor(at: 0)
        let color = Color(red: rgb.x, green: rgb.y, blue: rgb.z)
        let pulse = 1 - 0.25 * cos(time * 2 * .pi / cycleDuration)
        let opacity = opacity * pulse
        let bounds = boundary.boundingRect
        return .linearGradient(Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.55),
            .init(color: color.opacity(opacity * 0.3), location: 0.8),
            .init(color: color.opacity(opacity), location: 1)
        ]), startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
            endPoint: CGPoint(x: bounds.midX, y: bounds.maxY))
    }

}

final class InputProcessingPalette: ObservableObject {
    @Published var gradient = GlowGradient()
}

struct InputProcessingGlow: View {
    @ObservedObject var palette: InputProcessingPalette
    @ObservedObject var animationClock: GlowAnimationClock
    @ObservedObject var layout: InputOutlineLayout
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animationClock.running || reducedMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Group {
                let profile = Self.profile(contour: layout.contour, time: time,
                    reducedMotion: reducedMotion, gradient: palette.gradient)
                PreparedChromaGlow(request: ChromaFrameRequest(geometry: profile.chromaGeometry,
                    size: layout.renderSize, profile: profile, brightness: 1, backdrop: !reducedTransparency),
                    renderer: layout.renderer, submitRequest: { request in
                        if animationClock.running { layout.submitProcessingAnimation(request) }
                    })
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func profile(contour: InputContour, time: Double = 0, reducedMotion: Bool = false,
                        gradient: GlowGradient = .init()) -> GlowProfile {
        var profile = GlowProfile(energy: 1, heights: [])
        profile.inputOutline = InputOutlineBackdrop(contour: contour, withinInput: true)
        profile.processingInput = InputProcessingBackdrop(contour: contour,
            time: reducedMotion ? 0.3 : time.truncatingRemainder(dividingBy: WithinInputProcessing.cycleDuration))
        profile.response.tuning.gradients[GlowAppearance.withinInput.rawValue] = gradient
        profile.reducedMotion = reducedMotion
        return profile
    }

}

@MainActor final class InputProcessingController {
    private(set) var panel: NSPanel?
    private var visibility: OverlayVisibility?
    private let clock = GlowAnimationClock()
    private let layout: InputOutlineLayout
    private let palette = InputProcessingPalette()

    init(renderer: ChromaFrameRenderer? = nil) {
        layout = InputOutlineLayout(renderer: renderer)
        clock.running = false
    }

    @discardableResult func prepare(target: InputOutlineTarget) -> NSPanel? {
        guard WithinInputProcessing.accepts(target) else { hide(); return nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let padding = WithinInputProcessing.haloPadding
        let frame = target.frame.insetBy(dx: -padding, dy: -padding)
        let contour = target.contour.offsetBy(dx: padding, dy: padding)
        layout.renderSize = frame.size
        layout.renderer.prepareGeometry(.withinInput(contour), size: frame.size)
        let changed = layout.contour != contour
        if changed { layout.contour = contour }
        if panel == nil {
            let panel = BackdropWindowHosting.makePanel()
            panel.setFrame(frame, display: false)
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let root = ProgressiveBackdropView.hosting(InputProcessingGlow(palette: palette, animationClock: clock, layout: layout))
            root.preparesFramesAsynchronously = true
            root.frame = CGRect(origin: .zero, size: frame.size)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                root.profile = InputProcessingGlow.profile(contour: contour, time: Date().timeIntervalSinceReferenceDate,
                    reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
            panel.contentView = root
            self.panel = panel
            visibility = OverlayVisibility(panel: panel, animationClock: clock)
        }
        let panel = panel!
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        if changed, let root = panel.contentView as? ProgressiveBackdropView {
            root.profile = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                ? nil : InputProcessingGlow.profile(contour: contour, time: Date().timeIntervalSinceReferenceDate,
                    reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        (panel.contentView as? ProgressiveBackdropView)?.prepareGeometry(.withinInput(contour))
        if changed {
            layout.lastGeometrySubmission = CACurrentMediaTime()
            let profile = InputProcessingGlow.profile(contour: contour, time: Date().timeIntervalSinceReferenceDate,
                reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, gradient: palette.gradient)
            layout.renderer.submit(ChromaFrameRequest(geometry: profile.chromaGeometry, size: frame.size,
                profile: profile, brightness: 1, backdrop: !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        }
        return panel
    }

    func show(target: InputOutlineTarget, gradient: GlowGradient = .init()) {
        if palette.gradient != gradient { palette.gradient = gradient }
        guard prepare(target: target) != nil else { return }
        visibility?.setVisible(true)
    }

    var preparedFrame: ChromaFrame? { layout.renderer.frame }
    var completedFrames: Int { layout.renderer.completedFrames }
    func hide() { visibility?.setVisible(false) }
}
