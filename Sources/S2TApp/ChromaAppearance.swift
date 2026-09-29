import AppKit
import CoreImage
import SwiftUI
import S2TCore

/// Native fields from the approved Brighter edge study; desktop blur remains WindowServer-composed.
enum ChromaAppearance {
    enum Geometry: Equatable {
        case bottom
        case windowBottom(WindowBottomLayout)
        case input(InputContour)
        case withinInput(InputContour)
        static func input(_ rect: CGRect, _ radius: CGFloat, _ style: InputCornerStyle = .continuous) -> Self {
            .input(InputContour(rect: rect, radius: radius, style: style))
        }
        case notch(TopGlowLayout)

        var appearance: GlowAppearance {
            switch self { case .bottom, .windowBottom: return .bottom; case .input: return .aroundInput; case .withinInput: return .withinInput; case .notch: return .aroundNotch }
        }
        var preset: ChromaPreset {
            switch self { case .bottom, .windowBottom: return .bottom; case .input, .withinInput: return .box; case .notch: return .notch }
        }
        var mode: BrighterEdgeStyle.Mode {
            switch self { case .bottom, .windowBottom: return .bottom; case .input: return .input; case .withinInput: return .bottom; case .notch: return .notch }
        }
        var referenceScale: Double {
            switch self {
            case .bottom, .windowBottom: return 1
            case .withinInput: return 0.22
            case let .input(contour): return min(1, max(0.25, contour.main.rect.width / 940))
            case let .notch(layout):
                return min(1, max(0.25, layout.notch.map { $0.width / 411.25 } ?? layout.frame.width / 1080))
            }
        }
        // Shared controls use screen points, independent of input width or notch size.
        var fieldScale: Double { 0.4 * mode.fieldScale }
        // Kept low so the background only softens near the glow instead of washing out.
        var maximumBlurRadius: Double { 5 }

        func referencePoint(_ p: CGPoint, size: CGSize) -> CGPoint {
            switch self {
            case .bottom, .windowBottom: return CGPoint(x: p.x / size.width * 1080, y: 1080 - (size.height - p.y))
            case let .withinInput(contour):
                return CGPoint(x: (p.x - contour.main.rect.minX) / contour.main.rect.width * 1080, y: 1080)
            case let .input(contour):
                let rect = contour.bounds
                return CGPoint(x: (p.x - rect.minX) / rect.width * 1080,
                               y: (p.y - rect.midY) / rect.height * 300 + 540)
            case let .notch(layout):
                let bounds = NotchAura.paletteBounds(layout: layout)
                return CGPoint(x: (p.x - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound) * 1080,
                               y: 360 + p.y / referenceScale)
            }
        }

        func distance(_ p: CGPoint, size: CGSize) -> Double {
            switch self {
            case .bottom: return size.height - p.y
            case let .windowBottom(layout): return layout.distance(at: p)
            case let .withinInput(contour): return WithinInputField(contour: contour).distance(p)
            case let .notch(layout): return layout.distance(at: p)
            case let .input(contour):
                func distance(to part: InputContour.Part) -> Double {
                    let radius = part.corners == .top && p.y > part.rect.midY || part.corners == .bottom && p.y < part.rect.midY ? 0 : part.radius
                    let exponent = part.style == .circular || radius >= part.rect.height / 2 ? 2.0 : 2.8
                    let x = abs(p.x - part.rect.midX) - part.rect.width / 2 + radius
                    let y = abs(p.y - part.rect.midY) - part.rect.height / 2 + radius
                    return pow(pow(max(0, x), exponent) + pow(max(0, y), exponent), 1 / exponent)
                        + min(max(x, y), 0) - radius
                }
                var nearest = distance(to: contour.main)
                for bar in contour.bars { nearest = min(nearest, distance(to: bar)) }
                return nearest
            }
        }
    }

    final class Assets {
        let color, edge, radius: NSImage
        init(color: NSImage, edge: NSImage, radius: NSImage) {
            self.color = color; self.edge = edge; self.radius = radius
        }
    }

    private static let cache: NSCache<NSString, Assets> = {
        let cache = NSCache<NSString, Assets>()
        cache.countLimit = 8
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    // A padded four-sample input rim can exceed the cache budget by itself.
    // Keep the current working set alive even when NSCache declines to retain it.
    private static let activeAssetsLock = NSLock()
    private static var activeAssets: (key: NSString, value: Assets)?
    private static var inputAssets: (contour: InputContour, size: CGSize, falloff: Double, edgeExpansion: Double, value: Assets)?

    static func assets(geometry: Geometry, size: CGSize, falloff: Double = 1, edgeExpansion: Double = 1, useCache: Bool = true) -> Assets? {
        let key = "\(geometry)-\(size)-\(falloff)-\(edgeExpansion)" as NSString
        activeAssetsLock.lock()
        let active = activeAssets?.key == key ? activeAssets?.value : nil
        activeAssetsLock.unlock()
        if useCache, let active { return active }
        if useCache, let result = cache.object(forKey: key) {
            activeAssetsLock.lock(); activeAssets = (key, result); activeAssetsLock.unlock()
            return result
        }
        guard size.width > 0, size.height > 0 else { return nil }
        if useCache, case let .withinInput(contour) = geometry,
           let result = ChromaExpansion.withinAssets(contour: contour, size: size, falloff: falloff, edgeExpansion: edgeExpansion) {
            activeAssetsLock.lock(); activeAssets = (key, result); activeAssetsLock.unlock()
            return result
        }
        if useCache, case let .input(contour) = geometry {
            activeAssetsLock.lock(); let previous = inputAssets; activeAssetsLock.unlock()
            if let previous, previous.size.width == size.width, previous.falloff == falloff, previous.edgeExpansion == edgeExpansion,
               let mapping = InputHeightResize(source: previous.contour, target: contour),
               let images = ChromaExpansion.resize([previous.value.color, previous.value.edge, previous.value.radius],
                   from: previous.size, to: size, mapping: mapping) {
                let result = Assets(color: images[0], edge: images[1], radius: images[2])
                activeAssetsLock.lock(); activeAssets = (key, result); activeAssetsLock.unlock()
                return result
            }
        }
        let base = edgeExpansion == 1 ? nil : assets(geometry: geometry, size: size, falloff: falloff)
        let inputBoundary: ChromaInputBoundary?
        if case let .input(contour) = geometry { inputBoundary = ChromaInputBoundary(contour: contour) }
        else { inputBoundary = nil }
        let scale = geometry.fieldScale
        func distance(_ p: CGPoint) -> Double { inputBoundary?.distance(p) ?? geometry.distance(p, size: size) }
        func pixelBounds(extent: Double, width: Int, height: Int) -> (Range<Int>, Range<Int>) {
            var bounds: CGRect
            switch geometry {
            case .bottom, .windowBottom:
                bounds = CGRect(x: 0, y: size.height - extent, width: size.width, height: extent)
                if case let .windowBottom(layout) = geometry {
                    bounds = CGRect(x: 0, y: size.height - extent - max(layout.leftRadius, layout.rightRadius), width: size.width, height: extent + max(layout.leftRadius, layout.rightRadius))
                }
            case let .withinInput(contour):
                let rect = contour.main.rect
                bounds = CGRect(x: rect.minX - WithinInputField.upperSideSpill, y: rect.maxY - extent - contour.main.radius,
                    width: rect.width + 2 * WithinInputField.upperSideSpill, height: extent + contour.main.radius + 16)
            case let .input(contour): bounds = contour.bounds.insetBy(dx: -extent, dy: -extent)
            case let .notch(layout):
                bounds = CGRect(x: 0, y: 0, width: size.width, height: (layout.notch?.maxY ?? 0) + extent)
            }
            let x0 = max(0, min(width, Int(floor(bounds.minX / size.width * Double(width)))))
            let x1 = max(x0, min(width, Int(ceil(bounds.maxX / size.width * Double(width)))))
            let y0 = max(0, min(height, Int(floor(bounds.minY / size.height * Double(height)))))
            let y1 = max(y0, min(height, Int(ceil(bounds.maxY / size.height * Double(height)))))
            return (x0..<x1, y0..<y1)
        }
        let width = max(2, Int(ceil(size.width))), height = max(2, Int(ceil(size.height)))
        var color = [UInt8](repeating: 0, count: width * height * 4), radius = color
        func hues(_ columns: Int) -> [SIMD3<Double>]? {
            return (0..<columns).map { column in
                let reference = geometry.referencePoint(CGPoint(x: (Double(column) + 0.5) / Double(columns) * size.width, y: 0), size: size)
                return BrighterEdgeStyle.hue(mode: geometry.mode, x: reference.x, y: reference.y)
            }
        }
        let columnHues = hues(width)
        // Keep the field extent fixed and taper the softened blur to clear at its boundary.
        let limit = 320.0 / geometry.mode.fieldScale
        let (columns, rows) = pixelBounds(extent: limit * scale + 16, width: width, height: height)
        if base == nil {
        for y in rows { for x in columns {
            let point = CGPoint(x: (Double(x) + 0.5) / Double(width) * size.width,
                                y: (Double(y) + 0.5) / Double(height) * size.height)
            let d = distance(point), index = (y * width + x) * 4
            // Extend color through the border, then clip after speech transforms to keep it attached.
            let reference = geometry.referencePoint(point, size: size)
            let field = BrighterEdgeStyle.sample(mode: geometry.mode, distance: d / scale,
                x: reference.x, y: reference.y, hue: columnHues?[x])
            let bodyAlpha = GlowTuning.coverage(field.alpha, distance: d / scale, extent: limit, falloff: falloff)
            for c in 0..<3 { color[index + c] = byte(field.color[c]) }
            color[index + 3] = byte(bodyAlpha * withinCoverage(geometry, point))
            // Concentrate the blur at the edge; the far field stays sharp.
            let blur = pow(GlowTuning.coverage(field.blur, distance: d / scale, extent: limit, falloff: falloff), 2)
            // Input maps move with speech. Keep their source field filled and
            // exclude the input only after expansion and deformation.
            radius[index + 3] = d >= 0 || inputBoundary != nil || geometry.appearance == .withinInput ? byte(BackdropBlurFalloff.strength(blur,
                remainingFraction: (limit - d / scale) / (limit * 0.2)) * withinCoverage(geometry, point)) : 0
        } }
        }
        // The one-point rim needs enough subpixel coverage to stay continuous around curved inputs.
        let edgeScale = geometry.mode == .input ? 4.0 : 2.0
        let ew = max(2, Int(ceil(size.width * edgeScale))), eh = max(2, Int(ceil(size.height * edgeScale)))
        var edge = [UInt8](repeating: 0, count: ew * eh * 4)
        let edgeHues = hues(ew)
        let edgeScaleFactor = scale * max(0.000001, edgeExpansion)
        let band = 80.0 / geometry.mode.fieldScale * edgeScaleFactor
        let (edgeColumns, edgeRows) = pixelBounds(extent: band + 16, width: ew, height: eh)
        for y in edgeRows { for x in edgeColumns {
            let point = CGPoint(x: (Double(x) + 0.5) / Double(ew) * size.width,
                                y: (Double(y) + 0.5) / Double(eh) * size.height)
            // This cheap bound avoids walking the exact continuous path away from its narrow edge.
            guard abs(geometry.distance(point, size: size)) <= band + 16 else { continue }
            let d = distance(point)
            guard d <= band, d >= -1 else { continue }
            let reference = geometry.referencePoint(point, size: size)
            let field = BrighterEdgeStyle.sample(mode: geometry.mode, distance: d / edgeScaleFactor,
                x: reference.x, y: reference.y, hue: edgeHues?[x])
            let index = (y * ew + x) * 4
            for c in 0..<3 { edge[index + c] = byte(field.edgeColor[c]) }
            edge[index + 3] = edgeExpansion <= 0 ? 0 : byte(field.edgeAlpha * withinCoverage(geometry, point))
        } }
        guard let colorImage = base?.color ?? image(color, width: width, height: height, size: size),
              let edgeImage = image(edge, width: ew, height: eh, size: size),
              let radiusImage = base?.radius ?? image(radius, width: width, height: height, size: size) else { return nil }
        let result = Assets(color: colorImage, edge: edgeImage, radius: radiusImage)
        guard useCache else { return result }
        cache.setObject(result, forKey: key, cost: color.count + edge.count + radius.count)
        activeAssetsLock.lock(); activeAssets = (key, result); activeAssetsLock.unlock()
        if case let .input(contour) = geometry {
            activeAssetsLock.lock(); inputAssets = (contour, size, falloff, edgeExpansion, result); activeAssetsLock.unlock()
        }
        return result
    }

    private static func withinCoverage(_ geometry: Geometry, _ point: CGPoint) -> Double {
        if case let .withinInput(contour) = geometry { return WithinInputField(contour: contour).coverage(point) }
        return 1
    }

    static func draw(context: inout GraphicsContext, geometry: Geometry, size: CGSize,
                     brightness: Double, distortion: GlowDistortion, expansion: Double = 1, width: Double = 1,
                     tuning: GlowTuning = .init(),
                     preparedImages: [NSImage]? = nil, cycleTime: Double? = nil) {
        guard brightness > 0 else { return }
        if case let .windowBottom(layout) = geometry { context.clip(to: layout.clipPath) }
        if case let .withinInput(contour) = geometry { context.clip(to: WithinInputField(contour: contour).clipPath) }
        let expanded: [NSImage]
        if let preparedImages { expanded = preparedImages }
        else {
            guard let assets = assets(geometry: geometry, size: size, falloff: tuning.falloff),
                  let images = expandedImages(assets: assets, geometry: geometry, size: size,
                      expansion: expansion, edgeHeight: tuning.edgeHeight, softness: tuning.softness) else { return }
            expanded = images
        }
        guard expanded.count == 2 else { return }
        let rect = CGRect(origin: .zero, size: size)
        if width < 1, geometry.mode != .input, geometry.appearance != .withinInput {
            context.clipToLayer { mask in
                let stops = (0...128).map { index in
                    let x = Double(index) / 128
                    return Gradient.Stop(color: .white.opacity(widthCoverage(x * size.width, geometry: geometry, size: size, width: width)), location: x)
                }
                mask.fill(Path(rect), with: .linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)))
            }
        }
        let gradient = tuning.gradients[geometry.appearance.rawValue] ?? GlowGradient()
        let custom = gradient.isDefault ? nil : gradient.sampler
        for pass in 0..<Int(ceil(min(5, brightness))) {
            let opacity = min(1, brightness - Double(pass))
            // Apply gain to the complete body/edge pair, preserving their preview compositing at 100%.
            context.drawLayer { layer in
                layer.opacity = opacity
                layer.drawLayer { body in
                    body.opacity = tuning.bodyOpacity
                    body.concatenate(distortion.transform(in: size, bottom: geometry.preset.settings.style == 0))
                    drawColorImage(expanded[0], context: &body, rect: rect, geometry: geometry, time: cycleTime, custom: custom)
                }
                if tuning.edgeBrightness > 0, tuning.edgeOpacity > 0 {
                    layer.drawLayer { edge in
                        if case let .withinInput(contour) = geometry { edge.clip(to: contour.path) }
                        edge.opacity = tuning.edgeOpacity * min(1, tuning.edgeBrightness)
                        if tuning.edgeBrightness != 1 {
                            var light = ColorMatrix()
                            light.r1 = Float(tuning.edgeBrightness)
                            light.g2 = Float(tuning.edgeBrightness)
                            light.b3 = Float(tuning.edgeBrightness)
                            edge.addFilter(.colorMatrix(light))
                        }
                        if tuning.edgeGlow > 0 {
                            edge.drawLayer { halo in
                                halo.opacity = min(1, tuning.edgeGlow * 0.65)
                                halo.addFilter(.blur(radius: 8 + tuning.edgeGlow * 6))
                                drawColorImage(expanded[1], context: &halo, rect: rect, geometry: geometry, time: cycleTime, custom: custom)
                            }
                        }
                        edge.drawLayer { rim in
                            if tuning.edgeBlur > 0 { rim.addFilter(.blur(radius: tuning.edgeBlur)) }
                            drawColorImage(expanded[1], context: &rim, rect: rect, geometry: geometry, time: cycleTime, custom: custom)
                        }
                    }
                }
            }
        }
    }

    private static func drawColorImage(_ image: NSImage, context: inout GraphicsContext,
                                       rect: CGRect, geometry: Geometry, time: Double?, custom: GlowGradient.Sampler?) {
        let source = Image(nsImage: image).interpolation(.high)
        guard time != nil || custom != nil else { context.draw(source, in: rect); return }
        let time = time ?? 0
        let shading: GraphicsContext.Shading
        if case let .input(contour) = geometry {
            shading = InputGradientCycle.shading(contour: contour, time: time, custom: custom)
        } else {
            let sampleCount = custom == nil ? 96 : 256
            let stops = (0...sampleCount).map { index -> Gradient.Stop in
                let position = Double(index) / Double(sampleCount)
                let reference = geometry.referencePoint(CGPoint(x: position * rect.width, y: 0), size: rect.size)
                let rgb = custom?.color(at: reference.x / 1080 + time / GlowColorCycle.duration)
                    ?? GlowColorCycle.color(position: reference.x / 1080, time: time)
                return .init(color: Color(red: rgb.x, green: rgb.y, blue: rgb.z), location: position)
            }
            shading = .linearGradient(Gradient(stops: stops),
                startPoint: .zero, endPoint: CGPoint(x: rect.width, y: 0))
        }
        context.drawLayer { masked in
            masked.clipToLayer { mask in mask.draw(source, in: rect) }
            if custom != nil {
                masked.fill(Path(rect), with: shading)
                return
            }
            masked.drawLayer { color in
                color.draw(source, in: rect)
                color.blendMode = .color
                color.fill(Path(rect), with: shading)
            }
        }
    }

    static func expandedImages(assets: Assets, geometry: Geometry, size: CGSize,
                               expansion: Double, edgeHeight: Double, softness: Double = 0) -> [NSImage]? {
        var images: [NSImage]
        if case .notch = geometry {
            // A normal ray can cross from a concave join onto the top edge. Resampling
            // that ray creates tabs at thin settings, so evaluate the rim by distance.
            guard let body = ChromaExpansion.image(assets.color, geometry: geometry, size: size, factor: expansion),
                  let scaled = self.assets(geometry: geometry, size: size,
                    edgeExpansion: expansion * edgeHeight) else { return nil }
            images = [body, scaled.edge]
        } else {
            if edgeHeight == 1 {
                guard let scaled = ChromaExpansion.images([assets.color, assets.edge],
                    geometry: geometry, size: size, factor: expansion) else { return nil }
                images = scaled
            } else {
                guard let body = ChromaExpansion.image(assets.color, geometry: geometry, size: size, factor: expansion),
                      let edge = ChromaExpansion.image(assets.edge, geometry: geometry, size: size,
                        factor: expansion * edgeHeight) else { return nil }
                images = [body, edge]
            }
        }
        if softness > 0 {
            guard let softened = blurRepeatingEdges(images[0], radius: softness) else { return nil }
            images[0] = softened
        }
        return Array(images.prefix(2))
    }

    private static let colorBlurContext = CIContext(options: [.cacheIntermediates: false])

    static func blurRepeatingEdges(_ image: NSImage, radius: Double) -> NSImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = ChromaExpansion.filterImage(image) ?? CIImage(cgImage: source)
        let scale = Double(source.width) / image.size.width
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * scale])
            .cropped(to: input.extent)
        guard let output = colorBlurContext.createCGImage(blurred, from: input.extent) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: output)
        bitmap.size = image.size
        let result = NSImage(size: image.size)
        result.addRepresentation(bitmap)
        return result
    }

    private final class RadiusFrame {
        let distortion: GlowDistortion
        let expansion, width: Double
        let exterior: Path
        let image: NSImage
        init(distortion: GlowDistortion, expansion: Double, width: Double, exterior: Path, image: NSImage) {
            self.distortion = distortion; self.expansion = expansion; self.width = width
            self.exterior = exterior; self.image = image
        }
    }
    private static let radiusFrames: NSCache<NSString, RadiusFrame> = {
        let cache = NSCache<NSString, RadiusFrame>()
        cache.countLimit = 8
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func radiusMap(geometry: Geometry, size: CGSize, distortion: GlowDistortion, exterior: Path,
                          expansion: Double = 1, width: Double = 1, falloff: Double = 1) -> NSImage? {
        let key = "\(geometry)-\(size)-\(falloff)" as NSString
        if let frame = radiusFrames.object(forKey: key), frame.distortion == distortion,
           frame.expansion == expansion, frame.width == width, frame.exterior == exterior { return frame.image }
        guard let assets = assets(geometry: geometry, size: size, falloff: falloff),
              let expanded = ChromaExpansion.image(assets.radius, geometry: geometry, size: size, factor: expansion) else { return nil }
        guard let image = ContourMask.transformed(expanded, size: size,
            transform: distortion.transform(in: size, bottom: geometry.preset.settings.style == 0),
            exterior: exterior, illumination: { x in
                let coverage = widthCoverage(x * size.width, geometry: geometry, size: size, width: width)
                if case let .notch(layout) = geometry { return layout.blurSideOpacity(at: x * size.width) * coverage }
                return coverage
            }, bounds: 0...size.width) else { return nil }
        radiusFrames.setObject(RadiusFrame(distortion: distortion, expansion: expansion, width: width,
            exterior: exterior, image: image), forKey: key, cost: Int(ceil(size.width) * ceil(size.height)) * 4)
        return image
    }

    static func widthCoverage(_ x: Double, geometry: Geometry, size: CGSize, width: Double) -> Double {
        guard geometry.appearance != .withinInput, width < 1, geometry.preset.settings.style != 1 else { return 1 }
        let protectedHalf: Double
        if case let .notch(layout) = geometry { protectedHalf = Double(layout.notch?.width ?? 0) / 2 + 8 }
        else { protectedHalf = 0 }
        let half = protectedHalf + (size.width / 2 - protectedHalf) * max(0.25, width)
        let distance = abs(x - size.width / 2)
        let fade = max(8, (half - protectedHalf) * 0.2)
        let t = min(1, max(0, (half - distance) / fade))
        return t * t * (3 - 2 * t)
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int, size: CGSize) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaNonpremultiplied], bytesPerRow: width * 4, bitsPerPixel: 32), let target = bitmap.bitmapData else { return nil }
        bytes.withUnsafeBytes { target.update(from: $0.bindMemory(to: UInt8.self).baseAddress!, count: bytes.count) }
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap.retagging(with: .sRGB) ?? bitmap)
        // Upload before publishing the image to Canvas/CGImage readers on another thread.
        ChromaExpansion.prepareSource(image)
        return image
    }
    private static func byte(_ x: Double) -> UInt8 { UInt8((min(1, max(0, x)) * 255).rounded()) }
    private static func linear(_ x: Double) -> Double { x > 0.04045 ? pow((x + 0.055) / 1.055, 2.4) : x / 12.92 }
    private static func srgb(_ x: Double) -> Double { x > 0.0031308 ? 1.055 * pow(x, 1 / 2.4) - 0.055 : x * 12.92 }
}

/// Uses the same continuous/capsule path that clips the input, including its corner budget.
struct RoundedInputBoundary {
    private let rect: CGRect
    private let straightInset: CGFloat
    private let path: CGPath
    private let segments: [(CGPoint, CGPoint, Double)]

    init(rect: CGRect, radius: CGFloat, cornerStyle: InputCornerStyle = .continuous) {
        self.rect = rect
        straightInset = 2 * radius
        path = InputOutlineBackdrop(rect: rect, cornerRadius: radius, cornerStyle: cornerStyle).path.cgPath
        var edges: [(CGPoint, CGPoint, Double)] = []
        var current = CGPoint.zero, start = CGPoint.zero
        func append(_ point: CGPoint) {
            let a = current, b = point
            current = point
            // The path is symmetric, so distance queries can use its top-right quarter.
            if max(a.x, b.x) < rect.midX - 0.01 || min(a.y, b.y) > rect.midY + 0.01 { return }
            let length = pow(b.x - a.x, 2) + pow(b.y - a.y, 2)
            if length > 0 { edges.append((a, b, length)) }
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: current = element.points[0]; start = current
            case .addLineToPoint: append(element.points[0])
            case .addQuadCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1]
                for i in 1...32 {
                    let t = Double(i) / 32, v = 1 - t
                    append(CGPoint(x: v * v * a.x + 2 * v * t * b.x + t * t * c.x,
                                   y: v * v * a.y + 2 * v * t * b.y + t * t * c.y))
                }
            case .addCurveToPoint:
                let a = current, b = element.points[0], c = element.points[1], d = element.points[2]
                for i in 1...32 {
                    let t = Double(i) / 32, v = 1 - t
                    append(CGPoint(x: v * v * v * a.x + 3 * v * v * t * b.x + 3 * v * t * t * c.x + t * t * t * d.x,
                                   y: v * v * v * a.y + 3 * v * v * t * b.y + 3 * v * t * t * c.y + t * t * t * d.y))
                }
            case .closeSubpath: append(start)
            @unknown default: break
            }
        }
        segments = edges
    }

    func outwardVector(_ point: CGPoint) -> CGPoint {
        if rect.contains(point), path.contains(point) { return .zero }
        let p = CGPoint(x: rect.midX + abs(point.x - rect.midX), y: rect.midY - abs(point.y - rect.midY))
        if p.x <= rect.maxX - straightInset {
            return CGPoint(x: 0, y: max(0, rect.minY - p.y) * (point.y > rect.midY ? 1 : -1))
        }
        if p.y >= rect.minY + straightInset {
            return CGPoint(x: max(0, p.x - rect.maxX) * (point.x < rect.midX ? -1 : 1), y: 0)
        }
        var squared = Double.greatestFiniteMagnitude
        var vector = CGPoint.zero
        for (a, b, length) in segments {
            let dx = b.x - a.x, dy = b.y - a.y
            let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
            let x = p.x - a.x - t * dx, y = p.y - a.y - t * dy
            let candidate = x * x + y * y
            if candidate < squared { squared = candidate; vector = CGPoint(x: x, y: y) }
        }
        return CGPoint(x: vector.x * (point.x < rect.midX ? -1 : 1),
                       y: vector.y * (point.y > rect.midY ? -1 : 1))
    }

    func distance(_ point: CGPoint) -> Double {
        let p = CGPoint(x: rect.midX + abs(point.x - rect.midX), y: rect.midY - abs(point.y - rect.midY))
        if p.x <= rect.maxX - straightInset { return rect.minY - p.y }
        if p.y >= rect.minY + straightInset { return p.x - rect.maxX }
        var squared = Double.greatestFiniteMagnitude
        for (a, b, length) in segments {
            let dx = b.x - a.x, dy = b.y - a.y
            let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
            let x = p.x - a.x - t * dx, y = p.y - a.y - t * dy
            squared = min(squared, x * x + y * y)
        }
        let result = sqrt(squared)
        return rect.contains(p) && path.contains(p) ? -result : result
    }
}
