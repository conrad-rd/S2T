import AppKit
import Accelerate
import Metal
import S2TCore

/// Resamples outward distance, keeping the physical notch and input boundary fixed.
enum ChromaExpansion {
    private final class Texture {
        let value: MTLTexture
        let source: NSImage?
        init(_ value: MTLTexture, source: NSImage? = nil) { self.value = value; self.source = source }
    }
    private static let fields: NSCache<NSString, Texture> = cache(limit: 8)
    private static let sources: NSCache<NSString, Texture> = cache(limit: 32)
    private static func cache(limit: Int) -> NSCache<NSString, Texture> {
        let cache = NSCache<NSString, Texture>()
        cache.countLimit = limit
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }
    private final class Expansion {
        let source: NSImage
        let factor: Double
        let result: NSImage
        init(source: NSImage, factor: Double, result: NSImage) {
            self.source = source; self.factor = factor; self.result = result
        }
    }
    private static let expanded: NSCache<NSString, Expansion> = {
        let cache = NSCache<NSString, Expansion>()
        cache.countLimit = 16
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    private static let pipeline: MTLComputePipelineState? = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void expandGlow(texture2d<float, access::sample> source [[texture(0)]],
                               texture2d<float, access::sample> vectors [[texture(1)]],
                               texture2d<float, access::write> output [[texture(2)]],
                               constant float3 &parameters [[buffer(0)]], uint2 pixel [[thread_position_in_grid]]) {
            if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
            if (parameters.z == 0.0) { output.write(float4(0.0), pixel); return; }
            constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            constexpr sampler imageSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            float2 point = (float2(pixel) + 0.5) / float2(output.get_width(), output.get_height());
            float2 outward = vectors.sample(fieldSampler, point).rg;
            float2 origin = point + outward * (1.0 / parameters.z - 1.0) / parameters.xy;
            float4 color = any(origin < 0.0) || any(origin > 1.0) ? float4(0.0) : source.sample(imageSampler, origin);
            color.rgb = color.a > 0.0 ? color.rgb / color.a : float3(0.0);
            output.write(color, pixel);
        }
        """
        guard let device, let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "expandGlow") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    static func image(_ image: NSImage, geometry: ChromaAppearance.Geometry, size: CGSize, factor: Double) -> NSImage? {
        images([image], geometry: geometry, size: size, factor: factor)?.first
    }

    static func images(_ images: [NSImage], geometry: ChromaAppearance.Geometry, size: CGSize, factor: Double) -> [NSImage]? {
        if abs(factor - 1) < 0.000001 { return images }
        let keys = images.map { "\(ObjectIdentifier($0))-\(geometry)-\(size)" as NSString }
        let cached = keys.map { expanded.object(forKey: $0) }
        if cached.allSatisfy({ $0?.factor == factor }) { return cached.compactMap { $0?.result } }
        guard factor >= 0, let pipeline, let command = queue?.makeCommandBuffer(),
              let vectors = field(geometry: geometry, size: size) else { return nil }
        var results: [MTLTexture] = []
        for image in images {
            guard let source = texture(image), let output = makeTexture(width: source.width, height: source.height, format: .rgba8Unorm),
                  let encoder = command.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(vectors, index: 1)
            encoder.setTexture(output, index: 2)
            var parameters = SIMD3<Float>(Float(size.width), Float(size.height), Float(factor))
            encoder.setBytes(&parameters, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
            let width = pipeline.threadExecutionWidth
            encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1))
            encoder.endEncoding()
            results.append(output)
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let rendered = results.compactMap { texture -> NSImage? in
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: texture.width, pixelsHigh: texture.height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bitmapFormat: .alphaNonpremultiplied, bytesPerRow: texture.width * 4, bitsPerPixel: 32),
                let bytes = bitmap.bitmapData else { return nil }
            texture.getBytes(bytes, bytesPerRow: bitmap.bytesPerRow,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
            bitmap.size = size
            let result = NSImage(size: size)
            result.addRepresentation(bitmap.retagging(with: .sRGB) ?? bitmap)
            return result
        }
        guard rendered.count == images.count else { return nil }
        for index in images.indices {
            let texture = results[index]
            expanded.setObject(Expansion(source: images[index], factor: factor, result: rendered[index]),
                forKey: keys[index], cost: texture.width * texture.height * 4)
        }
        return rendered
    }

    private static func texture(_ image: NSImage) -> MTLTexture? {
        let key = String(describing: ObjectIdentifier(image)) as NSString
        if let cached = sources.object(forKey: key) { return cached.value }
        guard let bitmap = image.representations.first as? NSBitmapImageRep,
              bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4, !bitmap.isPlanar,
              !bitmap.bitmapFormat.contains(.alphaFirst), let bytes = bitmap.bitmapData,
              let texture = makeTexture(width: bitmap.pixelsWide, height: bitmap.pixelsHigh, format: .rgba16Float) else { return nil }
        let straightAlpha = bitmap.bitmapFormat.contains(.alphaNonpremultiplied)
        var pixels = [Float](repeating: 0, count: texture.width * texture.height * 4)
        for y in 0..<texture.height { for x in 0..<texture.width {
            let i = y * bitmap.bytesPerRow + x * 4
            let alpha = Float(bytes[i + 3]) / 255
            let gain = straightAlpha ? alpha : 1
            let destination = (y * texture.width + x) * 4
            pixels[destination] = Float(bytes[i]) / 255 * gain
            pixels[destination + 1] = Float(bytes[i + 1]) / 255 * gain
            pixels[destination + 2] = Float(bytes[i + 2]) / 255 * gain
            pixels[destination + 3] = alpha
        } }
        // Filter premultiplied color; half precision keeps faint tails from losing their hue.
        let converted = pixels.withUnsafeMutableBytes { bytes -> Bool in
            var source = vImage_Buffer(data: bytes.baseAddress!, height: vImagePixelCount(texture.height),
                width: vImagePixelCount(texture.width * 4), rowBytes: texture.width * 4 * MemoryLayout<Float>.stride)
            var destination = vImage_Buffer(data: bytes.baseAddress!, height: source.height,
                width: source.width, rowBytes: texture.width * 4 * MemoryLayout<UInt16>.stride)
            guard vImageConvert_PlanarFtoPlanar16F(&source, &destination, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return false }
            texture.replace(region: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: destination.rowBytes)
            return true
        }
        guard converted else { return nil }
        sources.setObject(Texture(texture, source: image), forKey: key, cost: texture.width * texture.height * 8)
        return texture
    }

    private static func makeTexture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device?.makeTexture(descriptor: descriptor)
    }

    private static func field(geometry: ChromaAppearance.Geometry, size: CGSize) -> MTLTexture? {
        let key = "\(geometry)-\(size)" as NSString
        if let field = fields.object(forKey: key) { return field.value }
        let width = max(2, Int(ceil(size.width * 2))), height = max(2, Int(ceil(size.height * 2)))
        var values = [SIMD2<Float>](repeating: .zero, count: width * height)
        let input: ChromaInputBoundary?
        if case let .input(rect, radius, cornerStyle) = geometry { input = ChromaInputBoundary(rect: rect, radius: radius, cornerStyle: cornerStyle) }
        else { input = nil }
        for y in 0..<height {
            for x in 0..<width {
                let point = CGPoint(x: (Double(x) + 0.5) / Double(width) * size.width,
                                    y: (Double(y) + 0.5) / Double(height) * size.height)
                let vector: CGPoint
                if let input { vector = input.outwardVector(point) }
                else if case .bottom = geometry { vector = CGPoint(x: 0, y: point.y - size.height) }
                else {
                    let d = max(0, geometry.distance(point, size: size))
                    let dx = geometry.distance(CGPoint(x: point.x + 0.1, y: point.y), size: size)
                        - geometry.distance(CGPoint(x: point.x - 0.1, y: point.y), size: size)
                    let dy = geometry.distance(CGPoint(x: point.x, y: point.y + 0.1), size: size)
                        - geometry.distance(CGPoint(x: point.x, y: point.y - 0.1), size: size)
                    let length = hypot(dx, dy)
                    vector = length > 0 ? CGPoint(x: dx * d / length, y: dy * d / length) : .zero
                }
                values[y * width + x] = SIMD2(Float(vector.x), Float(vector.y))
            }
        }
        guard let texture = makeTexture(width: width, height: height, format: .rg32Float) else { return nil }
        values.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: width * MemoryLayout<SIMD2<Float>>.stride) }
        fields.setObject(Texture(texture), forKey: key, cost: values.count * MemoryLayout<SIMD2<Float>>.stride)
        return texture
    }
}
