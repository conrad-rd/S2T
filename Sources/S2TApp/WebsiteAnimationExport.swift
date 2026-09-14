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
        let state = AppState(preview: true)
        let modes: [(String, CGRect)] = [
            ("bottom", CGRect(x: 0, y: desktop.height - GlowProfile.extent, width: desktop.width, height: GlowProfile.extent)),
            ("notch", CGRect(x: top.frame.minX, y: 0, width: top.frame.width, height: top.frame.height)),
            ("input", CGRect(x: 360, y: 460, width: 792, height: 304)),
            ("bezel", CGRect(x: desktop.width - BezelGeometry.size.width, y: (desktop.height - BezelGeometry.size.height) / 2, width: BezelGeometry.size.width, height: BezelGeometry.size.height))
        ]
        let transitionsOnly = ProcessInfo.processInfo.environment["S2T_WEBSITE_TRANSITIONS"] == "1"
        var manifestModes: [[String: Any]] = []
        for (name, rect) in modes {
            if transitionsOnly && name != "bezel" { continue }
            if let mode = ProcessInfo.processInfo.environment["S2T_WEBSITE_EXPORT_MODE"], mode != name { continue }
            state.glowStrength = Double(ProcessInfo.processInfo.environment["S2T_WEBSITE_GLOW_STRENGTH"] ?? "") ?? (name == "bottom" ? 1.15 : 0.8)
            renderScale = name == "bezel" ? 4 : name == "bottom" ? 2 : 3
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let background = try render(ExportDesktop(wallpaper: wallpaperImage, input: name == "input"), size: desktop)
            try write(background, to: destination.appendingPathComponent("background.png"))
            guard let crop = background.cropping(to: CGRect(x: rect.minX * renderScale, y: rect.minY * renderScale, width: rect.width * renderScale, height: rect.height * renderScale)) else { throw failure("Invalid preview bounds.") }
            let compositor = try NativeCompositor(background: crop, size: rect.size, scale: renderScale)
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
                        let foreground: CGImage
                        switch name {
                        case "bottom":
                            foreground = try render(BottomGlow(level: live, strength: state.glowStrength, phase: phase,
                                timeOverride: time, spectrumProvider: { bands }, reduceMotionOverride: false,
                                reduceTransparencyOverride: false, renderedProfile: profile), size: rect.size)
                        case "notch":
                            profile.topLayout = top
                            foreground = try render(TopGlow(renderedProfile: profile, showsBackdrop: false, layout: top,
                                strength: state.glowStrength, phase: phase, levelProvider: { live }, spectrumProvider: { bands },
                                timeOverride: time, reduceTransparencyOverride: false, reduceMotionOverride: false), size: rect.size)
                        case "input":
                            profile.inputOutline = InputOutlineBackdrop(rect: input.outlineRect, cornerRadius: input.cornerRadius, strength: state.glowStrength)
                            foreground = try render(InputOutline(renderedProfile: profile, showsBackdrop: false, state: state, layout: input,
                                reduceMotionOverride: false, levelProvider: { live }, spectrumProvider: { bands },
                                timeOverride: time, reduceTransparencyOverride: false), size: rect.size)
                        default:
                            indicator.update(form: motion.form(at: time), symbol: BezelSymbol.resolve(phase: phase, waiting: false, deliveryHint: nil),
                                level: live, spectrum: bands, time: time, reducedMotion: false)
                            profile = GlowProfile(energy: min(1, min(indicator.form.depth, indicator.form.body)), heights: [],
                                bezel: BezelBackdrop(path: indicator.displayedShape.path))
                            foreground = try bezelImage(indicator)
                        }
                        let image = try compositor.frame(profile: profile, foreground: foreground, time: time)
                        try write(image, to: destination.appendingPathComponent(String(format: "%@-%03d.png", phaseName, frame)))
                        frameTime += 1.0 / Double(fps)
                    }
                    if frame % 60 == 0 { print("Export \(name) \(phaseName) \(frame)/\(count)"); fflush(stdout) }
                }
            }
            manifestModes.append(["id": name, "scale": renderScale, "x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height, "frames": manifests])
        }
        let manifest: [String: Any] = ["build": BuildIdentity.menuLabel, "fps": fps, "width": desktop.width, "height": desktop.height,
            "strength": state.glowStrength, "modes": manifestModes,
            "rendering": "Production SwiftUI Canvas and AppKit drawing, production Glur filter, offscreen Metal composition. Synthetic PCM. No screen capture."]
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

    static func write(_ image: CGImage, to url: URL) throws {
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw failure("PNG encoding failed.") }
        try png.write(to: url, options: .atomic)
    }

    static func failure(_ message: String) -> NSError { NSError(domain: "WebsiteAnimationExport", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private struct ExportDesktop: View {
    let wallpaper: NSImage
    let input: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            if input {
                Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
                Capsule().fill(.white).shadow(color: .black.opacity(0.05), radius: 10, y: 2)
                    .overlay(Capsule().stroke(.black.opacity(0.06), lineWidth: 1))
                    .frame(width: 560, height: 51.2).offset(x: 476, y: 586.4)
            } else {
                Image(nsImage: wallpaper).resizable().scaledToFill().frame(width: 1512, height: 982).clipped()
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black)
                    .frame(width: 192, height: 32).offset(x: 660)
            }
        }.frame(width: 1512, height: 982)
    }
}

@MainActor private final class NativeCompositor {
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
