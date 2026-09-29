import AppKit
import Metal
import SwiftUI
import S2TCore

@MainActor enum WebsiteAnimationExport {
    static let desktop = CGSize(width: 1512, height: 982)
    static let fps = 60
    static var renderScale: CGFloat = 1

    static func run(wallpaper: URL, directory: URL) throws {
        guard let wallpaperImage = NSImage(contentsOf: wallpaper) else { throw failure("Cannot read wallpaper.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let display = GlowDisplay(frame: CGRect(origin: .zero, size: desktop), safeTop: 32,
            topLeft: CGRect(x: 0, y: 950, width: 660, height: 32), topRight: CGRect(x: 852, y: 950, width: 660, height: 32))
        let top = TopGlowLayout(display: display)
        let input = InputOutlineLayout()
        input.outlineRect = CGRect(x: 116, y: 126.4, width: 560, height: 51.2)
        input.cornerRadius = 25.6
        input.cornerStyle = .circular
        let preferences = UserDefaults(suiteName: "com.s2t.preview")!
        let savedPreferences = preferences.persistentDomain(forName: "com.s2t.preview") ?? [:]
        defer { preferences.setPersistentDomain(savedPreferences, forName: "com.s2t.preview") }
        let state = AppState(preview: true)
        let reference = try ProcessInfo.processInfo.environment["S2T_WEBSITE_APPEARANCE_REFERENCE"].map {
            try JSONDecoder().decode(WebsiteAppearanceReference.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
        }
        let modes: [(String, CGRect)] = [
            ("bottom", CGRect(x: 0, y: desktop.height - GlowProfile.extent, width: desktop.width, height: GlowProfile.extent)),
            ("notch", CGRect(x: top.frame.minX, y: 0, width: top.frame.width, height: top.frame.height)),
            ("input", CGRect(x: 360, y: 460, width: 792, height: 304)),
            ("bezel", CGRect(x: desktop.width - BezelGeometry.size.width, y: (desktop.height - BezelGeometry.size.height) / 2, width: BezelGeometry.size.width, height: BezelGeometry.size.height))
        ]
        let withinInput = ProcessInfo.processInfo.environment["S2T_WEBSITE_INPUT_PLACEMENT"] != "around"
        let transitionsOnly = ProcessInfo.processInfo.environment["S2T_WEBSITE_TRANSITIONS"] == "1"
        var manifestModes: [[String: Any]] = []
        for (name, rect) in modes {
            if transitionsOnly && name != "bezel" { continue }
            if let mode = ProcessInfo.processInfo.environment["S2T_WEBSITE_EXPORT_MODE"], mode != name { continue }
            state.glowAppearance = name == "input" ? (withinInput ? .withinInput : .aroundInput) : name == "notch" ? .aroundNotch : name == "bezel" ? .bezel : .bottom
            state.glowStrength = Double(ProcessInfo.processInfo.environment["S2T_WEBSITE_GLOW_STRENGTH"] ?? "") ?? (name == "bottom" ? 1.15 : 0.8)
            if name == "input" {
                state.glowStrength = 1.3
                state.glowMinimum = 0.2586009174311927
                state.glowMaximum = 2.033669008027523
                state.glowTuning = GlowTuning(backgroundBlur: 0.14506880733944955, softness: 10,
                    falloff: 1.9144208715596331, edgeBrightness: 2, edgeBlur: 0, edgeGlow: 0.5,
                    edgeHeight: 0.053612385321100915, edgeOpacity: 1,
                    bodyOpacity: 0.6149655963302753, gradientSpeed: 0.19879518072289157)
            }
            if let reference {
                state.glowStrength = reference.strength
                state.glowWidth = reference.width
                state.glowMinimum = reference.minimum
                state.glowMaximum = reference.maximum
                state.glowTuning = reference.tuning
            }
            renderScale = name == "bezel" ? 4 : name == "bottom" ? 2 : 3
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let background = try render(ExportDesktop(wallpaper: wallpaperImage, input: name == "input", inputRadius: input.cornerRadius), size: desktop)
            try write(background, to: destination.appendingPathComponent("background.png"))
            guard let crop = background.cropping(to: CGRect(x: rect.minX * renderScale, y: rect.minY * renderScale, width: rect.width * renderScale, height: rect.height * renderScale)) else { throw failure("Invalid preview bounds.") }
            let compositor = try GeneratedGlowCompositor(background: crop, size: rect.size, scale: renderScale)
            let history = GlowHistory(smoothAudio: name != "bottom")
            let indicator = BezelIndicatorView(frame: CGRect(origin: .zero, size: BezelGeometry.size))
            var motion = BezelMotion()
            motion.setVisible(true, at: 0)
            var spectrum = AudioSpectrum(sampleRate: 48000)
            var manifests: [String: Int] = [:]
            var frameTime = 0.0
            let phases: [(String, DictationPhase, Int)] = transitionsOnly
                ? [("appearing", .recording, 60), ("disappearing", .complete, 60)]
                : [("listening", .recording, 180), ("processing", .processing, 168), ("delivered", .complete, 60)]
            for (phaseName, phase, count) in phases {
                if phaseName == "disappearing" { motion.setVisible(false, at: frameTime) }
                state.phase = phase
                manifests[phaseName] = count
                for frame in 0..<count {
                    try autoreleasepool {
                        let time = frameTime
                        let live = phase == .recording ? 0.3 + 0.22 * pow(sin(time * 2.1), 2) : 0
                        for sample in 0..<800 {
                            let t = time + Double(sample) / 48000
                            let frequency = 170 + 1600 * (0.5 + 0.5 * sin(t * 1.8))
                            spectrum.consume(live * 0.12 * sin(2 * .pi * frequency * t))
                        }
                        let bands = phase == .recording ? spectrum.levels : Array(repeating: 0, count: 7)
                        var profile = history.frame(level: live, time: time, reducedMotion: false, bands: bands, active: !phase.busy)
                        profile.sweepStrength = state.glowStrength
                        profile.response = state.glowResponseSettings
                        // Matches the Settings preview, which always shows the maximum Within Input glow size.
                        if name == "input" && withinInput { profile.response.tuning = profile.response.tuning.forInput(size: .zero, preview: true) }
                        if name == "notch" { profile.topLayout = top }
                        if name == "input" {
                            profile.inputOutline = InputOutlineBackdrop(contour: input.contour, strength: state.glowStrength, withinInput: withinInput)
                        }
                        let foreground: CGImage
                        if name != "bezel" && phase == .recording {
                            let geometry: ChromaAppearance.Geometry = name == "bottom" ? .bottom
                                : name == "notch" ? .notch(top) : profile.inputOutline!.geometry
                            let request = ChromaFrameRequest(geometry: geometry, size: rect.size, profile: profile,
                                brightness: profile.speechGain, backdrop: false)
                            guard let prepared = ChromaFrame.render(request) else { throw failure("Cannot prepare native appearance frame.") }
                            if frame == 0 {
                                print("Native frame \(name): \(geometry), size \(rect.size)")
                                if case let .input(contour) = geometry {
                                    let samples = InputGradientCycle.samples(contour: contour)
                                    guard samples.allSatisfy({ $0.angle.isFinite && $0.distance.isFinite }) else { throw failure("Invalid native input gradient samples.") }
                                }
                                fflush(stdout)
                            }
                            foreground = try render(ChromaFrameCanvas(frame: prepared, cycleTime: time), size: rect.size)
                        } else if name != "bezel" && phase == .complete {
                            profile = GlowProfile(energy: 0, heights: [], active: false)
                            foreground = try render(Color.clear, size: rect.size)
                        } else { switch name {
                        case "bottom":
                            foreground = try render(BottomGlow(level: live, strength: state.glowStrength, phase: phase,
                                timeOverride: time, spectrumProvider: { bands }, reduceMotionOverride: false,
                                reduceTransparencyOverride: false, renderedProfile: profile, response: state.glowResponseSettings), size: rect.size)
                        case "notch":
                            profile.topLayout = top
                            foreground = try render(TopGlow(renderedProfile: profile, showsBackdrop: false, layout: top,
                                strength: state.glowStrength, phase: phase, levelProvider: { live }, spectrumProvider: { bands },
                                timeOverride: time, reduceTransparencyOverride: false, reduceMotionOverride: false, response: state.glowResponseSettings), size: rect.size)
                        case "input":
                            profile.inputOutline = InputOutlineBackdrop(contour: input.contour, strength: state.glowStrength, withinInput: withinInput)
                            if withinInput {
                                profile = InputProcessingGlow.profile(contour: input.contour, time: time)
                                foreground = try render(Canvas(opaque: false, colorMode: .extendedLinear) { context, _ in
                                    WithinInputProcessing.draw(context: &context, contour: input.contour, time: time,
                                        reducedMotion: false, gradient: state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init())
                                }, size: rect.size)
                            } else {
                                foreground = try render(InputOutline(renderedProfile: profile, showsBackdrop: false, state: state, layout: input,
                                    reduceMotionOverride: false, levelProvider: { live }, spectrumProvider: { bands },
                                    timeOverride: time, reduceTransparencyOverride: false), size: rect.size)
                            }
                        default:
                            indicator.update(form: motion.form(at: time), symbol: BezelSymbol.resolve(phase: phase, waiting: false, deliveryHint: nil),
                                level: live, spectrum: bands, time: time, reducedMotion: false)
                            profile = GlowProfile(energy: min(1, min(indicator.form.depth, indicator.form.body)), heights: [],
                                bezel: BezelBackdrop(path: indicator.displayedShape.path))
                            foreground = try bezelImage(indicator)
                        }
                        }
                        let image = phase == .complete && name != "bezel" ? crop
                            : try compositor.frame(profile: profile, foreground: foreground, time: time)
                        try write(image, to: destination.appendingPathComponent(String(format: "%@-%03d.png", phaseName, frame)))
                        frameTime += 1.0 / Double(fps)
                    }
                    if frame % 60 == 0 { print("Export \(name) \(phaseName) \(frame)/\(count)"); fflush(stdout) }
                }
            }
            manifestModes.append(["id": name, "scale": renderScale, "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height, "frames": manifests])
        }
        if !transitionsOnly && ProcessInfo.processInfo.environment["S2T_WEBSITE_EXPORT_MODE"] == "glass" {
            if let reference { state.glowTuning = reference.tuning }
            manifestModes.append(try glass(wallpaper: wallpaperImage, directory: directory, state: state))
        }
        var manifest: [String: Any] = ["build": BuildIdentity.menuLabel, "fps": fps, "width": desktop.width, "height": desktop.height,
            "strength": state.glowStrength, "modes": manifestModes,
            "rendering": "Production SwiftUI Canvas and AppKit drawing, production Glur filter, offscreen Metal composition. Synthetic PCM. No screen capture."]
        if let reference {
            manifest["appearance"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference))
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("manifest.json"))
        print("Native website animations exported: \(BuildIdentity.menuLabel)")
    }

    static func render<V: View>(_ view: V, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.displayScale, renderScale))
        renderer.scale = renderScale
        guard let image = renderer.cgImage else { throw failure("Production view did not render.") }
        return image
    }

    static func bezelImage(_ indicator: BezelIndicatorView) throws -> CGImage {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(indicator.bounds.width * renderScale), pixelsHigh: Int(indicator.bounds.height * renderScale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure("Cannot draw bezel.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: renderScale, y: renderScale)
        graphics.cgContext.translateBy(x: 0, y: indicator.bounds.height)
        graphics.cgContext.scaleBy(x: 1, y: -1)
        indicator.draw(indicator.bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { throw failure("Missing bezel image.") }
        return image
    }

    /// One continuous 6.5-second website cycle: listening, processing from 3.01 s, success from 5.2 s.
    /// The capsule rests 32 points above a 68-point Dock, like the live panel above visibleFrame.
    static func glass(wallpaper: NSImage, directory: URL, state: AppState) throws -> [String: Any] {
        renderScale = 3
        let dockHeight: CGFloat = 68
        let size = GlassWaveformView.size
        let rect = CGRect(x: (desktop.width - size.width) / 2, y: desktop.height - dockHeight - 50 - size.height / 2,
            width: size.width, height: size.height)
        let destination = directory.appendingPathComponent("glass")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let background = try render(ExportDesktop(wallpaper: wallpaper, input: false, inputRadius: 0), size: desktop)
        try write(background, to: destination.appendingPathComponent("background.png"))
        guard let crop = background.cropping(to: CGRect(x: rect.minX * renderScale, y: rect.minY * renderScale,
            width: rect.width * renderScale, height: rect.height * renderScale)) else { throw failure("Invalid glass bounds.") }
        let material = try GlassBackdropApproximation(background: crop, scale: renderScale)
        let indicator = GlassWaveformView(frame: CGRect(origin: .zero, size: size))
        let gradient = state.glowTuning.gradients[GlowAppearance.withinInput.rawValue] ?? .init()
        var spectrum = AudioSpectrum(sampleRate: 48000)
        let count = 390
        for frame in 0..<count {
            try autoreleasepool {
                let time = Double(frame) / Double(fps)
                let symbol: BezelSymbol = time < 3.01 ? .waveform : time < 5.2 ? .spinner : .checkmark
                let live = symbol == .waveform ? 0.3 + 0.22 * pow(sin(time * 2.1), 2) : 0
                for sample in 0..<800 {
                    let t = time + Double(sample) / 48000
                    let frequency = 170 + 1600 * (0.5 + 0.5 * sin(t * 1.8))
                    spectrum.consume(live * 0.12 * sin(2 * .pi * frequency * t))
                }
                let bands = symbol == .waveform ? spectrum.levels : Array(repeating: 0, count: 7)
                indicator.update(spectrum: bands, symbol: symbol, time: time, reducedMotion: false,
                    reducedTransparency: false, gradient: gradient)
                // OverlayVisibility: 0.08 s appearance and 0.22 s disappearance, both ease-in-ease-out.
                let opacity = easeInOut(time / 0.08) * easeInOut((6.5 - time) / 0.22)
                let image = try glassFrame(indicator: indicator, crop: crop, material: material, opacity: opacity)
                if frame == 0 { print("Native glass waveform frame \(indicator.waveformView.frame)"); fflush(stdout) }
                try write(image, to: destination.appendingPathComponent(String(format: "cycle-%03d.png", frame)))
            }
            if frame % 60 == 0 { print("Export glass cycle \(frame)/\(count)"); fflush(stdout) }
        }
        return ["id": "glass", "scale": renderScale, "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height,
            "dockHeight": dockHeight, "frames": ["cycle": count],
            "material": "NSGlassEffectView composes only in WindowServer. Offscreen frames approximate clear glass with 1-point softening, edge refraction and slight dimming beneath the production artwork."]
    }

    static func glassFrame(indicator: GlassWaveformView, crop: CGImage, material: GlassBackdropApproximation, opacity: Double) throws -> CGImage {
        let size = indicator.bounds.size
        guard let context = CGContext(data: nil, width: Int(size.width * renderScale), height: Int(size.height * renderScale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Cannot draw glass.") }
        context.scaleBy(x: renderScale, y: renderScale)
        context.draw(crop, in: CGRect(origin: .zero, size: size))
        let body = indicator.bodyRect, animation = indicator.animation
        var transform = CGAffineTransform(translationX: body.midX, y: body.midY + animation.offsetY)
            .scaledBy(x: animation.scaleX, y: animation.scaleY).translatedBy(x: -body.width / 2, y: -body.height / 2)
        let capsule = GlassCapsuleArtwork.path(in: CGRect(origin: .zero, size: body.size))
        guard let path = capsule.copy(using: &transform) else { throw failure("Cannot place glass capsule.") }
        context.setAlpha(opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // The production drop shadow: 0.14 opacity, 4-point radius, 2 points down.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2 * renderScale), blur: 8 * renderScale, color: CGColor(gray: 0, alpha: 1))
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0, alpha: 0.14))
        context.fillPath()
        context.restoreGState()
        if let glass = material.image(body: body.size, transform: transform, size: size, scale: renderScale) {
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.draw(glass, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }
        // The material content view: black overlay, phase symbols, then the waveform and cancel subviews.
        context.saveGState()
        context.concatenate(transform)
        context.addPath(capsule)
        context.clip()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }
        let ink = indicator.materialContent
        ink.layoutSubtreeIfNeeded()
        ink.draw(ink.bounds)
        for view in ink.subviews where !view.isHidden && view.alphaValue > 0 {
            context.saveGState()
            context.translateBy(x: view.frame.minX, y: view.frame.minY)
            context.setAlpha(view.alphaValue)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            view.draw(view.bounds)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        context.restoreGState()
        context.endTransparencyLayer()
        guard let image = context.makeImage() else { throw failure("Missing glass image.") }
        return image
    }

    static func easeInOut(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        var low = 0.0, high = 1.0, t = x
        for _ in 0..<32 {
            t = (low + high) / 2
            if 3 * (1 - t) * (1 - t) * t * 0.42 + 3 * (1 - t) * t * t * 0.58 + t * t * t < x { low = t } else { high = t }
        }
        return 3 * (1 - t) * t * t + t * t * t
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("PNG encoding failed.") }
        try png.write(to: url, options: .atomic)
    }

    static func failure(_ message: String) -> NSError { NSError(domain: "WebsiteAnimationExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private struct ExportDesktop: View {
    let wallpaper: NSImage
    let input: Bool
    let inputRadius: CGFloat
    var body: some View {
        ZStack(alignment: .topLeading) {
            if input {
                Color(nsColor: AppearancePreviewScene.inputBackgroundColor)
                RoundedRectangle(cornerRadius: inputRadius, style: .circular).fill(Color(nsColor: AppearancePreviewScene.inputComposerColor))
                    .frame(width: 560, height: 51.2).offset(x: 476, y: 586.4)
            } else {
                Image(nsImage: wallpaper).resizable().scaledToFill().frame(width: 1512, height: 982).clipped()
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black)
                    .frame(width: 192, height: 32).offset(x: 660)
            }
        }.frame(width: 1512, height: 982)
    }
}

@MainActor final class GeneratedGlowCompositor {
    let backdrop: ProgressiveBackdropView
    let root = CALayer()
    let stage = CALayer()
    let filtered = CALayer()
    let color = CALayer()
    let texture: MTLTexture
    let queue: MTLCommandQueue
    let renderer: CARenderer
    let size: CGSize

    init(background: CGImage, size: CGSize, scale: CGFloat) throws {
        self.size = size
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw WebsiteAnimationExport.failure("Metal unavailable.") }
        self.queue = queue
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width * scale), height: Int(size.height * scale), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw WebsiteAnimationExport.failure("Cannot create render texture.") }
        self.texture = texture
        backdrop = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
        root.frame = backdrop.bounds
        root.contents = background
        filtered.frame = root.bounds
        filtered.contents = background
        color.frame = root.bounds
        root.addSublayer(filtered)
        root.addSublayer(color)
        renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        stage.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        root.anchorPoint = .zero
        root.position = .zero
        root.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        root.contentsScale = scale
        filtered.contentsScale = scale
        color.contentsScale = scale
        stage.addSublayer(root)
        renderer.layer = stage
        renderer.bounds = stage.bounds
    }

    func frame(profile: GlowProfile, foreground: CGImage, time: Double) throws -> CGImage {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.apply(profile: profile, radiusMap: GlowBackdrop.mask(profile: profile, size: size))
        guard let sampler = backdrop.layer?.sublayers?.first, let filters = sampler.filters, !filters.isEmpty else {
            throw WebsiteAnimationExport.failure("Production variable-radius filter unavailable.")
        }
        filtered.filters = filters
        filtered.opacity = sampler.opacity
        filtered.isHidden = sampler.isHidden
        color.contents = foreground
        CATransaction.commit()
        CATransaction.flush()
        renderer.beginFrame(atTime: time, timeStamp: nil)
        renderer.addUpdate(stage.bounds)
        renderer.render()
        renderer.endFrame()
        guard let completion = queue.makeCommandBuffer() else { throw WebsiteAnimationExport.failure("Metal completion unavailable.") }
        completion.commit()
        completion.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let rowBytes = texture.width * 4
        for y in 0..<(texture.height / 2) {
            let opposite = texture.height - 1 - y
            for x in 0..<rowBytes { bytes.swapAt(y * rowBytes + x, opposite * rowBytes + x) }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: texture.width, height: texture.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: texture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw WebsiteAnimationExport.failure("Cannot read generated texture.") }
        return image
    }
}

private struct WebsiteAppearanceReference: Codable {
    let strength: Double
    let width: Double
    let minimum: Double
    let maximum: Double
    let tuning: GlowTuning
}

/// Offscreen stand-in for NSGlassEffectView's clear material, which WindowServer composes live.
/// The production black overlay covers most of the capsule; only its lower fade reveals this layer.
struct GlassBackdropApproximation {
    private let pixels: [Float]
    private let width: Int
    private let height: Int

    init(background: CGImage, scale: CGFloat) throws {
        width = background.width
        height = background.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "WebsiteAnimationExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read glass backdrop."])
        }
        context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Clear glass keeps the backdrop nearly sharp: a 1-point Gaussian, applied separably.
        let sigma = Double(scale)
        let reach = Int(ceil(sigma * 3))
        let weights = (-reach...reach).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let total = weights.reduce(0, +)
        var source = bytes.map(Float.init)
        var target = source
        for horizontal in [true, false] {
            for y in 0..<height { for x in 0..<width { for channel in 0..<4 {
                var value = 0.0
                for (index, weight) in weights.enumerated() {
                    let offset = index - reach
                    let sx = horizontal ? min(width - 1, max(0, x + offset)) : x
                    let sy = horizontal ? y : min(height - 1, max(0, y + offset))
                    value += weight * Double(source[(sy * width + sx) * 4 + channel])
                }
                target[(y * width + x) * 4 + channel] = Float(value / total)
            } } }
            source = target
        }
        pixels = source
    }

    /// Samples the softened backdrop inside the capsule, bending the outer 8 points outward by up to 3 points
    /// and dimming it slightly like dark clear glass.
    func image(body: CGSize, transform: CGAffineTransform, size: CGSize, scale: CGFloat) -> CGImage? {
        let inverse = transform.inverted()
        let radius = body.height / 2, straight = body.width / 2 - radius
        let band = 8.0, refraction = 3.0, dim: Float = 0.9
        let bounds = CGRect(origin: .zero, size: body).applying(transform).insetBy(dx: -1, dy: -1)
        var output = [UInt8](repeating: 0, count: width * height * 4)
        func sample(_ x: Double, _ y: Double, _ channel: Int) -> Float {
            let x = min(Double(width - 1), max(0, x)), y = min(Double(height - 1), max(0, y))
            let x0 = Int(x), y0 = Int(y), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
            func value(_ px: Int, _ py: Int) -> Float { pixels[(py * width + px) * 4 + channel] }
            return (value(x0, y0) * (1 - fx) + value(x1, y0) * fx) * (1 - fy) + (value(x0, y1) * (1 - fx) + value(x1, y1) * fx) * fy
        }
        for py in 0..<height { for px in 0..<width {
            var point = CGPoint(x: (Double(px) + 0.5) / scale, y: size.height - (Double(py) + 0.5) / scale)
            guard bounds.contains(point) else { continue }
            let local = point.applying(inverse)
            let qx = max(0, abs(local.x - body.width / 2) - straight), qy = local.y - radius
            let length = hypot(qx, qy)
            let depth = radius - length
            guard depth > -1 else { continue }
            if depth < band {
                let normal = length > 0 ? CGVector(dx: (local.x < body.width / 2 ? -qx : qx) / length, dy: qy / length)
                    : CGVector(dx: 0, dy: local.y < radius ? -1 : 1)
                let push = refraction * pow(1 - max(0, depth) / band, 2)
                point.x += normal.dx * push * transform.a
                point.y += normal.dy * push * transform.d
            }
            let sx = point.x * scale - 0.5, sy = (size.height - point.y) * scale - 0.5
            let offset = (py * width + px) * 4
            for channel in 0..<3 { output[offset + channel] = UInt8(min(255, max(0, (sample(sx, sy, channel) * dim).rounded()))) }
            output[offset + 3] = 255
        } }
        guard let provider = CGDataProvider(data: Data(output) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
