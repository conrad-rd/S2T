import AppKit
import Combine
import SwiftUI
import S2TCore

struct ChromaFrameRequest: Equatable {
    let geometry: ChromaAppearance.Geometry
    let size: CGSize
    let profile: GlowProfile
    let brightness: Double
    let backdrop: Bool

    var distortion: GlowDistortion {
        if case .notch = geometry { return NotchAura.deformation(profile.distortion) }
        return profile.distortion
    }
}

struct ChromaFrame {
    let request: ChromaFrameRequest
    let images: [NSImage]
    let radiusMap: NSImage?

    static func render(_ request: ChromaFrameRequest) -> ChromaFrame? {
        if let processing = request.profile.processingInput {
            let contour = processing.contour
            let local = contour.offsetBy(dx: -contour.bounds.minX, dy: -contour.bounds.minY)
            let gradient = request.profile.response.tuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init()
            guard let color = WithinInputProcessing.loadingImage(size: contour.bounds.size,
                time: processing.time, gradient: gradient, contour: local) else { return nil }
            let map = request.backdrop ? processing.mask(size: request.size) : nil
            guard !request.backdrop || map != nil else { return nil }
            return ChromaFrame(request: request, images: [color], radiusMap: map)
        }
        if request.brightness == 0 || request.profile.speechExpansion == 0 {
            let map = request.backdrop ? ContourMask.render(size: request.size) { _ in } : nil
            return ChromaFrame(request: request, images: [], radiusMap: map)
        }
        guard let assets = ChromaAppearance.assets(geometry: request.geometry, size: request.size, falloff: request.profile.response.tuning.falloff),
              let images = ChromaAppearance.expandedImages(assets: assets, geometry: request.geometry, size: request.size,
                expansion: request.profile.speechExpansion, edgeHeight: request.profile.response.tuning.edgeHeight, softness: request.profile.response.tuning.softness) else { return nil }
        let map = request.backdrop ? GlowBackdrop.mask(profile: request.profile, size: request.size) : nil
        guard !request.backdrop || map != nil else { return nil }
        return ChromaFrame(request: request, images: images, radiusMap: map)
    }
}

/// One render in flight per view; newer controls and meter samples replace pending work.
@MainActor final class ChromaFrameRenderer: ObservableObject {
    private static let queue = DispatchQueue(label: "com.s2t.appearance-render", qos: .userInitiated)
    private static let processingQueue = DispatchQueue(label: "com.s2t.input-processing-render", qos: .userInitiated)
    @Published private(set) var frame: ChromaFrame?
    private let render: (ChromaFrameRequest) -> ChromaFrame?
    init(render: @escaping (ChromaFrameRequest) -> ChromaFrame? = ChromaFrame.render) { self.render = render }
    private var latest: ChromaFrameRequest?
    private var rendering = false
    private var generation = 0
    private var preparedGeometry: (ChromaAppearance.Geometry, CGSize)?
    private(set) var completedFrames = 0

    func prepareGeometry(_ geometry: ChromaAppearance.Geometry, size: CGSize) {
        preparedGeometry = (geometry, size)
        if let latest, latest.geometry != geometry || latest.size != size { self.latest = nil }
    }

    func submit(_ request: ChromaFrameRequest) {
        guard request.size.width > 0, request.size.height > 0 else { return }
        if let preparedGeometry, request.geometry != preparedGeometry.0 || request.size != preparedGeometry.1 { return }
        latest = request
        startIfNeeded()
    }

    func cancel() {
        generation += 1
        latest = nil
        frame = nil
    }

    private func startIfNeeded() {
        guard !rendering, let request = latest, frame?.request != request else { return }
        rendering = true
        let generation = generation
        let render = render
        let queue = request.profile.processingInput == nil ? Self.queue : Self.processingQueue
        queue.async { [weak self] in
            let result = autoreleasepool { render(request) }
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rendering = false
                    if self.generation == generation, let latest = self.latest,
                       latest.geometry == request.geometry, latest.size == request.size,
                       latest.backdrop == request.backdrop, let result {
                        self.completedFrames += 1
                        self.frame = result
                    }
                    // A failed unchanged request waits for new input instead of spinning.
                    if self.latest != request || self.generation != generation { self.startIfNeeded() }
                }
            }
        }
    }
}

struct PreparedChromaGlow: View {
    let request: ChromaFrameRequest
    var cycleTime: Double? = nil
    /// Fades the color during a phase handoff without re-rendering.
    var fade: Double = 1
    /// Scales native blur during a handoff; zero leaves the backdrop to the processing indicator.
    var backdropFade: Double = 1
    @StateObject private var renderer: ChromaFrameRenderer
    private let retainsPreparedFrame: Bool
    private let submitRequest: ((ChromaFrameRequest) -> Void)?

    init(request: ChromaFrameRequest, cycleTime: Double? = nil, fade: Double = 1, backdropFade: Double = 1,
         renderer: ChromaFrameRenderer? = nil, submitRequest: ((ChromaFrameRequest) -> Void)? = nil) {
        self.request = request
        self.cycleTime = cycleTime
        self.fade = fade
        self.backdropFade = backdropFade
        self.submitRequest = submitRequest
        retainsPreparedFrame = renderer != nil
        _renderer = StateObject(wrappedValue: renderer ?? ChromaFrameRenderer())
    }

    var body: some View {
        ZStack {
            if let frame = renderer.frame, frame.request.geometry == request.geometry,
               frame.request.size == request.size {
                if request.backdrop, backdropFade > 0, let map = frame.radiusMap {
                    GlowBackdrop(profile: fadedProfile(frame.request.profile), radiusMap: map)
                }
                ChromaFrameCanvas(frame: frame, cycleTime: cycleTime)
                    .opacity(fade)
            }
        }
        .onChange(of: request, initial: true) { _, value in
            if let submitRequest { submitRequest(value) } else { renderer.submit(value) }
        }
        .onDisappear { if !retainsPreparedFrame { renderer.cancel() } }
    }

    private func fadedProfile(_ profile: GlowProfile) -> GlowProfile {
        guard backdropFade < 1 else { return profile }
        var faded = profile
        faded.blurScale = backdropFade
        return faded
    }
}

struct ChromaFrameCanvas: View {
    let frame: ChromaFrame
    var cycleTime: Double? = nil
    @State private var colorClock = GlowColorCycleClock()

    var body: some View {
        Canvas(colorMode: frame.request.profile.processingInput == nil ? .nonLinear : .extendedLinear) { context, size in
            let prepared = frame.request
            if let processing = prepared.profile.processingInput, let image = frame.images.first {
                WithinInputProcessing.draw(context: &context, contour: processing.contour,
                    time: processing.time, reducedMotion: false,
                    gradient: prepared.profile.response.tuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init(),
                    preparedImage: image)
                return
            }
            let animationTime = cycleTime.map { colorClock.sample(time: $0, speed: prepared.profile.response.tuning.gradientSpeed) }
            switch prepared.geometry {
            case .bottom, .windowBottom: break
            case .input, .withinInput: break
            case let .notch(layout):
                var exterior = TopGlow.edgePath(layout: layout)
                exterior.addLine(to: CGPoint(x: size.width, y: size.height))
                exterior.addLine(to: CGPoint(x: 0, y: size.height))
                exterior.closeSubpath()
                context.clip(to: exterior)
            }
            if prepared.geometry.appearance == .bottom {
                ChromaAppearance.draw(context: &context, geometry: prepared.geometry, size: size,
                    brightness: prepared.brightness, distortion: prepared.distortion,
                    expansion: prepared.profile.speechExpansion, width: prepared.profile.response.width,
                    tuning: prepared.profile.response.tuning,
                    preparedImages: frame.images, cycleTime: animationTime)
            } else {
                context.drawLayer { color in
                    if case let .input(contour) = prepared.geometry {
                        var exterior = Path(CGRect(origin: .zero, size: size))
                        exterior.addPath(InputOutlineBackdrop(contour: contour).path)
                        color.clip(to: exterior, style: FillStyle(eoFill: true))
                    }
                    ChromaAppearance.draw(context: &color, geometry: prepared.geometry, size: size,
                        brightness: prepared.brightness, distortion: prepared.distortion,
                        expansion: prepared.profile.speechExpansion, width: prepared.profile.response.width,
                        tuning: prepared.profile.response.tuning,
                        preparedImages: frame.images, cycleTime: animationTime)
                    if case let .notch(layout) = prepared.geometry {
                        color.blendMode = .destinationIn
                        let stops = (0...64).map { index in
                            Gradient.Stop(color: .white.opacity(layout.sideOpacity(at: size.width * Double(index) / 64)), location: Double(index) / 64)
                        }
                        color.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: stops),
                            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
                    }
                }
            }
        }
    }
}
