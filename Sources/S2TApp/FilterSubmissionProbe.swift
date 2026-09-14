import AppKit
import Metal
import S2TCore

// Renders only a generated four-pixel line into a private Metal texture.
// No window, desktop content, or screen capture API participates in this check.
@MainActor enum FilterSubmissionProbe {
    static func run() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw failure("Metal is unavailable for the generated-line filter check.")
        }
        let width = 256, height = Int(GlowProfile.extent)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let data = bitmap.bitmapData else { throw failure("Cannot allocate the generated-line fixture.") }
        for index in 0..<(width * height) {
            let color: UInt8 = (126...129).contains(index % width) ? 0 : 255
            for channel in 0..<3 { data[index * 4 + channel] = color }
            data[index * 4 + 3] = 255
        }
        let view = ProgressiveBackdropView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let root = CALayer()
        root.frame = view.bounds
        root.actions = ["filters": NSNull()]
        root.contents = bitmap.cgImage
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
        var previous: NSObject?
        var previousRadius: Double?
        var results: [Int] = []
        for level in [0.0, 0.3, 0.55, 0.0] {
            view.profile = GlowHistory().frame(level: level, time: 1.7, reducedMotion: false)
            guard let filter = view.layer?.sublayers?.first?.filters?.first as? NSObject else {
                throw failure("The production backdrop did not publish its filter.")
            }
            if let previous {
                guard previous !== filter, previous.value(forKey: "inputRadius") as? Double == previousRadius else {
                    throw failure("A submitted filter was mutated in place. Core Animation keeps its cached zero-blur render value.")
                }
            }
            previous = filter
            previousRadius = filter.value(forKey: "inputRadius") as? Double
            root.filters = [filter]
            // Allow the renderer to retire the prior frame and submit the replacement.
            for _ in 0..<3 {
                CATransaction.flush()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                renderer.addUpdate(root.bounds)
                renderer.render()
                renderer.endFrame()
                guard let completion = queue.makeCommandBuffer() else { throw failure("Metal command submission failed.") }
                completion.commit()
                completion.waitUntilCompleted()
            }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let bottom = Int(pixels[(5 * width + 128) * 4])
            let aboveGlow = Int(pixels[((height - 5) * width + 128) * 4])
            guard aboveGlow < 5 else { throw failure("The variable filter blurred the generated line above the glow.") }
            results.append(bottom)
        }
        guard results[0] > 0, results[1] > results[0], results[2] > results[1], abs(results[3] - results[0]) <= 2 else {
            throw failure("Submitted filter updates did not render at meter 0/0.3/0.55/0: \(results).")
        }
        print("Generated-line rendering, meter 0/0.3/0.55/0, bottom line luminance \(results): PASS. Louder speech increases the blur. Upper line stays sharp. This is an offscreen filter test, not a cross-app visual check.")

        view.profile = GlowHistory().frame(level: 0.55, time: 1.7, reducedMotion: false)
        guard let glow = view.layer?.sublayers?.first(where: { $0.name == "speechBackgroundGlow" }) else {
            throw failure("The additive background glow is missing.")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.contents = nil
        root.filters = nil
        root.backgroundColor = CGColor(gray: 0.5, alpha: 1)
        root.addSublayer(glow)
        CATransaction.commit()
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(root.bounds)
        renderer.render()
        renderer.endFrame()
        guard let completion = queue.makeCommandBuffer() else { throw failure("Glow command submission failed.") }
        completion.commit()
        completion.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let bottom = (0..<3).map { Int(pixels[(5 * width + 128) * 4 + $0]) }
        let above = (0..<3).map { Int(pixels[((height - 5) * width + 128) * 4 + $0]) }
        guard glow.isHidden, bottom == above, above.max()! - above.min()! <= 1 else {
            throw failure("Legacy additive layer changed the Bottom sweep backdrop: \(bottom), \(above).")
        }
        print("Generated gray backdrop: legacy additive layer is disabled for Bottom, channels \(bottom): PASS")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "FilterSubmissionProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
