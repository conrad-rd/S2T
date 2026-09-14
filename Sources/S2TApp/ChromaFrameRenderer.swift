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
    @Published private(set) var frame: ChromaFrame?
    private var latest: ChromaFrameRequest?
    private var rendering = false
    private var generation = 0
    private(set) var completedFrames = 0

    func submit(_ request: ChromaFrameRequest) {
        guard request.size.width > 0, request.size.height > 0 else { return }
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
        Self.queue.async { [weak self] in
            let result = autoreleasepool { ChromaFrame.render(request) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rendering = false
                if self.generation == generation, let latest = self.latest,
                   latest.geometry == request.geometry, latest.size == request.size,
                   latest.backdrop == request.backdrop, let result {
                    self.completedFrames += 1
                    self.frame = result
                }
                // A failed unchanged request waits for new input instead of spinning.
                if self.latest != request { self.startIfNeeded() }
            }
        }
    }
}

struct PreparedChromaGlow: View {
    let request: ChromaFrameRequest
    var cycleTime: Double? = nil
    @StateObject private var renderer = ChromaFrameRenderer()

    var body: some View {
        ZStack {
            if let frame = renderer.frame, frame.request.geometry == request.geometry,
               frame.request.size == request.size {
                if request.backdrop, let map = frame.radiusMap {
                    GlowBackdrop(profile: frame.request.profile, radiusMap: map)
                }
                ChromaFrameCanvas(frame: frame, cycleTime: cycleTime)
            }
        }
        .onChange(of: request, initial: true) { _, value in renderer.submit(value) }
        .onDisappear { renderer.cancel() }
    }
}

struct ChromaFrameCanvas: View {
    let frame: ChromaFrame
    var cycleTime: Double? = nil
    @State private var colorClock = GlowColorCycleClock()

    var body: some View {
        Canvas(colorMode: .nonLinear) { context, size in
            let prepared = frame.request
            let animationTime = cycleTime.map { colorClock.sample(time: $0, speed: prepared.profile.response.tuning.gradientSpeed) }
            switch prepared.geometry {
            case .bottom: break
            case .input: break
            case let .notch(layout):
                var exterior = TopGlow.edgePath(layout: layout)
                exterior.addLine(to: CGPoint(x: size.width, y: size.height))
                exterior.addLine(to: CGPoint(x: 0, y: size.height))
                exterior.closeSubpath()
                context.clip(to: exterior)
            }
            if case .bottom = prepared.geometry {
                ChromaAppearance.draw(context: &context, geometry: prepared.geometry, size: size,
                    brightness: prepared.brightness, distortion: prepared.distortion,
                    expansion: prepared.profile.speechExpansion, width: prepared.profile.response.width,
                    tuning: prepared.profile.response.tuning,
                    preparedImages: frame.images, cycleTime: animationTime)
            } else {
                context.drawLayer { color in
                    if case let .input(rect, radius, cornerStyle) = prepared.geometry {
                        var exterior = Path(CGRect(origin: .zero, size: size))
                        exterior.addPath(InputOutlineBackdrop(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle).path)
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
