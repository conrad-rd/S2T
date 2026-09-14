import AppKit
import Metal
import S2TCore

// Generated stripes only. No window content or screen pixels are sampled.
@MainActor enum BezelRenderingProbe {
    static func run() throws {
        let size = BezelGeometry.size
        let width = Int(size.width), height = Int(size.height)
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
              let data = bitmap.bitmapData else { throw failure("Cannot create generated blur fixture.") }
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value: UInt8 = x % 8 < 4 ? 0 : 255
                for channel in 0..<3 { data[offset + channel] = value }
                data[offset + 3] = 255
            }
        }
        let view = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
        view.profile = GlowProfile(energy: 1, heights: [],
            bezel: BezelBackdrop(path: BezelGeometry.shape(form: .shown, side: .left).path))
        guard let sampler = view.layer?.sublayers?.first,
              let filter = sampler.filters?.first as? NSObject else { throw failure("Missing production bezel filter.") }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw failure("Cannot allocate generated render target.") }
        let root = CALayer()
        root.frame = view.bounds
        root.contents = bitmap.cgImage
        let filtered = CALayer()
        filtered.frame = root.bounds
        filtered.contents = bitmap.cgImage
        filtered.filters = [filter]
        filtered.opacity = sampler.opacity
        root.addSublayer(filtered)
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = root.bounds
        var contrasts: [[Int]] = []
        for enabled in [false, true] {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            filtered.isHidden = !enabled
            CATransaction.commit()
            for _ in 0..<3 {
                CATransaction.flush()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                renderer.addUpdate(root.bounds)
                renderer.render()
                renderer.endFrame()
                guard let completion = queue.makeCommandBuffer() else { throw failure("Cannot submit generated frame.") }
                completion.commit()
                completion.waitUntilCompleted()
            }
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&pixels, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            contrasts.append([56, 104, 184].map { start in
                let values = (start..<(start + 8)).map { Int(pixels[((height / 2) * width + $0) * 4]) }
                return values.max()! - values.min()!
            })
        }
        let before = contrasts[0], after = contrasts[1]
        guard before.allSatisfy({ $0 >= 254 }), after[0] >= 40, after[0] < Int(Double(before[0]) * 0.7),
              after[1] > after[0] + 15, after[2] > after[1] + 20, after[2] >= 250 else {
            throw failure("Rendered bezel blur lacks visible progressive softness. Stripe contrasts before/after: \(before), \(after).")
        }
        print("Generated native bezel filter: stripe contrast near/middle/outside \(before) → \(after), gradual visible blur with sharp exterior PASS.")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BezelRenderingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
