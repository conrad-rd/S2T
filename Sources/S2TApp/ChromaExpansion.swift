import AppKit
import CoreImage
import Accelerate
import Metal
import ObjectiveC
import S2TCore

/// Resamples outward distance, keeping the physical notch and input boundary fixed.
enum ChromaExpansion {
    private final class Texture {
        let value: MTLTexture
        let bounds: CGRect
        init(_ value: MTLTexture, bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
            self.value = value; self.bounds = bounds
        }
    }
    private static let fields: NSCache<NSString, Texture> = cache(limit: 8)
    private static var sourceTextureKey: UInt8 = 0
    private final class Output {
        let texture: MTLTexture
        let buffer: MTLBuffer
        let rowBytes: Int
        init?(width: Int, height: Int) {
            guard let device else { return nil }
            let alignment = device.minimumLinearTextureAlignment(for: .rgba8Unorm)
            rowBytes = (width * 4 + alignment - 1) / alignment * alignment
            guard let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared) else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: rowBytes) else { return nil }
            self.buffer = buffer
            self.texture = texture
        }
    }
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
    private static let withinAssetsPipeline: MTLComputePipelineState? = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        float coverage(float value, float distance, float falloff) {
            if (falloff == 1) return value;
            float alpha = pow(saturate(value), falloff);
            return falloff < 1 ? alpha * (1 - smoothstep(0.65f, 1.0f, distance / 320)) : alpha;
        }
        float3 linearColor(float3 value) {
            return select(value / 12.92f, pow((value + 0.055f) / 1.055f, float3(2.4f)), value > 0.04045f);
        }
        float3 srgbColor(float3 value) {
            return select(value * 12.92f, 1.055f * pow(value, float3(1.0f / 2.4f)) - 0.055f, value > 0.0031308f);
        }
        kernel void withinAssets(texture2d<float, access::write> output [[texture(0)]],
                                 constant float4 &rect [[buffer(0)]], constant float4 &settings [[buffer(1)]],
                                 constant float2 &size [[buffer(2)]], constant uint &kind [[buffer(3)]],
                                 uint2 pixel [[thread_position_in_grid]]) {
            if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
            float2 p = (float2(pixel) + 0.5f) / float2(output.get_width(), output.get_height()) * size;
            float radius = settings.x, power = settings.y, falloff = settings.z, expansion = settings.w;
            float extent = kind == 1 ? 32 * max(0.000001f, expansion) : 128;
            float2 low = float2(rect.x - 36, rect.y + rect.w - extent - 16 - radius);
            float2 high = float2(rect.x + rect.z + 36, rect.y + rect.w + 16);
            // Match the CPU field's pixel-aligned generation bounds.
            float2 density = float2(output.get_width(), output.get_height()) / size;
            if (any(float2(pixel) < floor(low * density)) || any(float2(pixel) >= ceil(high * density))) {
                output.write(float4(0), pixel); return;
            }
            float corner = radius > 0 ? saturate((abs(p.x - rect.x - rect.z * 0.5f) - rect.z * 0.5f + radius) / radius) : 0;
            float edge = rect.y + rect.w - radius + radius * pow(max(0.0f, 1 - pow(corner, power)), 1 / power);
            float distance = edge - p.y;
            if (kind == 1 && (distance < -1 || distance > extent || expansion <= 0)) {
                output.write(float4(0), pixel); return;
            }
            float x = saturate((p.x - rect.x) / rect.z);
            float lateral = pow(max(0.0f, sin(M_PI_F * x)), 0.48f);
            float3 a, b; float t;
            if (x <= 0.33f) { a = float3(142, 0, 255); b = float3(0, 93, 255); t = x / 0.33f; }
            else if (x <= 0.83f) { a = float3(0, 93, 255); b = float3(253, 90, 189); t = (x - 0.33f) / 0.5f; }
            else { a = float3(253, 90, 189); b = float3(255, 0, 250); t = (x - 0.83f) / 0.17f; }
            float3 color = srgbColor(linearColor(mix(a, b, t) / 255) * 0.91f + 0.09f);
            float d = max(0.0f, distance) / (0.4f * (kind == 1 ? max(0.000001f, expansion) : 1));
            float body = saturate(0.52f * pow(max(0.0f, 1 - d / 310), 3.0f) * lateral * 1.08f);
            float alpha;
            if (kind == 1) {
                float rim = saturate(max(body, 0.98f * exp(-max(0.0f, d - 5) / 15) * lateral * 1.35f));
                alpha = body < 1 ? (rim - body) / (1 - body) : 0;
            } else if (kind == 2) {
                float blur = coverage(pow(max(0.0f, 1 - d / 265), 2.3f) * lateral, d, falloff);
                alpha = 0.6f * sqrt(saturate(blur)) * smoothstep(0.0f, 1.0f, (320 - d) / 64);
                color = float3(0);
            } else {
                float lift = saturate(0.20f * pow(max(0.0f, 1 - d / 320), 1.2f) * min(1.0f, d / 24) * lateral * 1.08f);
                alpha = body + lift * (1 - body);
                color = alpha > 0 ? (color * body + lift * (1 - body)) / alpha : float3(0);
                alpha = coverage(alpha, d, falloff);
            }
            float spread = 36 * smoothstep(0.0f, 1.0f, (rect.y + 64 - p.y) / 96);
            float side = min(p.x - rect.x + spread, rect.x + rect.z + spread - p.x);
            alpha *= smoothstep(0.0f, 1.0f, (side + 4) / max(10.0f, radius * 0.6f));
            alpha = round(saturate(alpha) * 255) / 255;
            color = round(saturate(color) * 255) / 255;
            output.write(float4(color * alpha, alpha), pixel);
        }
        """
        guard let device, let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "withinAssets") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    static func withinAssets(contour: InputContour, size: CGSize, falloff: Double, edgeExpansion: Double) -> ChromaAppearance.Assets? {
        guard let pipeline = withinAssetsPipeline, let command = queue?.makeCommandBuffer() else { return nil }
        let main = contour.main, r = min(main.radius, min(main.rect.width, main.rect.height) / 2)
        var rect = SIMD4<Float>(Float(main.rect.minX), Float(main.rect.minY), Float(main.rect.width), Float(main.rect.height))
        var settings = SIMD4<Float>(Float(r), main.style == .circular || r >= main.rect.height / 2 ? 2 : 2.8,
            Float(falloff), Float(edgeExpansion))
        var dimensions = SIMD2<Float>(Float(size.width), Float(size.height))
        var outputs = [Output]()
        for index in 0..<3 {
            let scale = index == 1 ? 2.0 : 1.0
            guard let output = Output(width: max(2, Int(ceil(size.width * scale))), height: max(2, Int(ceil(size.height * scale)))),
                  let encoder = command.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(output.texture, index: 0)
            encoder.setBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setBytes(&dimensions, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            var kind = UInt32(index)
            encoder.setBytes(&kind, length: MemoryLayout<UInt32>.stride, index: 3)
            let width = pipeline.threadExecutionWidth
            encoder.dispatchThreads(MTLSize(width: output.texture.width, height: output.texture.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1))
            encoder.endEncoding()
            outputs.append(output)
        }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let images = outputs.compactMap { outputImage($0, size: size) }
        guard images.count == 3 else { return nil }
        return ChromaAppearance.Assets(color: images[0], edge: images[1], radius: images[2])
    }
    private static let resizePipeline: MTLComputePipelineState? = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void resizeInput(texture2d<float, access::sample> source [[texture(0)]],
                                texture2d<float, access::write> output [[texture(1)]],
                                constant float4 &cuts [[buffer(0)]], constant float2 &heights [[buffer(1)]],
                                uint2 pixel [[thread_position_in_grid]]) {
            if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
            float2 uv = (float2(pixel) + 0.5) / float2(output.get_width(), output.get_height());
            float y = uv.y * heights.y;
            float sourceY = y <= cuts.z ? y + cuts.x - cuts.z : y >= cuts.w ? y + cuts.y - cuts.w
                : mix(cuts.x, cuts.y, (y - cuts.z) / (cuts.w - cuts.z));
            constexpr sampler sampling(coord::normalized, address::clamp_to_zero, filter::linear);
            output.write(source.sample(sampling, float2(uv.x, sourceY / heights.x)), pixel);
        }
        """
        guard let device, let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "resizeInput") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    static func resize(_ images: [NSImage], from oldSize: CGSize, to size: CGSize, mapping: InputHeightResize) -> [NSImage]? {
        guard oldSize.width == size.width, let command = queue?.makeCommandBuffer() else { return nil }
        var outputs = [Output]()
        for image in images {
            guard let source = texture(image),
                  let output = Output(width: source.value.width, height: Int(ceil(Double(source.value.height) / oldSize.height * size.height))),
                  encodeResize(source.value, into: output.texture, oldSize: oldSize, size: size, mapping: mapping, command: command) else { return nil }
            outputs.append(output)
        }
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let result = outputs.compactMap { outputImage($0, size: size) }
        return result.count == images.count ? result : nil
    }

    private static func encodeResize(_ source: MTLTexture, into output: MTLTexture, oldSize: CGSize, size: CGSize,
                                     mapping: InputHeightResize, command: MTLCommandBuffer) -> Bool {
        guard let pipeline = resizePipeline, let encoder = command.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(output, index: 1)
        var cuts = SIMD4<Float>(Float(mapping.sourceStart), Float(mapping.sourceEnd), Float(mapping.targetStart), Float(mapping.targetEnd))
        var heights = SIMD2<Float>(Float(oldSize.height), Float(size.height))
        encoder.setBytes(&cuts, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setBytes(&heights, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        let width = pipeline.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1))
        encoder.endEncoding()
        return true
    }
    private static let pipeline: MTLComputePipelineState? = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        float lowerEdge(float x, float4 rect, float2 shape) {
            if (shape.x <= 0) return rect.y + rect.w;
            float corner = saturate((abs(x - rect.x - rect.z * 0.5f) - rect.z * 0.5f + shape.x) / shape.x);
            return rect.y + rect.w - shape.x + shape.x * pow(max(0.0f, 1 - pow(corner, shape.y)), 1 / shape.y);
        }
        kernel void expandGlow(texture2d<float, access::sample> source [[texture(0)]],
                               texture2d<float, access::sample> vectors [[texture(1)]],
                               texture2d<float, access::write> output [[texture(2)]],
                               constant float3 &parameters [[buffer(0)]], constant float4 &bounds [[buffer(1)]],
                               constant float4 &inputRect [[buffer(2)]], constant float2 &inputShape [[buffer(3)]],
                               uint2 pixel [[thread_position_in_grid]]) {
            if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
            if (parameters.z == 0.0) { output.write(float4(0.0), pixel); return; }
            constexpr sampler fieldSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            constexpr sampler imageSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            float2 point = (float2(pixel) + 0.5) / float2(output.get_width(), output.get_height());
            if (any(point < bounds.xy) || any(point > bounds.zw)) { output.write(float4(0.0), pixel); return; }
            float2 outward;
            if (inputRect.z > 0) {
                // Match the original 2x vector grid and its bilinear sampling.
                float2 gridSize = ceil(parameters.xy * 2);
                float2 grid = point * gridSize - 0.5f;
                float2 start = floor(grid), weight = fract(grid);
                outward = float2(0);
                for (uint y = 0; y < 2; ++y) for (uint x = 0; x < 2; ++x) {
                    float2 position = (clamp(start + float2(x, y), float2(0), gridSize - 1) + 0.5f) / gridSize * parameters.xy;
                    float edge = lowerEdge(position.x, inputRect, inputShape);
                    float dx = lowerEdge(position.x + 0.1f, inputRect, inputShape) - lowerEdge(position.x - 0.1f, inputRect, inputShape);
                    float2 normal = normalize(float2(dx, -0.2f));
                    outward += normal * max(0.0f, edge - position.y) * (x == 0 ? 1 - weight.x : weight.x) * (y == 0 ? 1 - weight.y : weight.y);
                }
            } else { outward = vectors.sample(fieldSampler, point).rg; }
            float2 origin = point + outward * (1.0 / parameters.z - 1.0) / parameters.xy;
            float4 color = any(origin < 0.0) || any(origin > 1.0) ? float4(0.0) : source.sample(imageSampler, origin);
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
        if case .input = geometry { _ = resizePipeline }
        if abs(factor - 1) < 0.000001 { return images }
        let keys = images.map { "\(ObjectIdentifier($0))-\(geometry)-\(size)" as NSString }
        let cached = keys.map { expanded.object(forKey: $0) }
        if cached.allSatisfy({ $0?.factor == factor }) { return cached.compactMap { $0?.result } }
        guard factor >= 0, let pipeline, let command = queue?.makeCommandBuffer() else { return nil }
        var inputRect = SIMD4<Float>.zero, inputShape = SIMD2<Float>.zero
        let vectors: MTLTexture?
        if case let .withinInput(contour) = geometry {
            let rect = contour.main.rect, radius = min(contour.main.radius, min(rect.width, rect.height) / 2)
            inputRect = SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
            inputShape = SIMD2(Float(radius), contour.main.style == .circular || radius >= rect.height / 2 ? 2 : 2.8)
            vectors = nil
        } else {
            vectors = field(geometry: geometry, size: size)
            guard vectors != nil else { return nil }
        }
        var results: [Output] = []
        for image in images {
            guard let source = texture(image), let output = Output(width: source.value.width, height: source.value.height),
                  let encoder = command.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(source.value, index: 0)
            encoder.setTexture(vectors ?? source.value, index: 1)
            encoder.setTexture(output.texture, index: 2)
            var parameters = SIMD3<Float>(Float(size.width), Float(size.height), Float(factor))
            encoder.setBytes(&parameters, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
            var bounds = SIMD4<Float>(0, 0, 1, 1)
            if case let .input(contour) = geometry, factor <= 1 {
                let field = CGRect(x: contour.bounds.minX / size.width, y: contour.bounds.minY / size.height,
                    width: contour.bounds.width / size.width, height: contour.bounds.height / size.height)
                let support = source.bounds.union(field)
                bounds = SIMD4(Float(support.minX), Float(support.minY), Float(support.maxX), Float(support.maxY))
            }
            encoder.setBytes(&bounds, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.setBytes(&inputRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.setBytes(&inputShape, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
            let width = pipeline.threadExecutionWidth
            encoder.dispatchThreads(MTLSize(width: output.texture.width, height: output.texture.height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1))
            encoder.endEncoding()
            results.append(output)
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let rendered = results.compactMap { outputImage($0, size: size) }
        guard rendered.count == images.count else { return nil }
        for index in images.indices {
            let texture = results[index].texture
            expanded.setObject(Expansion(source: images[index], factor: factor, result: rendered[index]),
                forKey: keys[index], cost: texture.width * texture.height * 4)
        }
        return rendered
    }

    private static func outputImage(_ output: Output, size: CGSize) -> NSImage? {
        let texture = output.texture
        // The image owns the shared GPU storage until its last drawing consumer releases it.
        let owner = Unmanaged.passRetained(output).toOpaque()
        guard let provider = CGDataProvider(dataInfo: owner, data: output.buffer.contents(),
            size: output.buffer.length, releaseData: { owner, _, _ in
                if let owner { Unmanaged<Output>.fromOpaque(owner).release() }
            }) else { Unmanaged<Output>.fromOpaque(owner).release(); return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: output.rowBytes, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let result = NSImage(cgImage: image, size: size)
        objc_setAssociatedObject(result, &sourceTextureKey, Texture(texture), .OBJC_ASSOCIATION_RETAIN)
        return result
    }

    private static let textureLock = NSLock()

    // There are only 256 × 256 possible byte/alpha pairs. Preserve the exact
    // Float premultiplication and half rounding without allocating a full Float
    // image or launching a parallel vImage conversion for every new geometry.
    private static let premultipliedHalf: [UInt16] = halfTable((0..<65536).map { value in
        Float(value & 255) / 255 * (Float(value >> 8) / 255)
    })
    private static let normalizedHalf: [UInt16] = halfTable((0..<256).map { Float($0) / 255 })

    // Accelerate supports half conversion on Intel as well as Apple Silicon.
    // Convert only these cached lookup tables, never a full image per frame.
    private static func halfTable(_ values: [Float]) -> [UInt16] {
        var result = [UInt16](repeating: 0, count: values.count)
        values.withUnsafeBytes { source in
            result.withUnsafeMutableBytes { destination in
                var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                    height: 1, width: vImagePixelCount(values.count), rowBytes: source.count)
                var output = vImage_Buffer(data: destination.baseAddress!,
                    height: 1, width: vImagePixelCount(values.count), rowBytes: destination.count)
                precondition(vImageConvert_PlanarFtoPlanar16F(&input, &output,
                    vImage_Flags(kvImageNoFlags)) == kvImageNoError)
            }
        }
        return result
    }

    @discardableResult static func prepareSource(_ image: NSImage) -> MTLTexture? { texture(image)?.value }

    static func filterImage(_ image: NSImage) -> CIImage? {
        guard let source = objc_getAssociatedObject(image, &sourceTextureKey) as? Texture,
              source.value.pixelFormat == .rgba8Unorm,
              let image = CIImage(mtlTexture: source.value, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!]) else { return nil }
        return image.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: image.extent.height))
    }

    private static func texture(_ image: NSImage) -> Texture? {
        textureLock.lock()
        defer { textureLock.unlock() }
        if let cached = objc_getAssociatedObject(image, &sourceTextureKey) as? Texture { return cached }
        guard let bitmap = image.representations.first as? NSBitmapImageRep,
              bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4, !bitmap.isPlanar,
              !bitmap.bitmapFormat.contains(.alphaFirst), let bytes = bitmap.bitmapData,
              let texture = makeTexture(width: bitmap.pixelsWide, height: bitmap.pixelsHigh, format: .rgba16Float) else { return nil }
        let straightAlpha = bitmap.bitmapFormat.contains(.alphaNonpremultiplied)
        let rowBytes = bitmap.bytesPerRow
        let width = texture.width, height = texture.height
        var halfPixels = [UInt16](repeating: 0, count: width * height * 4)
        var minX = texture.width, minY = texture.height, maxX = 0, maxY = 0
        let table = straightAlpha ? premultipliedHalf : normalizedHalf
        for y in 0..<height { for x in 0..<width {
            let i = y * rowBytes + x * 4
            let alpha = Int(bytes[i + 3])
            if alpha > 0 { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x + 1); maxY = max(maxY, y + 1) }
            let offset = straightAlpha ? alpha << 8 : 0
            let destination = (y * width + x) * 4
            halfPixels[destination] = table[offset + Int(bytes[i])]
            halfPixels[destination + 1] = table[offset + Int(bytes[i + 1])]
            halfPixels[destination + 2] = table[offset + Int(bytes[i + 2])]
            halfPixels[destination + 3] = normalizedHalf[alpha]
        } }
        // Filter premultiplied color; half precision keeps faint tails from losing their hue.
        halfPixels.withUnsafeBytes { halfBytes in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                withBytes: halfBytes.baseAddress!, bytesPerRow: width * 8)
        }
        let bounds = CGRect(x: Double(minX - 1) / Double(texture.width), y: Double(minY - 1) / Double(texture.height),
            width: Double(max(0, maxX - minX) + 2) / Double(texture.width),
            height: Double(max(0, maxY - minY) + 2) / Double(texture.height))
        let result = Texture(texture, bounds: bounds)
        objc_setAssociatedObject(image, &sourceTextureKey, result, .OBJC_ASSOCIATION_RETAIN)
        return result
    }

    private static func makeTexture(width: Int, height: Int, format: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        return device?.makeTexture(descriptor: descriptor)
    }

    // A 2x field can exceed NSCache's entire budget. Keep just the current
    // geometry alive so every speech frame does not rebuild the same texture.
    private static let activeFieldLock = NSLock()
    private static var activeField: (key: NSString, texture: MTLTexture)?

    private static func retainField(_ texture: MTLTexture, key: NSString) {
        activeFieldLock.lock(); activeField = (key, texture); activeFieldLock.unlock()
    }

    private static let inputFieldLock = NSLock()
    private static var inputField: (contour: InputContour, size: CGSize, texture: MTLTexture)?

    static func field(geometry: ChromaAppearance.Geometry, size: CGSize) -> MTLTexture? {
        let key = "\(geometry)-\(size)" as NSString
        activeFieldLock.lock()
        let current = activeField?.key == key ? activeField?.texture : nil
        activeFieldLock.unlock()
        if let current { return current }
        if let field = fields.object(forKey: key) {
            retainField(field.value, key: key)
            return field.value
        }
        let width = max(2, Int(ceil(size.width * 2))), height = max(2, Int(ceil(size.height * 2)))
        if case let .input(contour) = geometry {
            inputFieldLock.lock(); let previous = inputField; inputFieldLock.unlock()
            if let previous, previous.size.width == size.width,
               let mapping = InputHeightResize(source: previous.contour, target: contour),
               let texture = makeTexture(width: width, height: height, format: .rg32Float),
               let command = queue?.makeCommandBuffer(),
               encodeResize(previous.texture, into: texture, oldSize: previous.size, size: size, mapping: mapping, command: command) {
                command.commit(); command.waitUntilCompleted()
                if command.status == .completed {
                    fields.setObject(Texture(texture), forKey: key, cost: width * height * 8)
                    retainField(texture, key: key)
                    return texture
                }
            }
        }
        var values = [SIMD2<Float>](repeating: .zero, count: width * height)
        let input: ChromaInputBoundary?
        if case let .input(contour) = geometry { input = ChromaInputBoundary(contour: contour) }
        else { input = nil }
        if case let .withinInput(contour) = geometry {
            let field = WithinInputField(contour: contour)
            let columns = (0..<width).map { x -> (Double, Double, Double) in
                let px = (Double(x) + 0.5) / Double(width) * size.width
                let edge = field.lowerEdge(at: px)
                let dx = field.lowerEdge(at: px + 0.1) - field.lowerEdge(at: px - 0.1)
                let length = hypot(dx, 0.2)
                return (edge, dx / length, -0.2 / length)
            }
            // distance(x,y) = lowerEdge(x) - y. Its x derivative is identical
            // for every row and its y derivative is constant.
            for y in 0..<height {
                let py = (Double(y) + 0.5) / Double(height) * size.height
                for x in 0..<width {
                    let (edge, dx, dy) = columns[x]
                    let distance = max(0, edge - py)
                    values[y * width + x] = SIMD2(Float(dx * distance), Float(dy * distance))
                }
            }
        } else {
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
        }
        guard let texture = makeTexture(width: width, height: height, format: .rg32Float) else { return nil }
        values.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: $0.baseAddress!, bytesPerRow: width * MemoryLayout<SIMD2<Float>>.stride) }
        fields.setObject(Texture(texture), forKey: key, cost: values.count * MemoryLayout<SIMD2<Float>>.stride)
        retainField(texture, key: key)
        if case let .input(contour) = geometry {
            inputFieldLock.lock(); inputField = (contour, size, texture); inputFieldLock.unlock()
        }
        return texture
    }
}
