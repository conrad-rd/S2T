import CoreGraphics
import Metal

enum ProcessingBoundaryDepth {
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    private static let pipeline: MTLComputePipelineState? = {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void boundaryDepth(const device float4 *edges [[buffer(0)]],
                                  device float *output [[buffer(1)]], constant uint3 &grid [[buffer(2)]],
                                  constant float2 &size [[buffer(3)]], constant float4 &bounds [[buffer(4)]],
                                  uint2 pixel [[thread_position_in_grid]]) {
            if (pixel.x >= grid.x || pixel.y >= grid.y) return;
            float2 point = (float2(pixel) + 0.5f) / float2(grid.xy) * size;
            bool inside = false;
            for (uint i = 0; i < grid.z; ++i) {
                float4 edge = edges[i];
                if ((edge.y > point.y) != (edge.y + edge.w > point.y)
                    && point.x < edge.x + (point.y - edge.y) * edge.z / edge.w) inside = !inside;
            }
            float rectangle = min(min(point.x - bounds.x, bounds.z - point.x), min(point.y - bounds.y, bounds.w - point.y));
            float nearest = inside ? rectangle * rectangle : INFINITY;
            for (uint i = 0; i < grid.z; ++i) {
                float4 edge = edges[i];
                float2 low = min(edge.xy, edge.xy + edge.zw), high = max(edge.xy, edge.xy + edge.zw);
                float2 separation = max(float2(0), max(low - point, point - high));
                if (dot(separation, separation) >= nearest) continue;
                float2 delta = point - edge.xy;
                float t = saturate(dot(delta, edge.zw) / dot(edge.zw, edge.zw));
                float2 offset = delta - t * edge.zw;
                nearest = min(nearest, dot(offset, offset));
            }
            output[pixel.y * grid.x + pixel.x] = sqrt(nearest) * (inside ? 1 : -1);
        }
        """
        guard let device, let library = try? device.makeLibrary(source: source, options: nil),
              let function = library.makeFunction(name: "boundaryDepth") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }()

    static func render(edges: [SIMD4<Float>], bounds: CGRect, width: Int, height: Int, size: CGSize) -> [Float]? {
        guard !edges.isEmpty, let device, let pipeline,
              let source = edges.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let output = device.makeBuffer(length: width * height * MemoryLayout<Float>.stride, options: .storageModeShared),
              let command = queue?.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return nil }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(source, offset: 0, index: 0)
        encoder.setBuffer(output, offset: 0, index: 1)
        var grid = SIMD3<UInt32>(UInt32(width), UInt32(height), UInt32(edges.count))
        var dimensions = SIMD2<Float>(Float(size.width), Float(size.height))
        var box = SIMD4<Float>(Float(bounds.minX), Float(bounds.minY), Float(bounds.maxX), Float(bounds.maxY))
        encoder.setBytes(&grid, length: MemoryLayout<SIMD3<UInt32>>.stride, index: 2)
        encoder.setBytes(&dimensions, length: MemoryLayout<SIMD2<Float>>.stride, index: 3)
        encoder.setBytes(&box, length: MemoryLayout<SIMD4<Float>>.stride, index: 4)
        let threads = pipeline.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threads, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / threads), depth: 1))
        encoder.endEncoding()
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        return Array(UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: Float.self), count: width * height))
    }
}
