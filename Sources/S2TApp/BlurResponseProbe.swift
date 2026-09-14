import AppKit
import Metal
import S2TCore
import SwiftUI

// Only generated lines, generated maps, and hidden window geometry are inspected.
@MainActor enum BlurResponseProbe {
    static func run() throws {
        let size = CGSize(width: 1080, height: 800)
        let rect = CGRect(x: 70, y: 250, width: 940, height: 100)
        let geometry = ChromaAppearance.Geometry.input(rect, 24)
        let view = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1080, pixelsHigh: 800,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 4320, bitsPerPixel: 32), let bytes = bitmap.bitmapData else {
            throw failure("Cannot allocate generated fixture")
        }
        for y in 0..<800 { for x in 0..<1080 {
            let value: UInt8 = (538...541).contains(x) ? 0 : 255
            let offset = (y * 1080 + x) * 4
            for channel in 0..<3 { bytes[offset + channel] = value }
            bytes[offset + 3] = 255
        } }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1080, height: 800, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw failure("No render target") }
        let root = CALayer()
        root.frame = view.bounds
        root.contents = bitmap.cgImage
        root.actions = ["filters": NSNull()]
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
        var previousLine: [Int]?
        for amount in [0.3, 0.5, 1, 2, 3, 3.5, 3.9, 4, 4.1, 4.5, 5] {
            var profile = GlowProfile(energy: 1, heights: [], inputOutline: .init(rect: rect, cornerRadius: 24, strength: 1.3))
            profile.response = .init(minimum: 0, maximum: amount)
            view.profile = profile
            guard let filter = view.layer?.sublayers?.first?.filters?.first as? NSObject,
                  let map = GlowBackdrop.mask(profile: profile, size: size)?.representations.first as? NSBitmapImageRep else {
                throw failure("Missing native filter")
            }
            root.filters = [filter]
            for _ in 0..<3 {
                CATransaction.flush()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                renderer.addUpdate(root.bounds)
                renderer.render()
                renderer.endFrame()
                let completion = queue.makeCommandBuffer()!
                completion.commit(); completion.waitUntilCompleted()
            }
            var pixels = [UInt8](repeating: 0, count: 1080 * 800 * 4)
            texture.getBytes(&pixels, bytesPerRow: 4320, from: MTLRegionMake2D(0, 0, 1080, 800), mipmapLevel: 0)
            let distances = [5, 15, 30, 60, 120, 200, 300]
            let luminance = distances.map { Int(pixels[((799 - 350 - $0) * 1080 + 540) * 4]) }
            let coverage = distances.map { Int((map.colorAt(x: 540, y: 350 + $0)?.alphaComponent ?? 0) * 255) }
            print("amount=\(amount) expansion=\(profile.speechExpansion) radius=\(filter.value(forKey: "inputRadius") ?? "nil") map=\(coverage) line=\(luminance)")
            let radius = filter.value(forKey: "inputRadius") as? Double ?? -1
            guard radius > 0, radius < 36 else { throw failure("Native blur exceeds its bounded response") }
            if amount == 0.3, luminance[1] < 200 { throw failure("Low amounts still have weak background blur") }
            if let previousLine, (4...4.1).contains(amount) {
                guard zip(previousLine, luminance).allSatisfy({ abs($0 - $1) <= 4 }) else { throw failure("Generated native blur jumps near 400 percent") }
            }
            previousLine = luminance
            guard let frame = ChromaFrame.render(.init(geometry: geometry, size: size, profile: profile,
                brightness: profile.speechGain, backdrop: true)) else { throw failure("Missing generated color frame") }
            let canvas = ChromaFrameCanvas(frame: frame).frame(width: size.width, height: size.height)
            let imageRenderer = ImageRenderer(content: canvas)
            imageRenderer.scale = 1
            guard let image = imageRenderer.cgImage else { throw failure("Cannot render generated input fade") }
            let color = NSBitmapImageRep(cgImage: image)
            let tail = [15, 30, 60, 120, 200, 300, 440].map {
                Int((color.colorAt(x: 540, y: 350 + $0)?.alphaComponent ?? 0) * 255)
            }
            guard tail.last == 0, zip(tail, tail.dropFirst()).allSatisfy({ $0 >= $1 }),
                  (color.colorAt(x: 540, y: 300)?.alphaComponent ?? -1) == 0 else {
                throw failure("Input fade clips at the panel bottom or covers the input interior")
            }
            if amount == 0.3, tail[1] < 10 { throw failure("Quiet input fade cuts off too close to the field") }
            print("input bottom color alpha at 15/30/60/120/200/300/440 points=\(tail)")
            if [0.3, 1, 5].contains(amount) {
                try GlowFixture.write(canvas.background(Color.white), size: size, name: "input-blur-response-\(amount)")
            }
        }
        let state = AppState(preview: true)
        let saved = (state.glowMaximum, state.glowAppearance)
        defer { state.glowMaximum = saved.0; state.glowAppearance = saved.1 }
        state.glowAppearance = .aroundInput
        let controller = InputOutlineWindowController(state: state)
        for screen in NSScreen.screens {
            let field = CGRect(x: screen.frame.midX - 350.25, y: screen.frame.minY + 180.25, width: 700.5, height: 100.5)
            for maximum in [2.0, 3.9, 4, 4.1, 5] {
                state.glowMaximum = maximum
                let geometry = InputOutlineGeometry(field: field, paddingScale: state.glowResponseSettings.paddingScale, displayFrame: screen.frame)
                let panel = controller.prepare(field: field)
                let root = panel.contentView as! ProgressiveBackdropView
                let host = root.subviews.first!
                print("hidden maximum=\(maximum) display=\(screen.frame) expected=\(geometry.windowFrame) actual=\(panel.frame) root=\(root.bounds) host=\(host.frame) outline=\(geometry.outlineRect)")
                guard !panel.isVisible else { throw failure("Fixture window became visible") }
            }
        }
        if let screen = NSScreen.screens.first {
            let field = CGRect(x: screen.frame.midX - 350, y: screen.frame.minY + 180, width: 700, height: 100)
            let frames = ChromaFrameRenderer()
            var geometries: [InputOutlineGeometry] = []
            let start = CACurrentMediaTime()
            for step in 0...40 {
                let response = GlowResponseSettings(minimum: 0, maximum: 2 + Double(step) * 0.075)
                let layout = InputOutlineGeometry(field: field, paddingScale: response.paddingScale, displayFrame: screen.frame)
                if geometries.last != layout { geometries.append(layout) }
                var profile = GlowProfile(energy: 1, heights: [], inputOutline: .init(rect: layout.outlineRect, cornerRadius: 24, strength: 1.3))
                profile.response = response
                frames.submit(.init(geometry: profile.chromaGeometry, size: layout.windowFrame.size, profile: profile, brightness: profile.speechGain, backdrop: true))
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            print("drag seconds=\(CACurrentMediaTime() - start) geometries=\(geometries.count) displayedFrames=\(frames.completedFrames)")
            guard geometries.count == 1, frames.completedFrames >= 10 else {
                throw failure("Slider drag invalidates geometry or starves prepared frames")
            }
            frames.cancel()
        }
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BlurResponseProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
