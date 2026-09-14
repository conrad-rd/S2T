import AppKit
import Metal
import SwiftUI
import S2TCore

@MainActor enum AppearancePreviewRenderingProbe {
    static func verify(frame: ChromaFrame, mode: GlowAppearance) throws {
        let size = frame.request.size
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw failure() }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw failure() }
        let view = AppearancePreviewBackdropView(frame: CGRect(origin: .zero, size: size))
        // A uniform white background cannot reveal blur. Use the authored forest fixture for this filter check.
        view.update(image: AppearancePreviewScene.background(mode == .aroundInput ? .bottom : mode), frame: frame)
        let canvas = ImageRenderer(content: ChromaFrameCanvas(frame: frame).frame(width: size.width, height: size.height))
        canvas.scale = 1
        guard let glow = canvas.cgImage else { throw failure() }
        let stage = CALayer(), background = CALayer(), color = CALayer()
        stage.frame = view.bounds
        background.frame = stage.bounds; color.frame = stage.bounds
        background.contents = view.layer?.contents
        color.contents = glow
        stage.addSublayer(background); stage.addSublayer(color)
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
        renderer.layer = stage; renderer.bounds = stage.bounds
        var sharp: [UInt8] = [], result: [UInt8] = []
        for enabled in [false, true] {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            background.filters = enabled ? view.layer?.filters : nil
            CATransaction.commit(); CATransaction.flush()
            for _ in 0..<3 {
                renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
                renderer.addUpdate(stage.bounds); renderer.render(); renderer.endFrame()
                let command = queue.makeCommandBuffer()!
                command.commit(); command.waitUntilCompleted()
            }
            result = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&result, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            if !enabled { sharp = result }
        }
        let changed = zip(sharp, result).filter { abs(Int($0) - Int($1)) > 2 }.count
        guard changed > 100 else { throw failure() }
        if let directory = ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32), let bytes = bitmap.bitmapData else { throw failure() }
            for y in 0..<height { for x in 0..<width {
                let source = (y * width + x) * 4, target = ((height - 1 - y) * width + x) * 4
                bytes[target] = result[source + 2]; bytes[target + 1] = result[source + 1]
                bytes[target + 2] = result[source]; bytes[target + 3] = result[source + 3]
            } }
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent("appearance-preview-\(mode.rawValue).png"))
        }
        print("PASS: \(mode.rawValue) native preview filter changes \(changed) generated color channels with the same glow overlay. No display content is sampled.")
    }
    private static func failure() -> NSError {
        NSError(domain: "AppearancePreviewRenderingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "The preview did not render its progressive background blur"])
    }
}
