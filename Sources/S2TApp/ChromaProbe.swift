import AppKit
import SwiftUI
import S2TCore

@MainActor enum ChromaProbe {
    static func run() throws {
        try verifyColorCycle()
        let display = GlowDisplay(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), safeTop: 32,
            topLeft: CGRect(x: 0, y: 1137, width: 780, height: 32),
            topRight: CGRect(x: 1020, y: 1137, width: 780, height: 32))
        let notch = TopGlowLayout(display: display)
        let input = CGRect(x: 400, y: 400, width: 940 * 0.83254075, height: 300 * 0.83254075)
        let fixtures: [(ChromaAppearance.Geometry, CGSize, Double)] = [
            (.bottom, CGSize(width: 1800, height: GlowProfile.extent), 12),
            (.input(input, 115 * 0.83254075), CGSize(width: 1600, height: 1100), 18 * 0.83254075),
            (.notch(notch), notch.frame.size, 12 * 240 / 411.25)
        ]
        for (geometry, size, radius) in fixtures {
            try autoreleasepool {
            guard let assets = ChromaAppearance.assets(geometry: geometry, size: size) else {
                throw failure("Chroma generated fields are missing.")
            }
            for image in [assets.color, assets.edge, assets.radius] {
                guard image.size == size, let bitmap = image.representations.first as? NSBitmapImageRep,
                      bitmap.size == size, let bytes = bitmap.bitmapData else { throw failure("Chroma image dimensions differ from the field.") }
                var maximum: UInt8 = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide { maximum = max(maximum, bytes[y * bitmap.bytesPerRow + x * 4 + 3]) }
                }
                guard maximum > 0 else { throw failure("A Chroma field is empty for \(geometry.preset.style).") }
            }
            let root = ProgressiveBackdropView(frame: CGRect(origin: .zero, size: size))
            var profile = GlowProfile(energy: 1, heights: [3], sweepStrength: 1.3)
            switch geometry {
            case .bottom: break
            case let .notch(layout): profile.topLayout = layout
            case let .input(rect, corner, cornerStyle): profile.inputOutline = InputOutlineBackdrop(rect: rect, cornerRadius: corner, cornerStyle: cornerStyle, strength: 1.3)
            }
            root.profile = profile
            let sampler = root.layer?.sublayers?.first
            guard let filter = sampler?.filters?.first as? NSObject,
                  let actual = filter.value(forKey: "inputRadius") as? Double,
                  abs(actual - radius * GlowSpeechEnvelope.blurGain(2)) < 0.000001, sampler?.opacity == 1 else {
                throw failure("\(geometry.preset.style) did not submit its bounded native blur radius at maximum intensity.")
            }
            let sourceMap = GlowBackdrop.mask(profile: profile, size: size)
            guard let rawMask = filter.value(forKey: "inputMaskImage"),
                  CFGetTypeID(rawMask as CFTypeRef) == CGImage.typeID else { throw failure("Missing native Chroma mask.") }
            let submitted = rawMask as! CGImage
            guard
                  let original = sourceMap?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  submitted.width == original.width, submitted.height == original.height,
                  submitted.dataProvider?.data as Data? == original.dataProvider?.data as Data? else {
                throw failure("The approved preview map was altered before native blur submission.")
            }
            root.profile = GlowProfile(energy: 0, heights: profile.heights, topLayout: profile.topLayout,
                inputOutline: profile.inputOutline, sweepStrength: 1.3)
            guard sampler?.isHidden == false,
                  abs(((sampler?.filters?.first as? NSObject)?.value(forKey: "inputRadius") as? Double ?? -1) - radius * GlowSpeechEnvelope.blurGain(0.3)) < 0.000001 else {
                throw failure("The quiet amount did not reach the native blur response.")
            }
            var inactive = profile
            inactive.active = false
            root.profile = inactive
            guard sampler?.isHidden == true,
                  (sampler?.filters?.first as? NSObject)?.value(forKey: "inputRadius") as? Double == 0 else {
                throw failure("Processing retained live blur.")
            }
            if ProcessInfo.processInfo.environment["S2T_GENERATED_GLOW_FIXTURE_DIR"] != nil {
                let view: AnyView
                switch geometry {
                case .bottom:
                    view = AnyView(BottomGlow(level: 1, strength: 1.3, phase: .recording,
                        timeOverride: 0, reduceMotionOverride: true, reduceTransparencyOverride: true,
                        renderedProfile: profile))
                case let .notch(layout):
                    view = AnyView(TopGlow(renderedProfile: profile, showsBackdrop: false, layout: layout,
                        strength: 1.3, phase: .recording, levelProvider: { 1 }, timeOverride: 0,
                        reduceTransparencyOverride: true, reduceMotionOverride: true))
                case let .input(rect, corner, cornerStyle):
                    let state = AppState(preview: true)
                    state.phase = .recording
                    state.glowStrength = 1.3
                    let layout = InputOutlineLayout()
                    layout.outlineRect = rect
                    layout.cornerRadius = corner
                    layout.cornerStyle = cornerStyle
                    view = AnyView(InputOutline(renderedProfile: profile, showsBackdrop: false, state: state,
                        layout: layout, reduceMotionOverride: true, timeOverride: 0, reduceTransparencyOverride: true))
                }
                for light in [false, true] {
                    let background = Color(white: light ? 0.94 : 0.08)
                    try GlowFixture.write(ZStack { background; view }, size: size,
                        name: "chroma-\(geometry.preset.style.lowercased())-maximum-\(light ? "light" : "dark")")
                }
            }
            print("PASS: \(geometry.preset.style) cached color/edge fields, base \(radius)-point native radius with double loud gain, aligned expanded map and thirty-percent quiet blur.")
            }
        }
        // The source Bottom blur is not effect-blurred: compare the independently sampled spatial map.
        guard let image = ChromaAppearance.assets(geometry: .bottom, size: fixtures[0].1)?.radius,
              let bitmap = image.representations.first as? NSBitmapImageRep else { throw failure("Missing Bottom source map.") }
        let x = bitmap.pixelsWide / 2, y = bitmap.pixelsHigh - 20
        let size = fixtures[0].1
        let position = (Double(x) + 0.5) / Double(bitmap.pixelsWide)
        let distance = size.height * (1 - (Double(y) + 0.5) / Double(bitmap.pixelsHigh))
        let original = pow(max(0, 1 - distance / 265), 2.3) * pow(sin(.pi * position), 0.48)
        let expected = 0.6 * sqrt(original)
        guard abs((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1) - expected) <= 1 / 255.0 else {
            throw failure("The Bottom native map differs from the softened approved distance field.")
        }
    }

    static func verifyColorCycle() throws {
        for rect in [CGRect(x: 40, y: 40, width: 600, height: 60),
                     CGRect(x: 40, y: 40, width: 380, height: 220)] {
            let samples = InputGradientCycle.samples(rect: rect, radius: min(30, rect.height / 2))
            func distance(at angle: Double) -> Double {
                samples.min(by: { abs($0.angle - angle) < abs($1.angle - angle) })!.distance
            }
            let opposite = abs(distance(at: 0.25) - distance(at: 0.75))
            guard abs(opposite - 0.5) < 0.01,
                  samples.first!.distance == samples.last!.distance else {
                throw failure("Input colors must follow a closed perimeter with opposite top/bottom phases")
            }
            for pair in zip(samples, samples.dropFirst()) {
                let difference = abs(pair.0.distance - pair.1.distance)
                guard min(difference, abs(1 - difference)) < 0.01 else {
                    throw failure("Input gradient jumps at a rounded corner or the loop seam")
                }
            }
        }
        print("PASS: input palette follows capsule and tall-input perimeters continuously, with opposite top/bottom phases.")
        let fixtureSize = CGSize(width: 80, height: 60)
        guard let solid = ContourMask.render(size: fixtureSize, draw: { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: fixtureSize))
        }), let blurred = ChromaAppearance.blurRepeatingEdges(solid, radius: 20),
              let cg = blurred.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw failure("Missing repeated-edge blur fixture")
        }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.99 else {
                throw failure("Gradient blur introduces transparency at a solid image edge")
            }
        } }
        print("PASS: gradient blur repeats edge pixels through a 20-point blur without transparent gaps.")
        let size = AppearancePreviewScene.size
        for mode in [GlowAppearance.bottom, .aroundNotch, .aroundInput] {
            let geometry = AppearancePreviewScene.geometry(mode)
            let request = ChromaFrameRequest(geometry: geometry, size: size,
                profile: GlowProfile(energy: 0.55, heights: [3]), brightness: 1, backdrop: false)
            guard let frame = ChromaFrame.render(request) else { throw failure("Missing cycle fixture") }
            func pixels(_ time: Double?, speed: Double = 0.1) throws -> [UInt8] {
                var profile = request.profile
                profile.response.tuning.gradientSpeed = speed
                let timedFrame = ChromaFrame(request: ChromaFrameRequest(geometry: geometry, size: size,
                    profile: profile, brightness: request.brightness, backdrop: false), images: frame.images, radiusMap: nil)
                let renderer = ImageRenderer(content: ChromaFrameCanvas(frame: timedFrame, cycleTime: time)
                    .frame(width: size.width, height: size.height))
                renderer.scale = 1
                guard let image = renderer.cgImage else { throw failure("Missing generated cycle rendering") }
                var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
                let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(image, in: CGRect(origin: .zero, size: size))
                    return true
                }
                guard success else { throw failure("Missing cycle bitmap context") }
                return bytes
            }
            let stopped = try pixels(0, speed: 0)
            func maximumDifference(_ other: [UInt8]) -> Int {
                zip(stopped, other).map { abs(Int($0) - Int($1)) }.max() ?? 0
            }
            let frozenDifference = maximumDifference(try pixels(2, speed: 0))
            let loopDifference = maximumDifference(try pixels(1, speed: 1))
            let movingDifference = maximumDifference(try pixels(0.5, speed: 1))
            guard frozenDifference <= 1, loopDifference <= 1, movingDifference > 4 else {
                throw failure("Gradient speed must stop at zero and complete one cycle per second at maximum for \(mode): freeze \(frozenDifference), wrap \(loopDifference), movement \(movingDifference)")
            }
            print("PASS: \(mode) rendered zero-speed freeze and one cycle per second.")
            let original = try pixels(nil), start = try pixels(0), middle = try pixels(2)
            let end = try pixels(GlowColorCycle.duration), before = try pixels(GlowColorCycle.duration - 1.0 / 60)
            var changes = 0
            var visibleSamples = 0
            var colorShift = 0.0
            for index in start.indices {
                if index % 4 == 3 {
                    if start[index] >= 32 {
                        visibleSamples += 1
                        let difference = (1...3).map { abs(Int(start[index - $0]) - Int(middle[index - $0])) }.max()!
                        colorShift += Double(difference) * 255 / Double(start[index])
                    }
                    for pixels in [start, middle] where pixels[index] >= 8 {
                        let brightest = max(pixels[index - 3], pixels[index - 2], pixels[index - 1])
                        guard Double(brightest) >= Double(pixels[index]) * 0.6 else {
                            throw failure("Color cycling darkened the translucent fade into a black border for \(mode)")
                        }
                    }
                    guard abs(Int(original[index]) - Int(start[index])) <= 1,
                          abs(Int(start[index]) - Int(middle[index])) <= 1 else {
                        throw failure("Color cycling changed the glow boundary or opacity for \(mode)")
                    }
                } else if abs(Int(start[index]) - Int(middle[index])) > 4 { changes += 1 }
                guard abs(Int(start[index]) - Int(end[index])) <= 1,
                      abs(Int(start[index]) - Int(before[index])) <= 5 else {
                    throw failure("Color cycle has a visible wrap discontinuity for \(mode)")
                }
            }
            guard visibleSamples > 0, colorShift / Double(visibleSamples) >= 50 else {
                throw failure("Gradient movement is too subtle after two seconds for \(mode): \(colorShift / Double(max(1, visibleSamples)))")
            }
            print("PASS: \(mode) two-second average color shift \(Int(colorShift / Double(visibleSamples)))/255.")
            guard changes > 100 else { throw failure("The rendered gradient did not cycle for \(mode)") }
            print("PASS: \(mode) generated color cycle changes colors, preserves alpha and joins seamlessly after \(GlowColorCycle.duration) seconds.")
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "ChromaProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
